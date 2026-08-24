import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/performance_analytics.dart';
import 'package:crypto_signal_scanner/services/signal_journal.dart';

JournalEntry e({
  String quality = 'A',
  String regime = 'TRENDING BULL',
  JournalOutcome outcome = JournalOutcome.win,
  double r = 1.0,
  bool live = false,
  double score = 75,
}) {
  return JournalEntry(
    id: '${quality}_${regime}_${r}_${outcome.name}_${DateTime.now().microsecondsSinceEpoch}',
    timestamp: DateTime.now(),
    symbol: 'BTCUSDT',
    timeframe: '15m',
    side: 'LONG',
    regime: regime,
    quality: quality,
    score: score,
    confidence: score,
    entry: 100,
    stopLoss: 95,
    tp1: 110,
    tp2: 115,
    tp3: 120,
    riskReward: 2,
    mode: live ? JournalMode.live : JournalMode.paper,
    outcome: outcome,
    rMultiple: r,
    isLive: live,
  );
}

void main() {
  test('insufficient sample flagged under minSample', () {
    final a = PerformanceAnalytics(minSample: 20);
    final report = a.build([e(), e(outcome: JournalOutcome.loss, r: -1)]);
    expect(report.overallPaper.insufficientSample, isTrue);
    expect(report.overallPaper.note.contains('INSUFFICIENT'), isTrue);
  });

  test('valid sample computes expectancy', () {
    final a = PerformanceAnalytics(minSample: 5);
    final list = <JournalEntry>[];
    for (var i = 0; i < 6; i++) {
      list.add(e(r: 1.0, outcome: JournalOutcome.win, score: 80));
    }
    for (var i = 0; i < 4; i++) {
      list.add(e(r: -1.0, outcome: JournalOutcome.loss, score: 60));
    }
    final report = a.build(list);
    expect(report.overallPaper.insufficientSample, isFalse);
    expect(report.overallPaper.sample, 10);
    expect(report.overallPaper.expectancyR, closeTo(0.2, 0.01));
  });

  test('paper and live never mixed in overall buckets', () {
    final a = PerformanceAnalytics(minSample: 2);
    final report = a.build([
      e(live: false, outcome: JournalOutcome.win, r: 1),
      e(live: false, outcome: JournalOutcome.loss, r: -1),
      e(live: true, outcome: JournalOutcome.win, r: 2),
    ]);
    expect(report.overallPaper.sample, 2);
    expect(report.overallLive.sample, 1);
  });

  test('weak regimes detected when expectancy negative', () {
    final a = PerformanceAnalytics(minSample: 3);
    final list = List.generate(
      4,
      (_) => e(
        regime: 'CHOPPY',
        outcome: JournalOutcome.loss,
        r: -1,
      ),
    );
    final report = a.build(list);
    expect(a.weakRegimes(report).contains('CHOPPY'), isTrue);
  });
}
