import '../models/market_data.dart';

/// One paper trade outcome from real OHLCV path (never hits exchange).
enum PaperOutcome { win, loss, timeout, skip }

class PaperTradeRecord {
  final DateTime timestamp;
  final String symbol;
  final String side;
  final double entry;
  final double stopLoss;
  final double tp1;
  final double riskReward;
  final PaperOutcome outcome;
  final double rMultiple;
  final double pnlPrice;
  final String reason;

  const PaperTradeRecord({
    required this.timestamp,
    required this.symbol,
    required this.side,
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.riskReward,
    required this.outcome,
    required this.rMultiple,
    required this.pnlPrice,
    this.reason = '',
  });
}

class PaperMetrics {
  final int signals;
  final int trades;
  final int wins;
  final int losses;
  final int skips;
  final double avgR;
  final double avgWinR;
  final double avgLossR;
  final double profitFactor;
  final double expectancy;
  final double maxDrawdownR;
  final bool insufficientData;
  final String note;

  const PaperMetrics({
    required this.signals,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.skips,
    required this.avgR,
    required this.avgWinR,
    required this.avgLossR,
    required this.profitFactor,
    required this.expectancy,
    required this.maxDrawdownR,
    this.insufficientData = false,
    this.note = '',
  });

  factory PaperMetrics.insufficient(String why) => PaperMetrics(
        signals: 0,
        trades: 0,
        wins: 0,
        losses: 0,
        skips: 0,
        avgR: 0,
        avgWinR: 0,
        avgLossR: 0,
        profitFactor: 0,
        expectancy: 0,
        maxDrawdownR: 0,
        insufficientData: true,
        note: why,
      );
}

/// Offline evaluation: walk candles, apply fixed R/R hits. No live orders.
class PaperEvaluator {
  /// Simulate LONG/SHORT from [signals] against subsequent [candles].
  /// Each signal is a MarketSignal-like tuple at candle index.
  static PaperMetrics evaluate({
    required List<Candle> candles,
    required List<({int index, String side, double entry, double sl, double tp1})> signals,
    int maxBars = 48,
  }) {
    if (candles.length < 30 || signals.isEmpty) {
      return PaperMetrics.insufficient(
        'INSUFFICIENT DATA: need ≥30 candles and ≥1 signal sample',
      );
    }

    final records = <PaperTradeRecord>[];
    for (final s in signals) {
      if (s.index < 0 || s.index >= candles.length - 2) continue;
      final risk = (s.entry - s.sl).abs();
      if (risk <= 0) {
        records.add(PaperTradeRecord(
          timestamp: DateTime.fromMillisecondsSinceEpoch(candles[s.index].timestampMs),
          symbol: 'LOCAL',
          side: s.side,
          entry: s.entry,
          stopLoss: s.sl,
          tp1: s.tp1,
          riskReward: 0,
          outcome: PaperOutcome.skip,
          rMultiple: 0,
          pnlPrice: 0,
          reason: 'invalid SL distance',
        ));
        continue;
      }

      PaperOutcome outcome = PaperOutcome.timeout;
      double exit = s.entry;
      final isLong = s.side.toUpperCase() == 'LONG' || s.side.toUpperCase() == 'BUY';

      final end = (s.index + maxBars).clamp(0, candles.length - 1);
      for (var i = s.index + 1; i <= end; i++) {
        final c = candles[i];
        if (isLong) {
          if (c.low <= s.sl) {
            outcome = PaperOutcome.loss;
            exit = s.sl;
            break;
          }
          if (c.high >= s.tp1) {
            outcome = PaperOutcome.win;
            exit = s.tp1;
            break;
          }
        } else {
          if (c.high >= s.sl) {
            outcome = PaperOutcome.loss;
            exit = s.sl;
            break;
          }
          if (c.low <= s.tp1) {
            outcome = PaperOutcome.win;
            exit = s.tp1;
            break;
          }
        }
      }

      final pnl = isLong ? (exit - s.entry) : (s.entry - exit);
      final r = pnl / risk;
      records.add(PaperTradeRecord(
        timestamp: DateTime.fromMillisecondsSinceEpoch(candles[s.index].timestampMs),
        symbol: 'LOCAL',
        side: s.side,
        entry: s.entry,
        stopLoss: s.sl,
        tp1: s.tp1,
        riskReward: ((s.tp1 - s.entry).abs() / risk),
        outcome: outcome,
        rMultiple: r,
        pnlPrice: pnl,
      ));
    }

    final trades = records.where((r) => r.outcome != PaperOutcome.skip).toList();
    final wins = trades.where((r) => r.outcome == PaperOutcome.win).toList();
    final losses = trades.where((r) => r.outcome == PaperOutcome.loss).toList();
    final skips = records.where((r) => r.outcome == PaperOutcome.skip).length;

    if (trades.isEmpty) {
      return PaperMetrics.insufficient('INSUFFICIENT DATA: no completed paper trades');
    }

    double sumR = 0, sumWin = 0, sumLoss = 0;
    for (final t in trades) {
      sumR += t.rMultiple;
    }
    for (final t in wins) {
      sumWin += t.rMultiple;
    }
    for (final t in losses) {
      sumLoss += t.rMultiple.abs();
    }

    final avgR = sumR / trades.length;
    final avgWinR = wins.isEmpty ? 0.0 : sumWin / wins.length;
    final avgLossR = losses.isEmpty ? 0.0 : sumLoss / losses.length;
    final profitFactor = sumLoss <= 0 ? (sumWin > 0 ? double.infinity : 0.0) : sumWin / sumLoss;

    // Equity curve in R units
    var equity = 0.0;
    var peak = 0.0;
    var maxDd = 0.0;
    for (final t in trades) {
      equity += t.rMultiple;
      if (equity > peak) peak = equity;
      final dd = peak - equity;
      if (dd > maxDd) maxDd = dd;
    }

    return PaperMetrics(
      signals: signals.length,
      trades: trades.length,
      wins: wins.length,
      losses: losses.length,
      skips: skips,
      avgR: avgR,
      avgWinR: avgWinR,
      avgLossR: avgLossR,
      profitFactor: profitFactor.isFinite ? profitFactor : 0,
      expectancy: avgR,
      maxDrawdownR: maxDd,
      note: 'Paper only — not live exchange results',
    );
  }
}
