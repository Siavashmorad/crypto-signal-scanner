import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/paper_forward.dart';
import 'package:crypto_signal_scanner/services/signal_journal.dart';

void main() {
  test('resolves long win when TP hit', () {
    final entry = JournalEntry(
      id: '1',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      symbol: 'X',
      timeframe: '15m',
      side: 'LONG',
      regime: 'TRENDING BULL',
      quality: 'A',
      score: 80,
      confidence: 80,
      entry: 100,
      stopLoss: 95,
      tp1: 110,
      tp2: 115,
      tp3: 120,
      riskReward: 2,
      mode: JournalMode.paper,
    );
    final candles = [
      const Candle(
          timestampMs: 0, open: 100, high: 101, low: 99, close: 100, volume: 1),
      const Candle(
          timestampMs: 1, open: 100, high: 105, low: 99, close: 104, volume: 1),
      const Candle(
          timestampMs: 2,
          open: 104,
          high: 111,
          low: 103,
          close: 110,
          volume: 1),
    ];
    final r = PaperForwardResolver().resolve(entry, candles);
    expect(r.outcome, JournalOutcome.win);
    expect(r.rMultiple, closeTo(2.0, 0.01));
  });

  test('resolves long loss when SL hit', () {
    final entry = JournalEntry(
      id: '2',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      symbol: 'X',
      timeframe: '15m',
      side: 'LONG',
      regime: 'RANGING',
      quality: 'B',
      score: 60,
      confidence: 60,
      entry: 100,
      stopLoss: 95,
      tp1: 110,
      tp2: 115,
      tp3: 120,
      riskReward: 2,
      mode: JournalMode.paper,
    );
    final candles = [
      const Candle(
          timestampMs: 0, open: 100, high: 101, low: 99, close: 100, volume: 1),
      const Candle(
          timestampMs: 1, open: 100, high: 100, low: 96, close: 97, volume: 1),
      const Candle(
          timestampMs: 2, open: 97, high: 98, low: 94, close: 95, volume: 1),
    ];
    final r = PaperForwardResolver().resolve(entry, candles);
    expect(r.outcome, JournalOutcome.loss);
  });
}
