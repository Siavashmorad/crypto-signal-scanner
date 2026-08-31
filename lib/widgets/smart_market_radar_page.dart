import 'package:flutter/material.dart';

import '../models/market_data.dart';
import '../services/coin_analysis_service.dart';
import '../services/tabdeal_api.dart';

/// Smart Radar: a read-only decision dashboard built on the existing scanner.
/// It does not create orders and does not alter scanner scoring.
class SmartMarketRadarPage extends StatefulWidget {
  final bool english;
  const SmartMarketRadarPage({super.key, this.english = false});

  @override
  State<SmartMarketRadarPage> createState() => _SmartMarketRadarPageState();
}

class _SmartMarketRadarPageState extends State<SmartMarketRadarPage> {
  late final CoinAnalysisService _service;
  List<MarketSignal> _signals = const [];
  bool _loading = true;
  String? _error;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    _service = CoinAnalysisService(api: TabdealApi());
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final signals = await _service.radar();
      if (!mounted) return;
      setState(() { _signals = signals; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  String _price(double v) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  String _side(MarketSignal s) {
    if (s.side.toUpperCase() == 'LONG') {
      return en ? 'LONG / Spot Buy Bias' : 'صعودی / تمایل خرید اسپات';
    }
    return en ? 'SHORT / Futures Analysis' : 'نزولی / تحلیل فروش استقراضی';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'Smart Market Radar' : 'رادار هوشمند بازار'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: en ? 'Refresh' : 'به‌روزرسانی',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        en ? 'Best measured opportunities' : 'بهترین فرصت‌های اندازه‌گیری‌شده',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(en
                          ? 'Ranks the existing scanner output. No score inflation and no automatic order.'
                          : 'خروجی اسکنر موجود را رتبه‌بندی می‌کند؛ بدون افزایش مصنوعی امتیاز و بدون سفارش خودکار.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(en ? 'Radar unavailable' : 'رادار در دسترس نیست'),
                    subtitle: Text(_error!),
                  ),
                )
              else if (_signals.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.hourglass_empty),
                    title: Text(en ? 'No qualified opportunity' : 'فرصت معتبر پیدا نشد'),
                    subtitle: Text(en
                        ? 'The scanner found no setup meeting its current filters.'
                        : 'اسکنر در شرایط فعلی هیچ موقعیت عبورکرده از فیلترها پیدا نکرد.'),
                  ),
                )
              else
                ..._signals.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final s = entry.value;
                  final long = s.side.toUpperCase() == 'LONG';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(child: Text('$index')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.symbol,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Chip(label: Text('${s.confidence.toStringAsFixed(0)} / 100')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${long ? '🟢' : '🔴'} ${_side(s)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text('${en ? 'Timeframe' : 'بازه زمانی'}: ${s.timeframe}'),
                          Text('${en ? 'Entry' : 'ورود'}: ${_price(s.entry)}'),
                          Text('${en ? 'Stop' : 'حد ضرر'}: ${_price(s.stopLoss)}'),
                          Text('${en ? 'TP1' : 'هدف اول'}: ${_price(s.tp1)}'),
                          Text('${en ? 'R/R' : 'سود به زیان'}: 1:${s.riskReward.toStringAsFixed(1)}'),
                          const SizedBox(height: 6),
                          Text(
                            long
                                ? (en ? 'Spot action: BUY BIAS only when all live gates allow.' : 'اقدام اسپات: فقط تمایل خرید و تنها در صورت عبور از تمام گیت‌های زنده.')
                                : (en ? 'Spot action: WAIT — spot short is not supported.' : 'اقدام اسپات: ⛔ عدم خرید / انتظار — شورت اسپات وجود ندارد.'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: long ? Colors.green : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Text(
                en ? 'Radar is analysis-only. Live execution remains protected by LiveTradingGate.' : 'این رادار فقط تحلیلی است؛ اجرای واقعی همچنان تحت LiveTradingGate و محدودیت‌های ایمنی است.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
