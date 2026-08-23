import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/market_data.dart';
import '../services/market_analysis_engine.dart';
import '../services/tabdeal_api.dart';

/// Chart + multi-TF analysis from real Tabdeal trades (no fake prices).
class MarketChartPage extends StatefulWidget {
  final MarketSignal signal;
  final TabdealApi api;
  final bool english;
  final Map<String, dynamic>? lastOrderFill;

  const MarketChartPage({
    super.key,
    required this.signal,
    required this.api,
    required this.english,
    this.lastOrderFill,
  });

  @override
  State<MarketChartPage> createState() => _MarketChartPageState();
}

class _MarketChartPageState extends State<MarketChartPage> {
  final engine = MarketAnalysisEngine();
  String tf = '15m';
  List<Candle> candles = [];
  double? lastPrice;
  bool loading = true;
  String? error;
  ScoredAnalysis? analysis;
  Timer? _poll;
  Map<String, dynamic>? depth;

  Duration get _duration => switch (tf) {
        '1m' => const Duration(minutes: 1),
        '5m' => const Duration(minutes: 5),
        '1h' => const Duration(hours: 1),
        '4h' => const Duration(hours: 4),
        '1D' => const Duration(days: 1),
        _ => const Duration(minutes: 15),
      };

  @override
  void initState() {
    super.initState();
    _load();
    // REST polling ~12s (Tabdeal spot WS exists for depth; trades still via REST)
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final trades = await widget.api.trades(widget.signal.symbol, limit: 500);
      final c = widget.api.candlesFromTrades(trades, _duration);
      final d = await widget.api.depth(widget.signal.symbol);

      final byTf = <String, List<Candle>>{
        '5m': widget.api.candlesFromTrades(trades, const Duration(minutes: 5)),
        '15m': widget.api.candlesFromTrades(trades, const Duration(minutes: 15)),
        '1h': widget.api.candlesFromTrades(trades, const Duration(hours: 1)),
        '4h': widget.api.candlesFromTrades(trades, const Duration(hours: 4)),
      };
      final scored = engine.score(
        signal: widget.signal,
        candlesByTf: byTf,
        depth: d,
      );

      if (!mounted) return;
      setState(() {
        candles = c;
        lastPrice = trades.isEmpty ? null : trades.last.price;
        depth = d;
        analysis = scored;
        loading = false;
        error = c.isEmpty
            ? (widget.english ? 'Not enough trades' : 'معامله کافی نیست')
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  bool get isExecuted =>
      widget.lastOrderFill != null &&
      (widget.lastOrderFill!['orderId'] != null ||
          widget.lastOrderFill!['executedQty'] != null);

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    final s = widget.signal;
    final px = lastPrice ?? s.entry;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${s.symbol} — ${en ? 'Chart' : 'نمودار'}'),
          actions: [
            IconButton(
                onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                title: Text(s.symbol,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                subtitle: Text(
                  '${en ? 'Price' : 'قیمت'}: ${px.toStringAsFixed(5)}  ·  '
                  '${isExecuted ? (en ? 'OPEN POSITION (SPOT)' : 'پوزیشن اسپات باز') : (en ? 'SIGNAL / NOT EXECUTED' : 'سیگنال / اجرا نشده')}',
                ),
                trailing: Chip(label: Text('SPOT ${s.side}')),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['1m', '5m', '15m', '1h', '4h', '1D'].map((t) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: tf == t,
                      onSelected: (_) {
                        setState(() => tf = t);
                        _load();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            if (loading)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              Card(child: ListTile(title: Text(error!)))
            else
              SizedBox(
                height: 260,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _CandlePainter(
                      candles: candles,
                      entry: s.entry,
                      sl: s.stopLoss,
                      tp1: s.tp1,
                      tp2: s.tp2,
                      tp3: s.tp3,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _orderBookCard(en),
            _levelsCard(en, s, px),
            if (analysis != null) _aiCard(en, analysis!),
            if (isExecuted) _fillCard(en, widget.lastOrderFill!),
          ],
        ),
      ),
    );
  }

  Widget _orderBookCard(bool en) {
    final d = depth;
    if (d == null) {
      return Card(
        child: ListTile(
          title: Text(en ? 'Order book' : 'اردربوک'),
          subtitle: Text(en ? 'Unavailable' : 'در دسترس نیست'),
        ),
      );
    }
    final bids = d['bids'];
    final asks = d['asks'];
    if (bids is! List || asks is! List || bids.isEmpty || asks.isEmpty) {
      return Card(
        child: ListTile(
          title: Text(en ? 'Order book' : 'اردربوک'),
          subtitle: Text(en ? 'Unavailable' : 'در دسترس نیست'),
        ),
      );
    }
    double bidVol = 0, askVol = 0;
    double? bestBid, bestAsk;
    for (final row in bids.take(10)) {
      if (row is List && row.length >= 2) {
        final p = double.tryParse('${row[0]}');
        final q = double.tryParse('${row[1]}') ?? 0;
        bidVol += q;
        bestBid ??= p;
      }
    }
    for (final row in asks.take(10)) {
      if (row is List && row.length >= 2) {
        final p = double.tryParse('${row[0]}');
        final q = double.tryParse('${row[1]}') ?? 0;
        askVol += q;
        bestAsk ??= p;
      }
    }
    final sum = bidVol + askVol;
    final imb = sum > 0 ? (bidVol - askVol) / sum : 0.0;
    final spread =
        (bestBid != null && bestAsk != null) ? (bestAsk - bestBid) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(en ? 'Order book (real)' : 'اردربوک واقعی',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Bid vol: ${bidVol.toStringAsFixed(3)}  Ask vol: ${askVol.toStringAsFixed(3)}'),
            Text(
              'Imbalance: ${(imb * 100).toStringAsFixed(1)}%  '
              '${imb > 0.05 ? 'BUY' : (imb < -0.05 ? 'SELL' : 'NEUTRAL')}',
            ),
            if (bestBid != null && bestAsk != null)
              Text('Best ${bestBid.toStringAsFixed(4)} / ${bestAsk.toStringAsFixed(4)}'
                  '${spread != null ? '  spread ${spread.toStringAsFixed(4)}' : ''}'),
          ],
        ),
      ),
    );
  }

  Widget _levelsCard(bool en, MarketSignal s, double px) {
    final distEntry = ((px - s.entry) / s.entry * 100);
    final distSl = ((px - s.stopLoss) / s.entry * 100).abs();
    final distTp = ((s.tp1 - px) / s.entry * 100).abs();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(en ? 'Levels' : 'سطوح',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('ENTRY ${s.entry.toStringAsFixed(5)}'),
            Text('SL ${s.stopLoss.toStringAsFixed(5)}'),
            Text(
                'TP1 ${s.tp1.toStringAsFixed(5)}  TP2 ${s.tp2.toStringAsFixed(5)}  TP3 ${s.tp3.toStringAsFixed(5)}'),
            Text('R/R 1:${s.riskReward.toStringAsFixed(1)}'),
            Text(
              '${en ? 'Dist Entry' : 'فاصله ورود'}: ${distEntry.toStringAsFixed(2)}%  '
              'SL: ${distSl.toStringAsFixed(2)}%  TP1: ${distTp.toStringAsFixed(2)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCard(bool en, ScoredAnalysis a) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(en ? 'AI Analysis (on-device)' : 'تحلیل هوش مصنوعی (روی دستگاه)',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${en ? 'Direction' : 'جهت'}: ${a.direction}'),
            Text('${en ? 'Score' : 'امتیاز'}: ${a.score.toStringAsFixed(0)}/100'),
            Text('${en ? 'Confidence' : 'اعتماد'}: ${a.confidence}%'),
            Text('${en ? 'Risk' : 'ریسک'}: ${a.riskLevel}'),
            if (a.breakdown.isNotEmpty)
              Text(a.breakdown.entries
                  .map((e) => '${e.key}:${e.value.toStringAsFixed(1)}')
                  .join(' · ')),
            if (a.missing.isNotEmpty)
              Text('${en ? 'Missing data' : 'داده ناقص'}: ${a.missing.join(', ')}'),
            const Divider(),
            ...a.reasons.map((r) => Text('• $r')),
          ],
        ),
      ),
    );
  }

  Widget _fillCard(bool en, Map<String, dynamic> fill) {
    return Card(
      color: Colors.green.withOpacity(0.08),
      child: ListTile(
        title: Text(en ? 'Real SPOT fill from Tabdeal' : 'اجرای واقعی اسپات از تبدیل'),
        subtitle: Text(
          'orderId: ${fill['orderId'] ?? fill['order_id'] ?? '-'}\n'
          'executedQty: ${fill['executedQty'] ?? fill['executed_qty'] ?? '-'}\n'
          'status: ${fill['status'] ?? '-'}',
        ),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  final double entry, sl, tp1, tp2, tp3;

  _CandlePainter({
    required this.candles,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.tp3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final pad = 12.0;
    final chartH = size.height - pad * 2;
    final chartW = size.width - pad * 2;

    var minP = candles.map((c) => c.low).reduce(math.min);
    var maxP = candles.map((c) => c.high).reduce(math.max);
    for (final p in [entry, sl, tp1, tp2, tp3]) {
      minP = math.min(minP, p);
      maxP = math.max(maxP, p);
    }
    final range = (maxP - minP).abs() < 1e-12 ? 1.0 : (maxP - minP);

    double yOf(double price) => pad + chartH * (1 - (price - minP) / range);

    final bg = Paint()..color = const Color(0xFF12141C);
    canvas.drawRect(Offset.zero & size, bg);

    void level(double price, Color color, String label) {
      final y = yOf(price);
      final paint = Paint()
        ..color = color.withOpacity(0.85)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), paint);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pad + 2, y - 12));
    }

    level(entry, Colors.blueAccent, 'ENTRY');
    level(sl, Colors.redAccent, 'SL');
    level(tp1, Colors.greenAccent, 'TP1');
    level(tp2, Colors.green, 'TP2');
    level(tp3, Colors.tealAccent, 'TP3');

    final n = candles.length;
    final cw = chartW / n;
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final x = pad + i * cw + cw / 2;
      final up = c.close >= c.open;
      final paint = Paint()
        ..color = up ? const Color(0xFF26A69A) : const Color(0xFFEF5350)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, yOf(c.high)), Offset(x, yOf(c.low)), paint);
      final bodyTop = yOf(math.max(c.open, c.close));
      final bodyBot = yOf(math.min(c.open, c.close));
      canvas.drawRect(
        Rect.fromLTRB(x - cw * 0.3, bodyTop, x + cw * 0.3, bodyBot),
        paint..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles || old.entry != entry;
}
