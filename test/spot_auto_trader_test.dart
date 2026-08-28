import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/spot_auto_trader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('max notional safety constant is 50', () {
    expect(kMaxPositionNotionalUsdt, 50.0);
  });

  test('auto-trade min score is 90', () {
    expect(kAutoTradeMinScore, 90.0);
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
      entry: 150.13,
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
  });
}
