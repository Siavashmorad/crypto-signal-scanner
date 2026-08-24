import 'signal_journal.dart';

class BucketMetrics {
  final String label;
  final int sample;
  final int wins;
  final int losses;
  final int pending;
  final double winRate;
  final double expectancyR;
  final double profitFactor;
  final double avgR;
  final double maxDrawdownR;
  final bool insufficientSample;
  final String note;

  const BucketMetrics({
    required this.label,
    required this.sample,
    required this.wins,
    required this.losses,
    required this.pending,
    required this.winRate,
    required this.expectancyR,
    required this.profitFactor,
    required this.avgR,
    required this.maxDrawdownR,
    this.insufficientSample = false,
    this.note = '',
  });

  factory BucketMetrics.empty(String label, {String note = 'INSUFFICIENT SAMPLE'}) =>
      BucketMetrics(
        label: label,
        sample: 0,
        wins: 0,
        losses: 0,
        pending: 0,
        winRate: 0,
        expectancyR: 0,
        profitFactor: 0,
        avgR: 0,
        maxDrawdownR: 0,
        insufficientSample: true,
        note: note,
      );
}

class PerformanceReport {
  final BucketMetrics overallPaper;
  final BucketMetrics overallLive;
  final List<BucketMetrics> byRegime;
  final List<BucketMetrics> byQuality;
  final List<BucketMetrics> byScoreBand;
  final List<BucketMetrics> bySide;
  final List<BucketMetrics> byTimeframe;
  final int minSample;
  final String summary;

  const PerformanceReport({
    required this.overallPaper,
    required this.overallLive,
    required this.byRegime,
    required this.byQuality,
    required this.bySide,
    required this.byScoreBand,
    required this.byTimeframe,
    required this.minSample,
    required this.summary,
  });
}

/// Pure analytics over journal entries — no invented performance.
class PerformanceAnalytics {
  PerformanceAnalytics({this.minSample = 20});

  final int minSample;

  BucketMetrics _bucket(String label, List<JournalEntry> entries) {
    final pending =
        entries.where((e) => e.outcome == JournalOutcome.pending).length;
    final closed = entries
        .where((e) =>
            e.outcome == JournalOutcome.win ||
            e.outcome == JournalOutcome.loss ||
            e.outcome == JournalOutcome.breakeven ||
            e.outcome == JournalOutcome.expired)
        .toList();
    if (closed.isEmpty) {
      return BucketMetrics.empty(label,
          note: pending > 0
              ? 'INSUFFICIENT SAMPLE ($pending pending, 0 closed)'
              : 'INSUFFICIENT SAMPLE');
    }

    final wins = closed.where((e) => e.outcome == JournalOutcome.win).toList();
    final losses =
        closed.where((e) => e.outcome == JournalOutcome.loss).toList();
    var sumR = 0.0, sumWin = 0.0, sumLoss = 0.0;
    for (final e in closed) {
      sumR += e.rMultiple;
    }
    for (final e in wins) {
      sumWin += e.rMultiple > 0 ? e.rMultiple : 0;
    }
    for (final e in losses) {
      sumLoss += e.rMultiple.abs();
    }

    var equity = 0.0, peak = 0.0, maxDd = 0.0;
    for (final e in closed) {
      equity += e.rMultiple;
      if (equity > peak) peak = equity;
      final dd = peak - equity;
      if (dd > maxDd) maxDd = dd;
    }

    final pf = sumLoss <= 0
        ? (sumWin > 0 ? double.infinity : 0.0)
        : sumWin / sumLoss;
    final insuff = closed.length < minSample;

    return BucketMetrics(
      label: label,
      sample: closed.length,
      wins: wins.length,
      losses: losses.length,
      pending: pending,
      winRate: closed.isEmpty ? 0 : wins.length / closed.length,
      expectancyR: sumR / closed.length,
      profitFactor: pf.isFinite ? pf : 0,
      avgR: sumR / closed.length,
      maxDrawdownR: maxDd,
      insufficientSample: insuff,
      note: insuff
          ? 'INSUFFICIENT SAMPLE (n=${closed.length}, need ≥$minSample)'
          : 'VALID SAMPLE',
    );
  }

  List<BucketMetrics> _group(
    List<JournalEntry> entries,
    String Function(JournalEntry) keyOf,
  ) {
    final map = <String, List<JournalEntry>>{};
    for (final e in entries) {
      map.putIfAbsent(keyOf(e), () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return keys.map((k) => _bucket(k, map[k]!)).toList();
  }

  String _scoreBand(double score) {
    if (score >= 90) return '90-100';
    if (score >= 80) return '80-89';
    if (score >= 70) return '70-79';
    if (score >= 60) return '60-69';
    if (score >= 50) return '50-59';
    return '<50';
  }

  PerformanceReport build(List<JournalEntry> all) {
    final paper = all.where((e) => !e.isLive).toList();
    final live = all.where((e) => e.isLive).toList();

    final overallP = _bucket('PAPER', paper);
    final overallL = _bucket('LIVE', live);

    final summary = StringBuffer();
    summary.writeln('Paper closed: ${overallP.sample} · ${overallP.note}');
    summary.writeln('Live closed: ${overallL.sample} · ${overallL.note}');
    if (overallP.insufficientSample && overallL.insufficientSample) {
      summary.writeln(
          'No validated threshold changes — INSUFFICIENT DATA overall.');
    }

    return PerformanceReport(
      overallPaper: overallP,
      overallLive: overallL,
      byRegime: _group(paper, (e) => e.regime),
      byQuality: _group(paper, (e) => e.quality),
      byScoreBand: _group(paper, (e) => _scoreBand(e.score)),
      bySide: _group(paper, (e) => e.side.toUpperCase()),
      byTimeframe: _group(paper, (e) => e.timeframe),
      minSample: minSample,
      summary: summary.toString().trim(),
    );
  }

  /// Suggest live-allowed qualities only when sample is valid and expectancy > 0.
  Set<String> suggestedLiveQualities(PerformanceReport report) {
    final allowed = <String>{};
    for (final b in report.byQuality) {
      if (!b.insufficientSample && b.expectancyR > 0 && b.sample >= minSample) {
        allowed.add(b.label);
      }
    }
    return allowed;
  }

  /// Regimes with measured negative expectancy → prefer WAIT for live.
  Set<String> weakRegimes(PerformanceReport report) {
    final weak = <String>{};
    for (final b in report.byRegime) {
      if (!b.insufficientSample && b.expectancyR < 0) {
        weak.add(b.label);
      }
    }
    return weak;
  }
}
