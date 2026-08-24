import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/data_health.dart';
import 'package:crypto_signal_scanner/services/market_regime.dart';
import 'package:crypto_signal_scanner/services/trade_filter_engine.dart';

void main() {
  final f = TradeFilterEngine();

  test('stale data → NO TRADE', () {
    final r = f.evaluate(
      dataHealth: DataHealth.stale,
      regime: MarketRegime.trendingBull,
      riskReward: 2,
    );
    expect(r.verdict, FilterVerdict.noTrade);
  });

  test('choppy → WAIT', () {
    final r = f.evaluate(
      dataHealth: DataHealth.live,
      regime: MarketRegime.choppy,
      riskReward: 2,
    );
    expect(r.verdict, FilterVerdict.wait);
  });

  test('bad R/R → WAIT', () {
    final r = f.evaluate(
      dataHealth: DataHealth.live,
      regime: MarketRegime.trendingBull,
      riskReward: 0.8,
    );
    expect(r.verdict, FilterVerdict.wait);
  });

  test('min order risk → NO TRADE', () {
    final r = f.evaluate(
      dataHealth: DataHealth.live,
      regime: MarketRegime.trendingBull,
      riskReward: 2,
      minOrderViolatesRisk: true,
    );
    expect(r.verdict, FilterVerdict.noTrade);
  });

  test('valid setup passes', () {
    final r = f.evaluate(
      dataHealth: DataHealth.live,
      regime: MarketRegime.trendingBull,
      riskReward: 2.2,
      atrPct: 1.0,
      relativeVolume: 1.1,
    );
    expect(r.verdict, FilterVerdict.pass);
  });
}
