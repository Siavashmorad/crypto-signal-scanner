import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import 'android_notification_service.dart';
import 'auto_trade_history.dart';
import 'fa_labels.dart';
import 'live_trading_gate.dart';
import 'local_trade_store.dart';
import 'order_sizing.dart';
import 'position_tracker.dart';
import 'signal_journal.dart';
import 'symbol_rules_service.dart';
import 'tabdeal_api.dart';
import 'tabdeal_trade.dart';

/// Hard safety cap — must not increase (matches backend MAX_POSITION_NOTIONAL_USDT).
const double kMaxPositionNotionalUsdt = 50.0;

/// Minimum score for unattended SPOT auto entry (user must enable setting).
const double kAutoTradeMinScore = 90.0;

/// Automatic SPOT entries for very-strong opportunities only.
/// Does NOT bypass Live Gate, emergency stop, risk, or notional cap.
/// Does NOT place cloud/FCM/TV orders.
class SpotAutoTrader {
  SpotAutoTrader({
    required this.api,
    LocalTradeStore? tradeStore,
    SymbolRulesService? rules,
    OrderSizingEngine? sizing,
    LiveTradingGate? gate,
    SignalJournal? journal,
    AutoTradeHistory? history,
    AndroidNotificationService? androidNotify,
  })  : tradeStore = tradeStore ?? LocalTradeStore(),
        rules = rules ?? SymbolRulesService(api),
        sizing = sizing ?? OrderSizingEngine(),
        gate = gate ?? LiveTradingGate(),
        journal = journal ?? SignalJournal(),
        history = history ?? AutoTradeHistory(),
        androidNotify = androidNotify ?? AndroidNotificationService();

  final TabdealApi api;
  final LocalTradeStore tradeStore;
  final SymbolRulesService rules;
  final OrderSizingEngine sizing;
  final LiveTradingGate gate;
  final SignalJournal journal;
  final AutoTradeHistory history;
  final AndroidNotificationService androidNotify;

  /// Returns true if user enabled auto strong SPOT trades.
  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('auto_strong_spot_trade') ?? false;
  }

  static String fingerprintOf(MarketSignal s) {
    final entryBand = s.entry <= 0
        ? 0
        : s.entry >= 1
            ? (s.entry * 100).round()
            : (s.entry * 1e6).round();
    final scoreBand = (s.confidence / 5).floor() * 5;
    return '${s.symbol.toUpperCase()}:${s.side.toUpperCase()}:$scoreBand:$entryBand';
  }

  /// Evaluate and optionally open at most one SPOT trade from ranked signals.
  Future<AutoTradeRecord?> tryAutoOpen({
    required List<MarketSignal> ranked,
    required bool tabdealLinked,
  }) async {
    if (!await isEnabled()) return null;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('emergency_stop') ?? false) return null;
    if (prefs.getBool('prefer_futures_execution') ?? false) return null;

    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!has || !live) return null;

    MarketSignal? best;
    for (final s in ranked) {
      if (s.confidence < kAutoTradeMinScore) continue;
      // SPOT auto path: only LONG / buy. Bearish never becomes a short order.
      if (s.side.toUpperCase() != 'LONG') continue;
      if (s.entry <= 0 || s.stopLoss <= 0 || s.tp1 <= 0) continue;
      // LONG-only: stop must be below entry.
      if (s.stopLoss >= s.entry) continue;
      final risk = (s.entry - s.stopLoss).abs();
      final reward = (s.tp1 - s.entry).abs();
      if (risk <= 0 || reward / risk < 1.2) continue;
      if (await history.hasOpenSymbol(s.symbol)) continue;
      final fp = fingerprintOf(s);
      if (await history.wasTradedFingerprint(fp)) continue;
      best = s;
      break;
    }
    if (best == null) return null;

    final journalEntries = await journal.load();
    final q = best.confidence >= 85
        ? 'A+'
        : best.confidence >= 72
            ? 'A'
            : best.confidence >= 58
                ? 'B'
                : 'C';
    final gateResult = gate.evaluate(
      journal: journalEntries,
      quality: q,
      regime: 'UNKNOWN',
      userLiveEnabled: live,
      dataHealthy: tabdealLinked,
    );
    if (!gateResult.allowLive) return null;

    // Already filtered to LONG above.
    const side = 'BUY';
    const isBuy = true;

    final client = TabdealTradeClient(
      apiKey: await tradeStore.apiKey(),
      apiSecret: await tradeStore.apiSecret(),
    );
    try {
      final filters = await rules.filtersFor(best.symbol);
      final snap = await client.accountSnapshot();
      final available = snap.available ? snap.freeQuote(best.symbol) : 0.0;
      final configured = await tradeStore.defaultQty();

      final size = sizing.compute(
        filters: filters,
        configuredQty: configured,
        currentPrice: best.entry,
        availableQuote: available,
        riskPercent: 0.01,
        entry: best.entry,
        stopLoss: best.stopLoss,
        isBuy: isBuy,
        maxRiskQuote: kMaxPositionNotionalUsdt,
      );
      if (!size.canSubmit) return null;
      final notional = size.finalQty * best.entry;
      if (notional > kMaxPositionNotionalUsdt + 0.01) return null;

      final res = await client.marketOrder(
        symbol: best.symbol,
        side: side,
        quantity: size.finalQty,
      );
      final tracked = TrackedOrder.fromApi(res, fallbackSymbol: best.symbol);
      final fillPx = tracked.avgPrice > 0 ? tracked.avgPrice : best.entry;

      final id =
          'auto_${best.symbol}_${DateTime.now().millisecondsSinceEpoch}';
      final record = AutoTradeRecord(
        id: id,
        symbol: best.symbol.toUpperCase().replaceAll('_', ''),
        side: best.side,
        score: best.confidence,
        entry: fillPx,
        stopLoss: best.stopLoss,
        takeProfit: best.tp1,
        qty: size.finalQty,
        openedAt: DateTime.now(),
        status: 'open',
        orderId: tracked.orderId,
      );
      await history.add(record);
      await history.rememberFingerprint(fingerprintOf(best));

      await journal.record(JournalEntry.fromSignal(
        best,
        quality: q,
        score: best.confidence,
        confidence: best.confidence,
        reasons: 'auto_spot fill ${tracked.orderId ?? ''}',
        mode: JournalMode.live,
        isLive: true,
      ));

      final body = '🔔 معامله خودکار باز شد\n\n'
          'نماد: ${record.symbol}\n'
          'نوع: ${FaLabels.side(record.side)}\n'
          'امتیاز تحلیل: ${record.score.toStringAsFixed(0)} از ۱۰۰\n'
          'قیمت ورود: ${record.entry}\n'
          'حد ضرر: ${record.stopLoss}\n'
          'حد سود: ${record.takeProfit}\n'
          'مقدار: ${record.qty}';
      try {
        await androidNotify.showOpportunity(
          id: record.id.hashCode & 0x7fffffff,
          title: 'معامله خودکار باز شد',
          body: body,
          payload: AndroidNotificationService.payloadFor(
            symbol: record.symbol,
            side: record.side,
          ),
        );
      } catch (_) {}

      return record;
    } catch (_) {
      return null;
    } finally {
      client.dispose();
    }
  }

  /// Monitor open auto trades; close on TP/SL using current market trades.
  Future<List<AutoTradeRecord>> monitorAndClose() async {
    final open = await history.openTrades();
    if (open.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('emergency_stop') ?? false) return const [];

    final closed = <AutoTradeRecord>[];
    final has = await tradeStore.hasKeys();
    if (!has) return const [];

    final client = TabdealTradeClient(
      apiKey: await tradeStore.apiKey(),
      apiSecret: await tradeStore.apiSecret(),
    );
    try {
      for (final t in open) {
        List<TradePoint> trades = const [];
        try {
          trades = await api.trades(t.symbol, limit: 50);
        } catch (_) {}
        if (trades.isEmpty) continue;
        final last = trades.last.price;
        if (last <= 0) continue;

        final isLong = t.side.toUpperCase() == 'LONG';
        String? reason;
        if (isLong) {
          if (last <= t.stopLoss) reason = 'SL';
          if (last >= t.takeProfit) reason = 'TP';
        } else {
          if (last >= t.stopLoss) reason = 'SL';
          if (last <= t.takeProfit) reason = 'TP';
        }
        if (reason == null) continue;

        final closeSide = isLong ? 'SELL' : 'BUY';
        try {
          await client.marketOrder(
            symbol: t.symbol,
            side: closeSide,
            quantity: t.qty,
          );
        } catch (_) {
          continue;
        }

        final pnl = isLong
            ? (last - t.entry) * t.qty
            : (t.entry - last) * t.qty;
        await history.close(
          t.id,
          exitPrice: last,
          pnlQuote: pnl,
          exitReason: reason,
        );
        final updated = t.copyWith(
          closedAt: DateTime.now(),
          exitPrice: last,
          pnlQuote: pnl,
          exitReason: reason,
          status: 'closed',
        );
        closed.add(updated);

        final dur = updated.closedAt!.difference(t.openedAt);
        final mins = dur.inMinutes;
        final body = '🔔 معامله خودکار بسته شد\n\n'
            'نماد: ${t.symbol}\n'
            'نتیجه: ${FaLabels.pnlLabel(pnl)}\n'
            'قیمت ورود: ${t.entry}\n'
            'قیمت خروج: $last\n'
            'سود/زیان: ${pnl.toStringAsFixed(4)}\n'
            'مدت معامله: $mins دقیقه\n'
            'دلیل خروج: ${FaLabels.exitReason(reason)}';
        try {
          await androidNotify.showOpportunity(
            id: (t.id.hashCode ^ 0x55) & 0x7fffffff,
            title: 'معامله خودکار بسته شد',
            body: body,
            payload: AndroidNotificationService.payloadFor(
              symbol: t.symbol,
              side: t.side,
            ),
          );
        } catch (_) {}
      }
    } finally {
      client.dispose();
    }
    return closed;
  }
}
