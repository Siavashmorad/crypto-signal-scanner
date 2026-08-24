import '../models/market_data.dart';
import 'signal_journal.dart';

/// Resolve pending paper entries against subsequent real candles only.
class PaperForwardResolver {
  /// Walk [candles] after entry time; mark win/loss/expired.
  JournalEntry resolve(
    JournalEntry entry,
    List<Candle> candles, {
    int maxBars = 48,
  }) {
    if (entry.outcome != JournalOutcome.pending) return entry;
    if (candles.length < 3) return entry;

    final risk = (entry.entry - entry.stopLoss).abs();
    if (risk <= 0) {
      return entry.copyWith(outcome: JournalOutcome.skipped, rMultiple: 0);
    }

    final isLong =
        entry.side.toUpperCase() == 'LONG' || entry.side.toUpperCase() == 'BUY';
    final startMs = entry.timestamp.millisecondsSinceEpoch;

    var startIdx = 0;
    for (var i = 0; i < candles.length; i++) {
      if (candles[i].timestampMs >= startMs) {
        startIdx = i;
        break;
      }
      startIdx = i;
    }

    JournalOutcome outcome = JournalOutcome.expired;
    double exit = entry.entry;
    var bars = 0;
    final end = (startIdx + maxBars).clamp(0, candles.length - 1);

    for (var i = startIdx + 1; i <= end; i++) {
      bars++;
      final c = candles[i];
      if (isLong) {
        if (c.low <= entry.stopLoss) {
          outcome = JournalOutcome.loss;
          exit = entry.stopLoss;
          break;
        }
        if (c.high >= entry.tp1) {
          outcome = JournalOutcome.win;
          exit = entry.tp1;
          break;
        }
      } else {
        if (c.high >= entry.stopLoss) {
          outcome = JournalOutcome.loss;
          exit = entry.stopLoss;
          break;
        }
        if (c.low <= entry.tp1) {
          outcome = JournalOutcome.win;
          exit = entry.tp1;
          break;
        }
      }
    }

    final pnl = isLong ? (exit - entry.entry) : (entry.entry - exit);
    final r = pnl / risk;
    // Near-zero R as breakeven
    if (outcome == JournalOutcome.expired && r.abs() < 0.05) {
      outcome = JournalOutcome.breakeven;
    }

    return entry.copyWith(
      outcome: outcome,
      rMultiple: r,
      durationBars: bars,
    );
  }
}
