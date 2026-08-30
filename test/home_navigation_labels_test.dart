import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/fa_labels.dart';
import 'package:crypto_signal_scanner/services/live_trading_gate.dart';

void main() {
  test('FaLabels spotSide never presents SHORT as sell entry', () {
    expect(FaLabels.spotSide('SHORT'), contains('عدم خرید'));
    expect(FaLabels.spotSide('LONG'), contains('خرید'));
    expect(FaLabels.side('SHORT'), equals('فروش'));
  });

  test('LiveGate Persian reason when sample insufficient', () {
    final g = LiveTradingGate(minSample: 20);
    final d = g.evaluate(
      journal: [],
      quality: 'A',
      regime: 'UNKNOWN',
      userLiveEnabled: true,
      dataHealthy: true,
    );
    expect(d.allowLive, isFalse);
    expect(
      d.reason.contains('قفل') ||
          d.reason.contains('نمونه') ||
          d.reason.contains('خاموش'),
      isTrue,
    );
  });

  test('GateDecision.text switches language', () {
    const d = GateDecision(
      allowLive: false,
      reason: 'قفل معامله زنده',
      reasonEn: 'LIVE GATE DISABLED',
      paperOnly: true,
    );
    expect(d.text(english: false), contains('قفل'));
    expect(d.text(english: true), contains('LIVE GATE'));
  });
}
