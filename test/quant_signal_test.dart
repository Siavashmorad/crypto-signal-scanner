import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/data_health.dart';
import 'package:crypto_signal_scanner/services/quant_signal_engine.dart';

List<Candle> up(int n) => List.generate(n, (i) {
      final p = 100.0 + i * 0.8;
      return Candle(
        timestampMs: i * 60000,
        open: p - 0.2,
        high: p + 0.6,
        low: p - 0.6,
        close: p,
        volume: 15 + i * 0.1,
      );
    });

MarketSignal sig() => MarketSignal(
      symbol: 'BTCUSDT',
      side: 'LONG',
      timeframe: '15m',
      entry: 140,
      stopLoss: 130,
      tp1: 155,
      tp2: 165,
      tp3: 175,
      atr: 2,
      riskReward: 1.5,
      confidence: 50,
      timestamp: DateTime.now(),
    );

void main() {
  test('quant returns decision with breakdown', () {
    final eng = QuantSignalEngine();
    final c = up(80);
    final d = eng.evaluate(
      signal: sig(),
      candlesByTf: {'15m': c, '1h': c, '4h': c, '5m': c},
      dataHealth: DataHealth.live,
    );
    expect(d.score >= 0 && d.score <= 100, isTrue);
    expect(d.breakdown.isNotEmpty, isTrue);
    expect(d.quality, isNotNull);
  });

  test('stale forces non-live quality', () {
    final eng = QuantSignalEngine();
    final c = up(80);
    final d = eng.evaluate(
      signal: sig(),
      candlesByTf: {'1h': c},
      dataHealth: DataHealth.stale,
    );
    expect(d.quality == TradeQuality.noTrade || d.direction == 'WAIT', isTrue);
  });
}
