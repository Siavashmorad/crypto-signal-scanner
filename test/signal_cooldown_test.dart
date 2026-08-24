import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/signal_cooldown.dart';

MarketSignal s(String symbol, {String side = 'LONG'}) => MarketSignal(
      symbol: symbol,
      side: side,
      timeframe: '15m',
      entry: 1,
      stopLoss: 0.9,
      tp1: 1.1,
      tp2: 1.2,
      tp3: 1.3,
      atr: 0.01,
      confidence: 70,
      riskReward: 2,
      timestamp: DateTime.now(),
    );

void main() {
  test('blocks duplicate within window', () {
    final c = SignalCooldown(window: const Duration(minutes: 30));
    final now = DateTime(2026, 1, 1, 12);
    expect(c.allow(s('BTCUSDT'), now: now), isTrue);
    expect(c.allow(s('BTCUSDT'), now: now.add(const Duration(minutes: 5))),
        isFalse);
    expect(c.allow(s('ETHUSDT'), now: now), isTrue);
  });

  test('allows after window', () {
    final c = SignalCooldown(window: const Duration(minutes: 10));
    final now = DateTime(2026, 1, 1, 12);
    expect(c.allow(s('BTCUSDT'), now: now), isTrue);
    expect(
      c.allow(s('BTCUSDT'), now: now.add(const Duration(minutes: 11))),
      isTrue,
    );
  });
}
