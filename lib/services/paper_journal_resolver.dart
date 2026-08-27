import '../models/market_data.dart';
import 'binance_public.dart';
import 'paper_forward.dart';
import 'signal_journal.dart';
import 'tabdeal_api.dart';

/// Resolves pending paper journal entries against real subsequent market data.
/// Does not place orders. Used so Live Gate can see closed sample counts.
class PaperJournalResolver {
  PaperJournalResolver({
    required this.api,
    BinancePublic? binance,
    PaperForwardResolver? forward,
  })  : binance = binance ?? BinancePublic(),
        forward = forward ?? PaperForwardResolver();

  final TabdealApi api;
  final BinancePublic binance;
  final PaperForwardResolver forward;

  static Duration parseTimeframe(String tf) {
    final s = tf.trim().toLowerCase();
    if (s.endsWith('m')) {
      final n = int.tryParse(s.substring(0, s.length - 1)) ?? 15;
      return Duration(minutes: n);
    }
    if (s.endsWith('h')) {
      final n = int.tryParse(s.substring(0, s.length - 1)) ?? 1;
      return Duration(hours: n);
    }
    if (s.endsWith('d')) {
      final n = int.tryParse(s.substring(0, s.length - 1)) ?? 1;
      return Duration(days: n);
    }
    return const Duration(minutes: 15);
  }

  /// Returns how many pending entries were closed (win/loss/expired/breakeven).
  Future<int> resolvePending(
    SignalJournal journal, {
    int maxBars = 48,
    int tradeLimit = 500,
  }) async {
    final all = await journal.load();
    final pending =
        all.where((e) => e.outcome == JournalOutcome.pending).toList();
    if (pending.isEmpty) return 0;

    var closed = 0;
    final bySymbol = <String, List<JournalEntry>>{};
    for (final e in pending) {
      bySymbol.putIfAbsent(e.symbol.toUpperCase(), () => []).add(e);
    }

    for (final entry in bySymbol.entries) {
      final symbol = entry.key;
      List<TradePoint> trades = <TradePoint>[];
      try {
        trades = await api.trades(symbol, limit: tradeLimit);
      } catch (_) {}
      if (trades.length < 5) {
        try {
          final bt = await binance.trades(symbol, limit: tradeLimit);
          if (bt.length > trades.length) trades = bt;
        } catch (_) {}
      }
      if (trades.length < 2) continue;

      for (final e in entry.value) {
        final tf = parseTimeframe(e.timeframe);
        final candles = api.candlesFromTrades(trades, tf);
        if (candles.length < 2) continue;
        final resolved = forward.resolve(e, candles, maxBars: maxBars);
        if (resolved.outcome == JournalOutcome.pending) continue;
        await journal.updateOutcome(
          e.id,
          outcome: resolved.outcome,
          rMultiple: resolved.rMultiple,
          durationBars: resolved.durationBars,
        );
        closed++;
      }
    }
    return closed;
  }
}
