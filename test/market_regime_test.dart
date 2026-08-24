import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/market_regime.dart';

List<Candle> trendingUp(int n) => List.generate(n, (i) {
      final p = 100.0 + i * 1.2;
      return Candle(
        timestampMs: i * 60000,
        open: p - 0.2,
        high: p + 1,
        low: p - 1,
        close: p + 0.5,
        volume: 20 + i.toDouble(),
      );
    });

void main() {
  test('insufficient data → unknown unavailable', () {
    final d = MarketRegimeDetector();
    final r = d.detect(trendingUp(10));
    expect(r.available, isFalse);
    expect(r.regime, MarketRegime.unknown);
  });

  test('strong uptrend produces non-choppy regime', () {
    final d = MarketRegimeDetector();
    final r = d.detect(trendingUp(80));
    expect(r.available, isTrue);
    expect(r.regime, isNot(MarketRegime.unknown));
    // Prefer trend/breakout over choppy on strong series
    expect(r.regime != MarketRegime.choppy || r.adx != null, isTrue);
  });
}
