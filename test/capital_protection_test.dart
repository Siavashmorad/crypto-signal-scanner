import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/capital_protection.dart';

void main() {
  test('cooldown after consecutive losses', () {
    final c = CapitalProtection(
      maxConsecutiveLosses: 3,
      cooldownAfterLosses: const Duration(hours: 1),
    );
    c.recordOutcome(win: false, rMultiple: -1);
    c.recordOutcome(win: false, rMultiple: -1);
    expect(c.allowsTrade, isTrue);
    c.recordOutcome(win: false, rMultiple: -1);
    expect(c.allowsTrade, isFalse);
    expect(c.blockReason(), contains('COOLDOWN'));
  });

  test('max daily loss blocks', () {
    final c = CapitalProtection(maxDailyLossR: 2);
    c.recordOutcome(win: false, rMultiple: -1.2);
    c.recordOutcome(win: false, rMultiple: -1.2);
    expect(c.allowsTrade, isFalse);
  });
}
