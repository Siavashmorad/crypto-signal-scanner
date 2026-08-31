import 'dart:async';

import 'package:flutter/material.dart';

import '../services/focus_coin_service_v2.dart';
import '../services/tabdeal_api.dart';
import 'market_chart_page.dart';

/// Deep focus dashboard: re-checks real candles and switches when the setup weakens.
/// Analysis-only; it never sends an order.
class FocusCoinPageV2 extends StatefulWidget {
  final bool english;
  const FocusCoinPageV2({super.key, this.english = false});

  @override
  State<FocusCoinPageV2> createState() => _FocusCoinPageV2State();
}

class _FocusCoinPageV2State extends State<FocusCoinPageV2> {
  late final FocusCoinServiceV2 service;
  FocusSnapshotV2? snap;
  Timer? timer;
  bool auto = true;
  bool loading = true;
  String? error;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    service = FocusCoinServiceV2(api: TabdealApi());
    _run();
    timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (auto && mounted) _run();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (loading && snap != null) return;
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final r = await service.tick(maxSymbols: 40);
      if (!mounted) return;
      setState(() { snap = r; loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = '$e'; });
    }
  }

  String _action(FocusActionV2 a) => switch (a) {
        FocusActionV2.startNow => en ? 'START NOW — review entry' : 'الان شروع کن — بررسی ورود',
        FocusActionV2.wait => en ? 'WAIT — keep watching' : 'انتظار — ادامه پایش',
        FocusActionV2.switchFocus => en ? 'SWITCH FOCUS' : 'تعویض فوکوس',
        FocusActionV2.noSetup => en ? 'NO QUALIFIED SETUP' : 'فرصت معتبر وجود ندارد',
      };

  Color _color(FocusActionV2 a) => switch (a) {
        FocusActionV2.startNow => Colors.green.shade700,
        FocusActionV2.wait => Colors.orange.shade800,
        FocusActionV2.switchFocus => Colors.blue.shade700,
        FocusActionV2.noSetup => Colors.grey.shade700,
      };

  String _px(double? v) {
    if (v == null) return '—';
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  void _openChart() {
    final s = snap?.signal;
    if (s == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MarketChartPage(signal: s, api: TabdealApi(), english: en),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = snap;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'AI Focus' : 'فوکوس هوشمند AI'),
          actions: [
            IconButton(onPressed: loading ? null : _run, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _run,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile(
                  value: auto,
                  onChanged: (v) => setState(() => auto = v),
                  title: Text(en ? 'Auto focus re-check every 60s' : 'بازبینی خودکار فوکوس هر ۶۰ ثانیه'),
                  subtitle: Text(en
                      ? 'Deep-checks candles and switches to another coin when the current setup weakens.'
                      : 'کندل‌ها و چندتایم‌فریم را عمیق بررسی می‌کند و با ضعیف‌شدن موقعیت، ارز را عوض می‌کند.'),
                ),
              ),
              const SizedBox(height: 10),
              if (loading && s == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (error != null)
                Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(en ? 'AI Focus error' : 'خطای فوکوس AI'), subtitle: Text(error!)))
              else if (s != null) ...[
                Card(
                  color: _color(s.action).withOpacity(0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_action(s.action), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: _color(s.action))),
                      const SizedBox(height: 8),
                      Text(s.symbol ?? (en ? 'No focus' : 'بدون فوکوس'), style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text('${en ? 'Deep score' : 'امتیاز عمیق'}: ${s.score.toStringAsFixed(0)}/100 · ${en ? 'Confidence' : 'اطمینان'}: ${s.confidence}%'),
                      Text('${en ? 'TF' : 'تایم‌فریم'}: ${s.timeframe} · ${s.dataSource}'),
                    ]),
                  ),
                ),
                if (s.signal != null) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(en ? 'Real candle chart' : 'نمودار کندلی واقعی', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(en ? 'The decision above was deep-checked from real OHLCV candles.' : 'تصمیم بالا با داده واقعی OHLCV و کندل‌های چندتایم‌فریم بررسی شده است.'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(onPressed: _openChart, icon: const Icon(Icons.candlestick_chart), label: Text(en ? 'Open candles + indicators' : 'مشاهده کندل‌ها و اندیکاتورها')),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(en ? 'Plan' : 'طرح تحلیلی', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${en ? 'Entry' : 'ورود'}: ${_px(s.entry)}'),
                        Text('${en ? 'Stop' : 'حد ضرر'}: ${_px(s.stopLoss)}'),
                        Text('${en ? 'TP1' : 'هدف ۱'}: ${_px(s.tp1)}'),
                        Text('${en ? 'TP2' : 'هدف ۲'}: ${_px(s.tp2)}'),
                        Text('${en ? 'TP3' : 'هدف ۳'}: ${_px(s.tp3)}'),
                        Text('${en ? 'R/R' : 'ریسک/بازده'}: 1:${s.riskReward.toStringAsFixed(1)}'),
                        const SizedBox(height: 6),
                        Text(en ? 'SPOT: LONG/buy bias only.' : 'اسپات: فقط تمایل خرید / LONG.'),
                      ]),
                    ),
                  ),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(en ? 'Why this focus?' : 'چرا این ارز انتخاب شد؟', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...s.reasonsFa.map((r) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r'))),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(en
                  ? 'Analysis only. No automatic order. Existing LiveTradingGate, 50-USDT cap and LONG-only SPOT rules remain unchanged.'
                  : 'فقط تحلیل. بدون سفارش خودکار. LiveTradingGate، سقف ۵۰ تتر و قانون LONG-only اسپات دست‌نخورده باقی می‌مانند.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
