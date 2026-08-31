import 'dart:async';

import '../models/market_data.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

/// User-facing focus status (Persian-first labels live in the UI).
enum FocusAction {
  /// Structure is strong enough to consider entry (still analysis-only).
  startNow,

  /// Keep watching current focus; not ready yet.
  wait,

  /// Current focus weakened; service will pick another symbol.
  switchFocus,

  /// No qualified LONG setup across the scanned universe.
  noSetup,
}

/// Snapshot of the single coin the AI is currently focused on.
class FocusSnapshot {
  final String? symbol;
  final FocusAction action;
  final double score;
  final String side;
  final double? entry;
  final double? stopLoss;
  final double? tp1;
  final double riskReward;
  final String timeframe;
  final List<String> reasonsFa;
  final DateTime at;
  final String dataSource;

  const FocusSnapshot({
    required this.symbol,
    required this.action,
    required this.score,
    required this.side,
    this.entry,
    this.stopLoss,
    this.tp1,
    required this.riskReward,
    required this.timeframe,
    required this.reasonsFa,
    required this.at,
    required this.dataSource,
  });

  bool get isLong => side.toUpperCase() == 'LONG';
}

/// Picks ONE strong SPOT-LONG candidate, re-checks candles, and switches
/// when the focus weakens. Never places orders. Uses api1.tabdeal.org only
/// via [ScannerService] / [TabdealApi].
class FocusCoinService {
  FocusCoinService({
    TabdealApi? api,
    ScannerService? scanner,
  })  : api = api ?? TabdealApi(),
        scanner = scanner ?? ScannerService(api ?? TabdealApi());

  final TabdealApi api;
  final ScannerService scanner;

  /// Minimum confidence to become the active focus.
  static const double minFocusScore = 62;

  /// Below this on a re-check → drop focus and search for another coin.
  static const double dropScore = 55;

  /// High enough to surface "الان شروع کن" (still not an order).
  static const double startNowScore = 72;

  String? _focusSymbol;

  String? get focusSymbol => _focusSymbol;

  /// Run a full scan, keep or switch focus, return a clear action.
  Future<FocusSnapshot> tick({
    Duration timeframe = const Duration(minutes: 15),
    int maxSymbols = 20,
  }) async {
    final now = DateTime.now();
    final all = await scanner.scanAll(
      timeframe: timeframe,
      maxSymbols: maxSymbols,
      maxSignals: 12,
      preferSpot: true,
    );

    // SPOT-safe: only LONG candidates for "start now".
    final longs = all
        .where((s) => s.side.toUpperCase() == 'LONG')
        .where((s) => s.confidence >= minFocusScore)
        .toList();

    if (longs.isEmpty) {
      _focusSymbol = null;
      return FocusSnapshot(
        symbol: null,
        action: FocusAction.noSetup,
        score: 0,
        side: 'NONE',
        riskReward: 0,
        timeframe: timeframe.inMinutes >= 60 ? '1h' : '${timeframe.inMinutes}m',
        reasonsFa: const [
          'هیچ ارز LONG با امتیاز کافی پیدا نشد',
          'فیلترها دست‌نخورده ماندند (بدون تورم امتیاز)',
        ],
        at: now,
        dataSource: scanner.dataSource,
      );
    }

    // Prefer keeping current focus if still healthy.
    MarketSignal? current;
    if (_focusSymbol != null) {
      for (final s in longs) {
        if (s.symbol == _focusSymbol) {
          current = s;
          break;
        }
      }
      // Re-scan single symbol if it fell out of the batch list.
      if (current == null) {
        try {
          current = await scanner.scanSymbol(_focusSymbol!, timeframe);
          if (current != null &&
              current.side.toUpperCase() != 'LONG') {
            current = null;
          }
        } catch (_) {
          current = null;
        }
      }
    }

    if (current != null && current.confidence >= dropScore) {
      _focusSymbol = current.symbol;
      final start = current.confidence >= startNowScore;
      return _fromSignal(
        current,
        start ? FocusAction.startNow : FocusAction.wait,
        now,
        keepReasons: true,
      );
    }

    // Switch focus to the strongest LONG.
    final best = longs.first;
    final switched = _focusSymbol != null && _focusSymbol != best.symbol;
    _focusSymbol = best.symbol;
    final start = best.confidence >= startNowScore;
    return _fromSignal(
      best,
      switched
          ? FocusAction.switchFocus
          : (start ? FocusAction.startNow : FocusAction.wait),
      now,
      keepReasons: false,
      switched: switched,
    );
  }

  FocusSnapshot _fromSignal(
    MarketSignal s,
    FocusAction action,
    DateTime at, {
    required bool keepReasons,
    bool switched = false,
  }) {
    final reasons = <String>[
      if (switched) 'فوکوس قبلی ضعیف شد → تعویض به ${s.symbol}',
      if (action == FocusAction.startNow)
        'ساختار کندل + امتیاز بالا: بررسی ورود اسپات'
      else if (action == FocusAction.wait)
        'هنوز صبر کن؛ امتیاز یا هم‌زمانی کامل نیست'
      else if (action == FocusAction.switchFocus)
        'در حال جابه‌جایی فوکوس',
      'امتیاز ${s.confidence.toStringAsFixed(0)} / ۱۰۰',
      'R:R ≈ 1:${s.riskReward.toStringAsFixed(1)}',
      'فقط تحلیل — بدون سفارش خودکار',
    ];
    return FocusSnapshot(
      symbol: s.symbol,
      action: action,
      score: s.confidence,
      side: s.side,
      entry: s.entry,
      stopLoss: s.stopLoss,
      tp1: s.tp1,
      riskReward: s.riskReward,
      timeframe: s.timeframe,
      reasonsFa: reasons,
      at: at,
      dataSource: scanner.dataSource,
    );
  }

  void clearFocus() => _focusSymbol = null;
}
