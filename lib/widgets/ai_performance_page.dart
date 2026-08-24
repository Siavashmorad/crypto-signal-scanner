import 'package:flutter/material.dart';

import '../services/performance_analytics.dart';
import '../services/signal_journal.dart';

class AiPerformancePage extends StatefulWidget {
  final bool english;
  const AiPerformancePage({super.key, required this.english});

  @override
  State<AiPerformancePage> createState() => _AiPerformancePageState();
}

class _AiPerformancePageState extends State<AiPerformancePage> {
  final journal = SignalJournal();
  final analytics = PerformanceAnalytics(minSample: 20);
  List<JournalEntry> entries = [];
  PerformanceReport? report;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final e = await journal.load();
    final r = analytics.build(e);
    if (!mounted) return;
    setState(() {
      entries = e;
      report = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    final r = report;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'AI Performance' : 'عملکرد AI'),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      title: Text(en ? 'Dataset' : 'دیتاست'),
                      subtitle: Text(
                        '${en ? 'Total journal entries' : 'کل رکوردها'}: ${entries.length}\n'
                        '${en ? 'Paper / Live' : 'پیپر / زنده'}: '
                        '${entries.where((e) => !e.isLive).length} / '
                        '${entries.where((e) => e.isLive).length}',
                      ),
                    ),
                  ),
                  if (r != null) ...[
                    _metricCard(en, r.overallPaper),
                    _metricCard(en, r.overallLive),
                    Card(
                      color: Colors.orange.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          r.summary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    Text(en ? 'By Quality' : 'بر اساس کیفیت',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.byQuality.map((b) => _bucketTile(en, b)),
                    Text(en ? 'By Regime' : 'بر اساس رژیم',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.byRegime.map((b) => _bucketTile(en, b)),
                    Text(en ? 'By Score band' : 'بر اساس بازه امتیاز',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.byScoreBand.map((b) => _bucketTile(en, b)),
                    Text(en ? 'By Side' : 'LONG / SHORT',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.bySide.map((b) => _bucketTile(en, b)),
                    Text(en ? 'By Timeframe' : 'بر اساس تایم‌فریم',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.byTimeframe.map((b) => _bucketTile(en, b)),
                    const SizedBox(height: 8),
                    Text(en ? 'Trade Journal' : 'ژورنال معاملات',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...entries.take(40).map((e) => Card(
                          child: ListTile(
                            dense: true,
                            title: Text(
                                '${e.symbol} ${e.side} · ${e.quality} · ${e.regime}'),
                            subtitle: Text(
                              '${e.mode.name} · ${e.outcome.name} · '
                              'R=${e.rMultiple.toStringAsFixed(2)} · '
                              'score=${e.score.toStringAsFixed(0)}\n'
                              '${e.timestamp.toIso8601String()}',
                            ),
                          ),
                        )),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    en
                        ? 'No guaranteed profit. Metrics only from recorded paper/live outcomes. LIVE and PAPER are never mixed.'
                        : 'سود تضمینی نیست. فقط نتایج ثبت‌شده. زنده و پیپر مخلوط نمی‌شوند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _metricCard(bool en, BucketMetrics m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(m.note),
            Text(
              'n=${m.sample}  W/L ${m.wins}/${m.losses}  '
              'WR=${(m.winRate * 100).toStringAsFixed(1)}%  '
              'E=${m.expectancyR.toStringAsFixed(2)}R  '
              'PF=${m.profitFactor.toStringAsFixed(2)}  '
              'DD=${m.maxDrawdownR.toStringAsFixed(2)}R',
            ),
            if (m.pending > 0) Text('${en ? 'Pending' : 'در انتظار'}: ${m.pending}'),
          ],
        ),
      ),
    );
  }

  Widget _bucketTile(bool en, BucketMetrics b) {
    return ListTile(
      dense: true,
      title: Text(b.label),
      subtitle: Text(
        b.insufficientSample
            ? b.note
            : 'n=${b.sample} WR=${(b.winRate * 100).toStringAsFixed(0)}% '
                'E=${b.expectancyR.toStringAsFixed(2)}R PF=${b.profitFactor.toStringAsFixed(2)}',
      ),
    );
  }
}
