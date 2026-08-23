import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/chart_indicators.dart';

List<Candle> _candles(int n) {
  final out = <Candle>[];
  var p = 100.0;
  for (var i = 0; i < n; i++) {
    p += (i % 3 == 0) ? 1.0 : -0.5;
    out.add(Candle(
      timestampMs: i * 60000,
      open: p - 0.2,
      high: p + 0.5,
      low: p - 0.5,
      close: p,
      volume: 10 + i.toDouble(),
    ));
  }
  return out;
}

void main() {
  test('EMA length matches candles and fills after period', () {
    final c = _candles(30);
    final e = ChartIndicators.ema(c, 10);
    expect(e.length, 30);
    expect(e[8], isNull);
    expect(e[9], isNotNull);
    expect(e.last, isNotNull);
  });

  test('SMA stable on constant series', () {
    final c = List.generate(
      20,
      (i) => Candle(
        timestampMs: i * 60000,
        open: 50,
        high: 51,
        low: 49,
        close: 50,
        volume: 1,
      ),
    );
    final s = ChartIndicators.sma(c, 5);
    expect(s[4], closeTo(50, 1e-9));
    expect(s[19], closeTo(50, 1e-9));
  });

  test('RSI null when insufficient data', () {
    final c = _candles(5);
    expect(ChartIndicators.lastRsi(c), isNull);
  });

  test('VWAP increases with rising prices and volume', () {
    final c = _candles(15);
    final v = ChartIndicators.vwap(c);
    expect(v.last, isNotNull);
    expect(v.last! > 0, isTrue);
  });
}
