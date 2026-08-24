import 'package:crypto_signal_scanner/services/realtime_futures_scanner_service.dart';
import 'package:crypto_signal_scanner/services/signal_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalFingerprint', () {
    test('same setup produces same key for tiny price noise', () {
      final a = SignalFingerprint.fromOpportunity(
        symbol: 'BTCUSDT',
        side: 'LONG',
        quality: 'A',
        score: 80,
        entry: 65000,
      );
      final b = SignalFingerprint.fromOpportunity(
        symbol: 'btcusdt',
        side: 'long',
        quality: 'A',
        score: 82,
        entry: 65002,
      );
      // score band is 5-pt; entry band is /10 for large prices
      expect(a.scoreBand, b.scoreBand);
      expect(a.entryBand, b.entryBand);
      expect(a.key, b.key);
    });

    test('side change changes key', () {
      final long = SignalFingerprint.fromOpportunity(
        symbol: 'ETHUSDT',
        side: 'LONG',
        quality: 'A+',
        score: 90,
        entry: 3000,
      );
      final short = SignalFingerprint.fromOpportunity(
        symbol: 'ETHUSDT',
        side: 'SHORT',
        quality: 'A+',
        score: 90,
        entry: 3000,
      );
      expect(long.key, isNot(short.key));
    });
  });

  group('SignalNotificationService', () {
    test('blocks B when min quality is A', () {
      final n = SignalNotificationService(minQualityForNotify: 'A');
      expect(n.qualityAllowsNotify('B'), isFalse);
      expect(n.qualityAllowsNotify('A'), isTrue);
      expect(n.qualityAllowsNotify('A+'), isTrue);
    });

    test('suppresses duplicate fingerprint', () {
      final n = SignalNotificationService(
        cooldown: const Duration(minutes: 15),
        minQualityForNotify: 'A',
      );
      final fp = SignalFingerprint.fromOpportunity(
        symbol: 'SOLUSDT',
        side: 'LONG',
        quality: 'A',
        score: 75,
        entry: 140,
      );
      final t0 = DateTime.utc(2026, 1, 1, 12);
      expect(n.shouldNotify(fp: fp, now: t0), isTrue);
      expect(
          n.shouldNotify(fp: fp, now: t0.add(const Duration(minutes: 1))),
          isFalse);
    });

    test('allows notify after cooldown for new fingerprint', () {
      final n = SignalNotificationService(
        cooldown: const Duration(minutes: 5),
        minQualityForNotify: 'A',
      );
      final fp1 = SignalFingerprint.fromOpportunity(
        symbol: 'XRPUSDT',
        side: 'SHORT',
        quality: 'A',
        score: 70,
        entry: 0.5,
      );
      final t0 = DateTime.utc(2026, 1, 1, 12);
      expect(n.shouldNotify(fp: fp1, now: t0), isTrue);
      n.invalidate('XRPUSDT');
      final fp2 = SignalFingerprint.fromOpportunity(
        symbol: 'XRPUSDT',
        side: 'SHORT',
        quality: 'A+',
        score: 90,
        entry: 0.48,
      );
      expect(
        n.shouldNotify(
          fp: fp2,
          now: t0.add(const Duration(minutes: 6)),
        ),
        isTrue,
      );
    });
  });

  group('RealtimeFuturesScannerService.qualityOf', () {
    test('maps confidence bands', () {
      expect(RealtimeFuturesScannerService.qualityOf(90), 'A+');
      expect(RealtimeFuturesScannerService.qualityOf(75), 'A');
      expect(RealtimeFuturesScannerService.qualityOf(60), 'B');
      expect(RealtimeFuturesScannerService.qualityOf(50), 'C');
      expect(RealtimeFuturesScannerService.qualityOf(10), 'NO TRADE');
    });
  });
}
