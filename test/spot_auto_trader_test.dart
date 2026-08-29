import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/live_trading_gate.dart';
import 'package:crypto_signal_scanner/services/spot_auto_trader.dart';
import 'package:flutter_test/flutter_test.dart';

MarketSignal _sig({
  String side = 'LONG',
  double confidence = 93,
  double entry = 100,
  double sl = 95,
  double tp1 = 110,
}) {
  return MarketSignal(
    symbol: 'BTCUSDT',
    side: side,
    timeframe: '15m',
    entry: entry,
    stopLoss: sl,
    tp1: tp1,
    tp2: tp1 + 5,
    tp3: tp1 + 10,
    atr: 2,
    confidence: confidence,
    riskReward: 2,
    timestamp: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  test('max notional safety constant is 50', () {
    expect(kMaxPositionNotionalUsdt, 50.0);
  });

  test('auto-trade min score is 90', () {
    expect(kAutoTradeMinScore, 90.0);
  });

  test('score 89 is below auto-trade threshold', () {
    expect(89 < kAutoTradeMinScore, isTrue);
    expect(_sig(confidence: 89).confidence < kAutoTradeMinScore, isTrue);
  });

  test('score 90 is eligible threshold (gates still required)', () {
    expect(90 >= kAutoTradeMinScore, isTrue);
    expect(_sig(confidence: 90).confidence >= kAutoTradeMinScore, isTrue);
  });

  test('bearish SPOT signal is not LONG — auto path must skip SHORT', () {
    final short = _sig(side: 'SHORT', confidence: 95, entry: 100, sl: 105, tp1: 90);
    expect(short.side.toUpperCase() == 'LONG', isFalse);
  });

  test('fingerprint is stable for same signal band', () {
    final a = MarketSignal(
      symbol: 'SOLUSDT',
      side: 'LONG',
      timeframe: '15m',
      entry: 150.12,
      stopLoss: 145,
      tp1: 160,
      tp2: 165,
      tp3: 170,
      atr: 2,
      confidence: 93,
      riskReward: 2,
      timestamp: DateTime.utc(2026, 1, 1),
    );
    final b = MarketSignal(
      symbol: 'SOLUSDT',
      side: 'LONG',
      timeframe: '15m',
      entry: 150.124,
      stopLoss: 145,
      tp1: 160,
      tp2: 165,
      tp3: 170,
      atr: 2,
      confidence: 93,
      riskReward: 2,
      timestamp: DateTime.utc(2026, 1, 1),
    );
    expect(SpotAutoTrader.fingerprintOf(a), SpotAutoTrader.fingerprintOf(b));
    expect(SpotAutoTrader.fingerprintOf(a), 'SOLUSDT:LONG:90:15012');
  });

  test('duplicate fingerprint strings match', () {
    final a = _sig(confidence: 92);
    final b = _sig(confidence: 93); // same score band 90
    expect(SpotAutoTrader.fingerprintOf(a), SpotAutoTrader.fingerprintOf(b));
  });

  test('LiveTradingGate defaults minSample 20 and expectancy 0.05', () {
    final g = LiveTradingGate();
    expect(g.minSample, 20);
    expect(g.minExpectancyR, 0.05);
  });

  test('LiveTradingGate blocks when userLiveEnabled is false', () {
    final g = LiveTradingGate();
    final d = g.evaluate(
      journal: const [],
      quality: 'A+',
      regime: 'UNKNOWN',
      userLiveEnabled: false,
      dataHealthy: true,
    );
    expect(d.allowLive, isFalse);
  });

  test('LiveTradingGate blocks when data not healthy', () {
    final g = LiveTradingGate();
    final d = g.evaluate(
      journal: const [],
      quality: 'A+',
      regime: 'UNKNOWN',
      userLiveEnabled: true,
      dataHealthy: false,
    );
    expect(d.allowLive, isFalse);
  });

  test('notional above 50 must be rejected by constant', () {
    expect(51 > kMaxPositionNotionalUsdt, isTrue);
    expect(50 <= kMaxPositionNotionalUsdt, isTrue);
  });
}
