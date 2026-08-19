import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';

void main() {
  test('market signal keeps entry, ATR and multiple targets', () {
    final now = DateTime(2026, 8, 19);
    final signal = MarketSignal(symbol: 'BTCUSDT', side: 'LONG', entry: 100, stopLoss: 98, tp1: 102, tp2: 104, tp3: 106, atr: 1.33, confidence: 75, riskReward: 2, timestamp: now);
    expect(signal.symbol, 'BTCUSDT');
    expect(signal.tp3, 106);
    expect(signal.atr, 1.33);
    expect(signal.confidence, greaterThanOrEqualTo(0));
    expect(signal.confidence, lessThanOrEqualTo(100));
  });

  test('trade point stores normalized market primitives', () {
    const trade = TradePoint(price: 123.45, quantity: 2, timestampMs: 1000);
    expect(trade.price, 123.45);
    expect(trade.quantity, 2);
    expect(trade.timestampMs, 1000);
  });
}
