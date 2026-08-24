import 'performance_analytics.dart';
import 'signal_journal.dart';

class GateDecision {
  final bool allowLive;
  final String reason;
  final bool paperOnly;

  const GateDecision({
    required this.allowLive,
    required this.reason,
    this.paperOnly = false,
  });
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
        reason: 'User LIVE toggle off',
        paperOnly: true,
      );
    }
    if (!dataHealthy) {
      return const GateDecision(
        allowLive: false,
        reason: 'Market data not LIVE',
        paperOnly: true,
      );
    }

    final report = analytics.build(journal);
    final paper = report.overallPaper;

    if (paper.insufficientSample) {
      return GateDecision(
        allowLive: false,
        reason:
            'LIVE GATE DISABLED: ${paper.note}. Paper recording continues.',
        paperOnly: true,
      );
    }

    if (paper.expectancyR < minExpectancyR) {
      return GateDecision(
        allowLive: false,
        reason:
            'LIVE GATE DISABLED: paper expectancy ${paper.expectancyR.toStringAsFixed(2)}R < ${minExpectancyR}R',
        paperOnly: true,
      );
    }

    final allowedQ = analytics.suggestedLiveQualities(report);
    if (allowedQ.isNotEmpty && !allowedQ.contains(quality)) {
      return GateDecision(
        allowLive: false,
        reason:
            'Quality $quality not validated for live (allowed: ${allowedQ.join(', ')})',
        paperOnly: true,
      );
    }

    // Default: only A+ / A until data expands allowed set
    if (allowedQ.isEmpty && quality != 'A+' && quality != 'A') {
      return GateDecision(
        allowLive: false,
        reason: 'Until quality buckets validated, live limited to A+/A',
        paperOnly: true,
      );
    }

    final weak = analytics.weakRegimes(report);
    if (weak.contains(regime)) {
      return GateDecision(
        allowLive: false,
        reason: 'Regime $regime has negative measured expectancy',
        paperOnly: true,
      );
    }

    return GateDecision(
      allowLive: true,
      reason: 'Gate OK · paper n=${paper.sample} E=${paper.expectancyR.toStringAsFixed(2)}R',
    );
  }
}
