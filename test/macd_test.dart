import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/chart_indicators.dart';

List<Candle> rising(int n) {
  return List.generate(
    n,
    (i) => Candle(
      timestampMs: i * 60000,
      open: 100 + i * 0.5,
      high: 101 + i * 0.5,
      low: 99 + i * 0.5,
      close: 100.5 + i * 0.5,
      volume: 10,
    ),
  );
}

void main() {
  test('MACD length matches candles; null until slow+signal ready', () {
    final c = rising(50);
    final m = ChartIndicators.macd(c);
    expect(m.macd.length, 50);
    expect(m.signal.length, 50);
    expect(m.hist.length, 50);
    // slow=26 → first MACD at index 25; signal needs 9 more → ~33
    expect(m.macd[24], isNull);
    expect(m.macd[25], isNotNull);
    expect(m.signal[25], isNull);
    expect(m.hist.last, isNotNull);
  });

  test('rising series produces positive MACD eventually', () {
    final c = rising(80);
    final m = ChartIndicators.macd(c);
    final last = m.macd.last;
    expect(last, isNotNull);
    expect(last! > 0, isTrue);
  });

  test('insufficient candles → all null', () {
    final c = rising(10);
    final m = ChartIndicators.macd(c);
    expect(m.macd.every((e) => e == null), isTrue);
  });
}
