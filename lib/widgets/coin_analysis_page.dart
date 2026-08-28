import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import '../services/coin_analysis_service.dart';
import '../services/fa_labels.dart';
import '../services/tabdeal_api.dart';

/// تب مستقل «تحلیل ارز» — UI کاملاً فارسی.
class CoinAnalysisPage extends StatefulWidget {
  final bool english;
  const CoinAnalysisPage({super.key, this.english = false});

  @override
  State<CoinAnalysisPage> createState() => _CoinAnalysisPageState();
}

class _CoinAnalysisPageState extends State<CoinAnalysisPage> {
  final _searchCtrl = TextEditingController();
  late final CoinAnalysisService _svc;
  late final TabdealApi _api;

  CoinAnalysisResult? _result;
  List<MarketSignal> _radar = const [];
  List<CoinAnalysisResult> _history = const [];
  List<String> _watchlist = const [];
  bool _loading = false;
  bool _radarLoading = false;
  String? _error;
  bool _autoRefresh = false;
  int _autoSeconds = 30;
  Timer? _autoTimer;
  bool _preferSpot = true;

  @override
  void initState() {
    super.initState();
    _api = TabdealApi();
    _svc = CoinAnalysisService(api: _api);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final preferFutures = prefs.getBool('prefer_futures_execution') ?? false;
    final w = await _svc.loadWatchlist();
    final h = await _svc.loadHistory();
    if (!mounted) return;
    setState(() {
      _preferSpot = !preferFutures;
      _watchlist = w;
      _history = h;
    });
    _loadRadar();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setAutoRefresh(bool on) {
    _autoTimer?.cancel();
    setState(() => _autoRefresh = on);
    if (on && _result != null) {
      _autoTimer = Timer.periodic(Duration(seconds: _autoSeconds), (_) {
        if (_result != null) _analyze(_result!.symbol, silent: true);
      });
    }
  }

  Future<void> _analyze(String raw, {bool silent = false}) async {
    final sym = _svc.normalizeInput(raw);
    if (sym.isEmpty) {
      setState(() => _error = 'نماد نامعتبر است');
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await _svc.analyze(sym, preferSpot: _preferSpot);
      await _svc.saveToHistory(r);
      final h = await _svc.loadHistory();
      if (!mounted) return;
      setState(() {
        _result = r;
        _history = h;
        _loading = false;
        _searchCtrl.text = sym;
      });
      if (_autoRefresh) _setAutoRefresh(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'خطا در دریافت داده: $e';
      });
    }
  }

  Future<void> _loadRadar() async {
    setState(() => _radarLoading = true);
    try {
      final list = await _svc.radar();
      if (!mounted) return;
      setState(() {
        _radar = list;
        _radarLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _radarLoading = false);
    }
  }

  Future<void> _toggleWatch(String sym) async {
    final n = _svc.normalizeInput(sym);
    if (_watchlist.contains(n)) {
      await _svc.removeFromWatchlist(n);
    } else {
      await _svc.addToWatchlist(n);
    }
    final w = await _svc.loadWatchlist();
    if (mounted) setState(() => _watchlist = w);
  }

  String _fmtPrice(double? v) {
    if (v == null) return '—';
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  String _fmtTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  Color _decisionColor(CoinDecision d) {
    switch (d) {
      case CoinDecision.buy:
        return Colors.green;
      case CoinDecision.sell:
        return Colors.red;
      case CoinDecision.wait:
        return Colors.orange;
      case CoinDecision.noTrade:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحلیل ارز'),
          actions: [
            IconButton(
              tooltip: 'به‌روزرسانی رادار',
              onPressed: _radarLoading ? null : _loadRadar,
              icon: _radarLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            if (_result != null) await _analyze(_result!.symbol);
            await _loadRadar();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _searchCard(),
              const SizedBox(height: 12),
              if (_error != null)
                Card(
                  color: Colors.red.withOpacity(0.1),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(_error!),
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_result != null && !_loading) ...[
                _resultCard(_result!),
                const SizedBox(height: 12),
                _tradePlanCard(_result!),
                const SizedBox(height: 12),
                _whyCard(_result!),
                const SizedBox(height: 12),
                _levelsCard(_result!),
                const SizedBox(height: 12),
                _mtfCard(_result!),
                const SizedBox(height: 12),
                _actionsRow(_result!),
              ],
              const SizedBox(height: 16),
              _watchlistSection(),
              const SizedBox(height: 16),
              _radarSection(),
              const SizedBox(height: 16),
              _historySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'جستجوی ارز',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _analyze(v),
              decoration: const InputDecoration(
                hintText: 'مثلاً BTC یا BTCUSDT',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : () => _analyze(_searchCtrl.text),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('تحلیل کن'),
            ),
            const SizedBox(height: 6),
            Text(
              _preferSpot ? 'بازار: نقدی (اسپات)' : 'بازار: آتی (اختیاری)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(CoinAnalysisResult r) {
    final color = _decisionColor(r.decision);
    return Card(
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.symbol.replaceAll('USDT', ' / USDT'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (r.dataStale)
                  const Chip(
                    label: Text('⚠️ داده‌ها به‌روز نیستند'),
                    backgroundColor: Color(0x33FF9800),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'نتیجه تحلیل',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              '${r.decision.emoji} ${r.decision.label}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              r.tierFa,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 24),
            _kv('امتیاز تحلیل', '${r.score.toStringAsFixed(0)} / ۱۰۰'),
            _kv('اطمینان تحلیل', '${r.confidence}٪'),
            _kv('روند کوتاه‌مدت', r.trendShortFa),
            _kv('روند میان‌مدت', r.trendMidFa),
            _kv('روند اصلی', r.trendMainFa),
            _kv('وضعیت بازار', r.regimeFa),
            if (r.lastPrice != null) _kv('قیمت', _fmtPrice(r.lastPrice)),
            _kv('آخرین به‌روزرسانی', _fmtTime(r.analyzedAt)),
            _kv('سن داده', '${r.dataAgeSeconds} ثانیه'),
            if (r.conflictAcrossTf)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ تضاد بین بازه‌های زمانی',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
            if (r.noTradeReasonsFa.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...r.noTradeReasonsFa.map(
                (e) => Text(e, style: const TextStyle(color: Colors.redAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tradePlanCard(CoinAnalysisResult r) {
    if (!r.hasTradePlan) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.block),
          title: const Text('برنامه معاملاتی'),
          subtitle: Text(
            r.decision == CoinDecision.noTrade || r.decision == CoinDecision.wait
                ? 'ورود توصیه نمی‌شود'
                : 'برنامه ورود محاسبه نشد',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('برنامه معاملاتی',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _kv('نقطه ورود پیشنهادی', _fmtPrice(r.entry)),
            _kv('حد ضرر', _fmtPrice(r.stopLoss)),
            _kv('هدف اول', _fmtPrice(r.tp1)),
            if (r.tp2 != null) _kv('هدف دوم', _fmtPrice(r.tp2)),
            if (r.tp3 != null) _kv('هدف سوم', _fmtPrice(r.tp3)),
            _kv(
              'نسبت سود به زیان',
              r.riskReward != null
                  ? '۱ : ${r.riskReward!.toStringAsFixed(1)}'
                  : '—',
            ),
          ],
        ),
      ),
    );
  }

  Widget _whyCard(CoinAnalysisResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('چرا این تحلیل؟',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (r.reasonsFa.isEmpty)
              const Text('دلیل محاسبه‌شده‌ای ثبت نشد.')
            else
              ...r.reasonsFa.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(e)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _levelsCard(CoinAnalysisResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('حمایت و مقاومت',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'حمایت‌ها: ${r.supports.isEmpty ? '—' : r.supports.map(_fmtPrice).join('  |  ')}',
            ),
            const SizedBox(height: 4),
            Text(
              'مقاومت‌ها: ${r.resistances.isEmpty ? '—' : r.resistances.map(_fmtPrice).join('  |  ')}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _mtfCard(CoinAnalysisResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تحلیل چندبازه‌ای',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...r.timeframes.map((t) {
              final icon = !t.available
                  ? '⚪'
                  : (t.bias == 'LONG'
                      ? '🟢'
                      : (t.bias == 'SHORT' ? '🔴' : '🟡'));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 72, child: Text(t.labelFa)),
                    Text('$icon  ${t.biasFa}'),
                    if (t.rsi != null) ...[
                      const Spacer(),
                      Text('RSI ${t.rsi!.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow(CoinAnalysisResult r) {
    final inWatch = _watchlist.contains(r.symbol);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _toggleWatch(r.symbol),
          icon: Icon(inWatch ? Icons.star : Icons.star_border),
          label: Text(inWatch ? 'حذف از علاقه‌مندی‌ها' : 'افزودن به علاقه‌مندی‌ها'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _analyze(r.symbol),
          icon: const Icon(Icons.refresh),
          label: const Text('به‌روزرسانی'),
        ),
        FilterChip(
          label: Text(_autoRefresh
              ? 'خودکار هر $_autoSeconds ثانیه'
              : 'به‌روزرسانی خودکار'),
          selected: _autoRefresh,
          onSelected: (v) {
            if (v) {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: const Text('۱۵ ثانیه'),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() => _autoSeconds = 15);
                            _setAutoRefresh(true);
                          },
                        ),
                        ListTile(
                          title: const Text('۳۰ ثانیه'),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() => _autoSeconds = 30);
                            _setAutoRefresh(true);
                          },
                        ),
                        ListTile(
                          title: const Text('۶۰ ثانیه'),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() => _autoSeconds = 60);
                            _setAutoRefresh(true);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } else {
              _setAutoRefresh(false);
            }
          },
        ),
      ],
    );
  }

  Widget _watchlistSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ارزهای مورد علاقه',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_watchlist.isEmpty)
              const Text('لیست خالی است')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _watchlist
                    .map(
                      (s) => ActionChip(
                        label: Text(s.replaceAll('USDT', '')),
                        onPressed: () => _analyze(s),
                        avatar: const Icon(Icons.star, size: 16),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _radarSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('رادار فرصت‌ها',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (_radarLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_radar.isEmpty && !_radarLoading)
              const Text('⛔ فعلاً فرصت مناسبی وجود ندارد')
            else
              ..._radar.take(8).toList().asMap().entries.map((e) {
                final i = e.key + 1;
                final s = e.value;
                final score = s.confidence;
                final tier = FaLabels.scoreTier(score);
                final side = FaLabels.side(s.side);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('$i', style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(
                      '${s.symbol.replaceAll('USDT', '')} — ${score.toStringAsFixed(0)} — $tier'),
                  subtitle: Text('$side · ${s.timeframe}'),
                  onTap: () => _analyze(s.symbol),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _historySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تاریخچه تحلیل‌ها',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Text('هنوز تحلیلی ذخیره نشده')
            else
              ..._history.take(12).map((h) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${h.symbol.replaceAll('USDT', '')} — ${h.score.toStringAsFixed(0)} — ${h.decision.label}'),
                  subtitle: Text(
                      '${_fmtTime(h.analyzedAt)} · قیمت ${_fmtPrice(h.lastPrice)}'),
                  onTap: () => _analyze(h.symbol),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
