import 'dart:async';

import 'package:flutter/material.dart';

import '../services/focus_coin_service.dart';
import '../services/tabdeal_api.dart';

/// صفحه فوکوس روی یک ارز قوی — فقط تحلیل، بدون سفارش.
/// هر چند ثانیه یک‌بار کندل/امتیاز را چک می‌کند؛ اگر ضعیف شد فوکوس عوض می‌شود.
class FocusCoinPage extends StatefulWidget {
  final bool english;
  const FocusCoinPage({super.key, this.english = false});

  @override
  State<FocusCoinPage> createState() => _FocusCoinPageState();
}

class _FocusCoinPageState extends State<FocusCoinPage> {
  late final FocusCoinService _service;
  FocusSnapshot? _snap;
  bool _loading = true;
  bool _auto = true;
  String? _error;
  Timer? _timer;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    _service = FocusCoinService(api: TabdealApi());
    _run();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_auto && mounted) _run();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snap = await _service.tick();
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _actionTitle(FocusAction a) {
    switch (a) {
      case FocusAction.startNow:
        return en ? 'START NOW (review entry)' : 'الان شروع کن (بررسی ورود)';
      case FocusAction.wait:
        return en ? 'WAIT — keep watching' : 'صبر کن — ادامه پایش';
      case FocusAction.switchFocus:
        return en ? 'SWITCH FOCUS' : 'تعویض فوکوس';
      case FocusAction.noSetup:
        return en ? 'No strong setup' : 'فرصت قوی نیست';
    }
  }

  Color _actionColor(FocusAction a) {
    switch (a) {
      case FocusAction.startNow:
        return Colors.green.shade700;
      case FocusAction.wait:
        return Colors.orange.shade800;
      case FocusAction.switchFocus:
        return Colors.blue.shade700;
      case FocusAction.noSetup:
        return Colors.grey.shade700;
    }
  }

  String _px(double? v) {
    if (v == null) return '—';
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'Focus Mode' : 'حالت فوکوس'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.refresh),
              tooltip: en ? 'Refresh now' : 'به‌روزرسانی',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _run,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile(
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                  title: Text(en
                      ? 'Auto re-check every 45s'
                      : 'بررسی خودکار هر ۴۵ ثانیه'),
                  subtitle: Text(en
                      ? 'Watches candles; switches coin if focus weakens'
                      : 'کندل‌ها را می‌بیند؛ اگر فوکوس ضعیف شد ارز را عوض می‌کند'),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading && snap == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(en ? 'Focus failed' : 'خطا در فوکوس'),
                    subtitle: Text(_error!),
                  ),
                )
              else if (snap != null) ...[
                Card(
                  color: _actionColor(snap.action).withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _actionTitle(snap.action),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _actionColor(snap.action),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snap.symbol == null
                              ? (en ? 'No focus' : 'بدون فوکوس')
                              : (en
                                  ? 'Focus: ${snap.symbol}'
                                  : 'فوکوس فعلی: ${snap.symbol}'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${en ? 'Score' : 'امتیاز'}: ${snap.score.toStringAsFixed(0)} / 100'\
                          ' · ${snap.timeframe}'\
                          ' · ${snap.dataSource}',
                        ),
                      ],
                    ),
                  ),
                ),
                if (snap.symbol != null) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(en ? 'Plan (analysis only)' : 'طرح تحلیلی (بدون سفارش)'),
                          const SizedBox(height: 8),
                          Text('${en ? 'Entry' : 'ورود'}: ${_px(snap.entry)}'),
                          Text('${en ? 'Stop' : 'حد ضرر'}: ${_px(snap.stopLoss)}'),
                          Text('${en ? 'TP1' : 'هدف ۱'}: ${_px(snap.tp1)}'),
                          Text('${en ? 'R/R' : 'ریسک/بازده'}: 1:${snap.riskReward.toStringAsFixed(1)}'),
                          Text('${en ? 'Side' : 'جهت'}: ${snap.side} (SPOT LONG-only action)'),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          en ? 'Why' : 'دلایل',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...snap.reasonsFa.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(r)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                en
                    ? 'Focus mode never sends orders. LiveTradingGate and size limits stay unchanged. Data: api1.tabdeal.org.'
                    : 'حالت فوکوس هیچ سفارشی نمی‌فرستد. LiveTradingGate و سقف حجم دست‌نخورده است. داده: api1.tabdeal.org.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
