import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/paper_eval.dart';

List<Candle> path() {
  // 40 candles: drift up then hit TP for a long
  return List.generate(40, (i) {
    final p = 100.0 + i * 0.5;
    return Candle(
      timestampMs: i * 60000,
      open: p,
      high: p + 1,
      low: p - 0.5,
      close: p + 0.3,
      volume: 5,
    );
  });
}

void main() {
  test('insufficient data reported', () {
    final m = PaperEvaluator.evaluate(candles: path().take(5).toList(), signals: []);
    expect(m.insufficientData, isTrue);
  });

  test('long hits TP → win', () {
    final c = path();
    final m = PaperEvaluator.evaluate(
      candles: c,
      signals: [
        (index: 5, side: 'LONG', entry: 102.0, sl: 100.0, tp1: 110.0),
      ],
    );
    expect(m.insufficientData, isFalse);
    expect(m.wins, greaterThanOrEqualTo(1));
    expect(m.avgR, greaterThan(0));
  });

  test('long hits SL → loss', () {
    // flat then dump
    final c = List.generate(30, (i) {
      final p = i < 10 ? 100.0 : 100.0 - (i - 10) * 2;
      return Candle(
        timestampMs: i * 60000,
        open: p,
        high: p + 0.2,
        low: p - 1,
        close: p,
        volume: 1,
      );
    });
    final m = PaperEvaluator.evaluate(
      candles: c,
      signals: [
        (index: 5, side: 'LONG', entry: 100.0, sl: 98.0, tp1: 120.0),
      ],
    );
    expect(m.losses, greaterThanOrEqualTo(1));
  });
}
