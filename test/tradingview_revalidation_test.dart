import 'package:crypto_signal_scanner/services/tradingview_opportunity_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final v = TradingViewOpportunityValidator(maxDriftPct: 1.5);

  test('expired by age', () {
    final r = v.revalidate(
      side: 'LONG',
      alertPrice: 100,
      livePrice: 100,
      alertTime: DateTime.now().subtract(const Duration(minutes: 20)),
    );
    expect(r.valid, isFalse);
    expect(r.reason, 'SIGNAL EXPIRED');
  });

  test('stale price drift', () {
    final r = v.revalidate(
      side: 'LONG',
      alertPrice: 100,
      livePrice: 103,
      alertTime: DateTime.now(),
    );
    expect(r.valid, isFalse);
    expect(r.reason, 'REJECT STALE SIGNAL');
  });

  test('ok within drift', () {
    final r = v.revalidate(
      side: 'LONG',
      alertPrice: 100,
      livePrice: 100.5,
      alertTime: DateTime.now(),
    );
    expect(r.valid, isTrue);
  });

  test('missing live price', () {
    final r = v.revalidate(side: 'SHORT', alertPrice: 50, livePrice: null);
    expect(r.valid, isFalse);
    expect(r.reason, 'DATA INSUFFICIENT');
  });
}
