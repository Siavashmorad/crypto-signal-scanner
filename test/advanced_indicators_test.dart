import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/chart_indicators.dart';

List<Candle> series(int n, {double start = 100}) {
  return List.generate(n, (i) {
    final p = start + i * 0.4;
    return Candle(
      timestampMs: i * 60000,
      open: p - 0.1,
      high: p + 0.5,
      low: p - 0.5,
      close: p,
      volume: 10 + (i % 5).toDouble(),
    );
  });
}

void main() {
  test('ATR positive on trending series', () {
    final c = series(40);
    final a = ChartIndicators.lastAtr(c);
    expect(a, isNotNull);
    expect(a! > 0, isTrue);
  });

  test('ADX returns values with enough candles', () {
    final c = series(60);
    final a = ChartIndicators.adx(c);
    expect(a.adx, isNotNull);
  });

  test('StochRSI bounded 0-100 when present', () {
    final c = series(50);
    final s = ChartIndicators.stochRsi(c);
    final k = s.k.lastWhere((e) => e != null, orElse: () => null);
    if (k != null) {
      expect(k >= 0 && k <= 100, isTrue);
    }
  });

  test('CCI / ROC / Williams produce finite last values', () {
    final c = series(40);
    final cci = ChartIndicators.cci(c);
    final roc = ChartIndicators.roc(c);
    final wr = ChartIndicators.williamsR(c);
    expect(cci.last, isNotNull);
    expect(roc.last, isNotNull);
    expect(wr.last, isNotNull);
    expect(wr.last! <= 0 && wr.last! >= -100, isTrue);
  });

  test('BB width positive', () {
    final c = series(30);
    final w = ChartIndicators.bollingerWidth(c);
    final last = w.lastWhere((e) => e != null, orElse: () => null);
    expect(last, isNotNull);
    expect(last! > 0, isTrue);
  });

  test('relative volume defined', () {
    final c = series(25);
    final r = ChartIndicators.relativeVolume(c);
    expect(r, isNotNull);
    expect(r! > 0, isTrue);
  });
}
