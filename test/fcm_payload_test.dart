import 'package:crypto_signal_scanner/services/fcm_opportunity_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FcmOpportunityPayload', () {
    test('fromData parses signal_opportunity', () {
      final p = FcmOpportunityPayload.fromData({
        'type': 'signal_opportunity',
        'opportunity_id': 'fp123',
        'symbol': 'btcusdt',
        'side': 'long',
        'entry': '65000.5',
        'stop_loss': '64000',
        'tp1': '67000',
        'risk_reward': '2.0',
        'score': '85',
        'confidence': '88',
        'regime': 'TRENDING_BULL',
        'timestamp_ms': '1700000000000',
        'source': 'scanner+tv',
      });
      expect(p, isNotNull);
      expect(p!.isOpportunity, isTrue);
      expect(p.symbol, 'BTCUSDT');
      expect(p.side, 'LONG');
      expect(p.opportunityId, 'fp123');
      expect(p.entry, 65000.5);
      expect(p.stopLoss, 64000);
      expect(p.tp1, 67000);
      expect(p.score, 85);
      expect(p.confidence, 88);
      expect(p.regime, 'TRENDING_BULL');
    });

    test('fromData rejects bad side', () {
      expect(
        FcmOpportunityPayload.fromData({
          'symbol': 'ETHUSDT',
          'side': 'BUY',
        }),
        isNull,
      );
    });

    test('fromLocalPayload roundtrip', () {
      final p = FcmOpportunityPayload.fromLocalPayload('ETHUSDT|SHORT|abc');
      expect(p?.symbol, 'ETHUSDT');
      expect(p?.side, 'SHORT');
      expect(p?.opportunityId, 'abc');
      expect(p!.toLocalPayload(), 'ETHUSDT|SHORT|abc');
    });

    test('toDataMap has no secret keys', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'x',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 1,
      );
      final m = p.toDataMap();
      final joined = m.values.join(' ').toLowerCase();
      expect(joined.contains('secret'), isFalse);
      expect(joined.contains('password'), isFalse);
      expect(m['type'], 'signal_opportunity');
    });

    test('stale detection', () {
      final old = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'o',
        symbol: 'BTCUSDT',
        side: 'LONG',
        timestampMs: 1,
      );
      expect(old.isStale(), isTrue);
      final fresh = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'n',
        symbol: 'BTCUSDT',
        side: 'LONG',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      expect(fresh.isStale(), isFalse);
    });
  });
}
