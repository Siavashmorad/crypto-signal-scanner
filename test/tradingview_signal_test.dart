import 'package:crypto_signal_scanner/services/tradingview_signal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TradingViewAlert', () {
    test('parses full payload without inventing fields', () {
      final a = TradingViewAlert.fromJson({
        'symbol': 'btcusdt',
        'signal': 'long',
        'price': 65000,
        'indicators': {'rsi': 62.5},
        'fingerprint': 'abc',
        'stale': false,
      });
      expect(a.symbol, 'BTCUSDT');
      expect(a.signal, 'LONG');
      expect(a.price, 65000);
      expect(a.indicators['rsi'], 62.5);
      expect(a.indicators.containsKey('macd'), isFalse);
      expect(a.isActionable, isTrue);
    });

    test('stale or neutral not actionable', () {
      final stale = TradingViewAlert.fromJson({
        'symbol': 'ETHUSDT',
        'signal': 'LONG',
        'stale': true,
      });
      expect(stale.isActionable, isFalse);
      final neutral = TradingViewAlert.fromJson({
        'symbol': 'ETHUSDT',
        'signal': 'NEUTRAL',
      });
      expect(neutral.isActionable, isFalse);
    });
  });
}
