import 'performance_analytics.dart';
import 'signal_journal.dart';

class GateDecision {
  final bool allowLive;
  final String reason;
  final String reasonEn;
  final bool paperOnly;

  const GateDecision({
    required this.allowLive,
    required this.reason,
    this.reasonEn = '',
    this.paperOnly = false,
  });

  /// User-facing text for current UI language.
  String text({required bool english}) =>
      english ? (reasonEn.isNotEmpty ? reasonEn : reason) : reason;
}

/// Statistical live gate — does not invent edge; defaults to paper when unknown.
class LiveTradingGate {
  LiveTradingGate({
    this.minSample = 20,
    this.minExpectancyR = 0.05,
  });

  final int minSample;
  final double minExpectancyR;
  final analytics = PerformanceAnalytics(minSample: 20);

  GateDecision evaluate({
    required List<JournalEntry> journal,
    required String quality,
    required String regime,
    required bool userLiveEnabled,
    required bool dataHealthy,
  }) {
    if (!userLiveEnabled) {
      return const GateDecision(
        allowLive: false,
        reason: 'سفارش واقعی خاموش است — فقط معاملات آزمایشی',
        reasonEn: 'User LIVE toggle off',
        paperOnly: true,
      );
    }
    if (!dataHealthy) {
      return const GateDecision(
        allowLive: false,
        reason: 'داده بازار زنده نیست — قفل معامله واقعی',
        reasonEn: 'Market data not LIVE',
        paperOnly: true,
      );
    }

    final report = analytics.build(journal);
    final paper = report.overallPaper;

    if (paper.insufficientSample) {
      return GateDecision(
        allowLive: false,
        reason:
            'قفل معامله زنده: نمونه آزمایشی کافی نیست '
            '(n=${paper.sample}، حداقل $minSample لازم است). '
            'ثبت آزمایشی ادامه دارد.',
        reasonEn:
            'LIVE GATE DISABLED: ${paper.note}. Paper recording continues.',
        paperOnly: true,
      );
    }

    if (paper.expectancyR < minExpectancyR) {
      return GateDecision(
        allowLive: false,
        reason:
            'قفل معامله زنده: امیدریاضی معاملات آزمایشی '
            '${paper.expectancyR.toStringAsFixed(2)}R کمتر از ${minExpectancyR}R است.',
        reasonEn:
            'LIVE GATE DISABLED: paper expectancy ${paper.expectancyR.toStringAsFixed(2)}R < ${minExpectancyR}R',
        paperOnly: true,
      );
    }

    final allowedQ = analytics.suggestedLiveQualities(report);
    if (allowedQ.isNotEmpty && !allowedQ.contains(quality)) {
      return GateDecision(
        allowLive: false,
        reason:
            'کیفیت $quality برای سفارش واقعی تأیید نشده '
            '(مجاز: ${allowedQ.join('، ')})',
        reasonEn:
            'Quality $quality not validated for live (allowed: ${allowedQ.join(', ')})',
        paperOnly: true,
      );
    }

    if (allowedQ.isEmpty && quality != 'A+' && quality != 'A') {
      return GateDecision(
        allowLive: false,
        reason: 'تا تأیید کیفیت‌ها، سفارش واقعی فقط برای A+/A',
        reasonEn: 'Until quality buckets validated, live limited to A+/A',
        paperOnly: true,
      );
    }

    final weak = analytics.weakRegimes(report);
    if (weak.contains(regime)) {
      return GateDecision(
        allowLive: false,
        reason: 'وضعیت بازار $regime امیدریاضی منفی دارد',
        reasonEn: 'Regime $regime has negative measured expectancy',
        paperOnly: true,
      );
    }

    return GateDecision(
      allowLive: true,
      reason:
          'گیت تأیید شد · نمونه آزمایشی n=${paper.sample} '
          'E=${paper.expectancyR.toStringAsFixed(2)}R',
      reasonEn:
          'Gate OK · paper n=${paper.sample} E=${paper.expectancyR.toStringAsFixed(2)}R',
    );
  }
}
