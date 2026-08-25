import 'package:crypto_signal_scanner/services/android_notification_service.dart';
import 'package:crypto_signal_scanner/services/signal_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidNotificationService payload', () {
    test('payloadFor / parsePayload roundtrip', () {
      final p = AndroidNotificationService.payloadFor(
        symbol: 'btcusdt',
        side: 'long',
      );
      expect(p, 'BTCUSDT|LONG');
      final parsed = AndroidNotificationService.parsePayload(p);
      expect(parsed?.symbol, 'BTCUSDT');
      expect(parsed?.side, 'LONG');
    });

    test('parsePayload rejects malformed', () {
      expect(AndroidNotificationService.parsePayload(null), isNull);
      expect(AndroidNotificationService.parsePayload('only'), isNull);
    });
  });

  group('notification body security', () {
    test('buildBody has no secret-like keys', () {
      final n = SignalNotificationService();
      final body = n.buildBody(
        symbol: 'ETHUSDT',
        side: 'SHORT',
        quality: 'A+',
        score: 91,
        entry: 3000,
        stopLoss: 3050,
        tp1: 2900,
        riskReward: 2.0,
        regime: 'TRENDING BEAR',
      );
      final lower = body.toLowerCase();
      expect(lower.contains('secret'), isFalse);
      expect(lower.contains('password'), isFalse);
      expect(body.contains('ETHUSDT'), isTrue);
      expect(body.contains('SHORT'), isTrue);
      expect(body.contains('Quality'), isTrue);
      expect(body.contains('A+'), isTrue);
    });
  });
}
