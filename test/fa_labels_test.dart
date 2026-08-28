import 'package:crypto_signal_scanner/services/fa_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('side labels are Persian', () {
    expect(FaLabels.side('LONG'), 'خرید');
    expect(FaLabels.side('BUY'), 'خرید');
    expect(FaLabels.side('SHORT'), 'فروش');
    expect(FaLabels.side('SELL'), 'فروش');
    expect(FaLabels.side('WAIT'), 'صبر');
  });

  test('score tiers match product bands', () {
    expect(FaLabels.scoreTier(95), 'فرصت بسیار قوی');
    expect(FaLabels.scoreTier(90), 'فرصت بسیار قوی');
    expect(FaLabels.scoreTier(85), 'فرصت قوی');
    expect(FaLabels.scoreTier(75), 'قابل بررسی');
    expect(FaLabels.scoreTier(65), 'ضعیف');
    expect(FaLabels.scoreTier(40), 'عدم ورود');
  });

  test('reason mapping keeps Persian structure notes', () {
    expect(FaLabels.reason('EMA alignment bullish'), contains('میانگین'));
    expect(FaLabels.reason('structure aligned'), contains('ساختار'));
    expect(FaLabels.reason('volume confirmation 1.50x'), contains('حجم'));
    expect(FaLabels.reason('ساختار: HH_HL'), startsWith('ساختار'));
  });

  test('exit reasons', () {
    expect(FaLabels.exitReason('TP'), 'حد سود');
    expect(FaLabels.exitReason('SL'), 'حد ضرر');
    expect(FaLabels.pnlLabel(1.2), 'سود');
    expect(FaLabels.pnlLabel(-0.5), 'زیان');
  });
}
