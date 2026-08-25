import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/fcm_opportunity_payload.dart';
import 'package:crypto_signal_scanner/services/push_open_handler.dart';
import 'package:flutter_test/flutter_test.dart';

MarketSignal _sig({
  String symbol = 'BTCUSDT',
  String side = 'LONG',
  double entry = 65000,
  double conf = 80,
}) {
  return MarketSignal(
    symbol: symbol,
    side: side,
    timeframe: '15m',
    entry: entry,
    stopLoss: entry * 0.99,
    tp1: entry * 1.01,
    tp2: entry * 1.02,
    tp3: entry * 1.03,
    atr: 100,
    confidence: conf,
    riskReward: 2,
    timestamp: DateTime.now(),
  );
}

void main() {
  group('PushOpenHandler', () {
    final h = PushOpenHandler();

    test('rejects stale payload without ordering', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'old',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 65000,
        timestampMs: 1,
      );
      final r = h.evaluate(payload: p, live: _sig());
      expect(r.decision, PushOpenDecision.reject);
      expect(r.reasonFa.contains('معتبر نیست'), isTrue);
      expect(r.liveSignal, isNull);
    });

    test('rejects when live data missing', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'n',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 65000,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      final r = h.evaluate(payload: p, live: null);
      expect(r.decision, PushOpenDecision.reject);
      expect(r.liveSignal, isNull);
    });

    test('rejects side conflict', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'n',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 65000,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      final r = h.evaluate(payload: p, live: _sig(side: 'SHORT'));
      expect(r.decision, PushOpenDecision.reject);
    });

    test('proceeds with live signal (not notification prices)', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'n',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 65000,
        stopLoss: 64000,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      final live = _sig(entry: 65100);
      final r = h.evaluate(payload: p, live: live);
      expect(r.decision, PushOpenDecision.proceed);
      expect(r.liveSignal?.entry, 65100);
      expect(r.liveSignal?.entry, isNot(equals(p.entry)));
    });

    test('rejects large drift', () {
      final p = FcmOpportunityPayload(
        type: 'signal_opportunity',
        opportunityId: 'n',
        symbol: 'BTCUSDT',
        side: 'LONG',
        entry: 65000,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      final live = _sig(entry: 70000);
      final r = h.evaluate(payload: p, live: live);
      expect(r.decision, PushOpenDecision.reject);
    });
  });
}
