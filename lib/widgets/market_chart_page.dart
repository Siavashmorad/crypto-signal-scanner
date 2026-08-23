import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/market_data.dart';
import '../services/chart_indicators.dart';
import '../services/market_analysis_engine.dart';
import '../services/tabdeal_api.dart';
import '../services/tabdeal_ws.dart';

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
  String depthSource = 'rest';
  String wsStatus = 'idle';
  TabdealDepthSocket? _ws;

  bool showEma20 = true;
  bool showEma50 = false;
  bool showEma200 = false;
  bool showBb = false;
  bool showVwap = false;
  bool showVolume = true;

  Duration get _duration => switch (tf) {
        '5m' => const Duration(minutes: 5),
        '1h' => const Duration(hours: 1),
        '4h' => const Duration(hours: 4),
        '1D' => const Duration(days: 1),
        _ => const Duration(minutes: 15),
      };

  @override
  void initState() {
    super.initState();
    _ws = TabdealDepthSocket(
      onDepth: (d) {
        if (!mounted) return;
        setState(() {
          depth = d;
          depthSource = 'websocket';
        });
      },
      onStatus: (s) {
        if (!mounted) return;
        setState(() => wsStatus = s);
      },
    );
    _ws!.subscribe(widget.signal.symbol);
    _load();
    // REST fallback for trades/candles + depth if WS quiet
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ws?.dispose();
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
      // REST depth only if WS not providing
      if (depthSource != 'websocket' || depth == null) {
        final d = await widget.api.depth(widget.signal.symbol);
        depth = d;
        depthSource = 'rest';
      }

      final byTf = <String, List<Candle>>{
        '5m': widget.api.candlesFromTrades(trades, const Duration(minutes: 5)),
        '15m': widget.api.candlesFromTrades(trades, const Duration(minutes: 15)),
        '1h': widget.api.candlesFromTrades(trades, const Duration(hours: 1)),
        '4h': widget.api.candlesFromTrades(trades, const Duration(hours: 4)),
      };
      final scored = engine.score(
        signal: widget.signal,
        candlesByTf: byTf,
        depth: depth,
      );

      if (!mounted) return;
      setState(() {
        candles = c;
        lastPrice = trades.isEmpty ? null : trades.last.price;
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

  double? get realFillPrice {
    final f = widget.lastOrderFill;
    if (f == null) return null;
    final fills = f['fills'];
    if (fills is List && fills.isNotEmpty) {
      double q = 0, pq = 0;
      for (final row in fills) {
        if (row is! Map) continue;
        final p = double.tryParse('${row['price'] ?? 0}') ?? 0;
        final qty = double.tryParse('${row['qty'] ?? row['quantity'] ?? 0}') ?? 0;
        if (p > 0 && qty > 0) {
          pq += p * qty;
          q += qty;
        }
      }
      if (q > 0) return pq / q;
    }
    final cum = double.tryParse('${f['cummulativeQuoteQty'] ?? f['cumulativeQuoteQty'] ?? 0}');
    final exec = double.tryParse('${f['executedQty'] ?? 0}');
    if (cum != null && exec != null && exec > 0 && cum > 0) return cum / exec;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    final s = widget.signal;
    final px = lastPrice ?? s.entry;
    final fillPx = realFillPrice;
    final trail = candles.isNotEmpty ? engine.suggestedTrailDistance(candles) : null;

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
                  '${en ? 'Price' : 'قیمت'}: ${px.toStringAsFixed(5)}\n'
                  '${isExecuted ? (en ? 'SPOT OPEN (fill ${fillPx?.toStringAsFixed(5) ?? '-'})' : 'اسپات باز (اجرا ${fillPx?.toStringAsFixed(5) ?? '-'})') : (en ? 'SIGNAL / NOT EXECUTED' : 'سیگنال / اجرا نشده')}\n'
                  'WS: $wsStatus · depth: $depthSource',
                ),
                trailing: Chip(label: Text('SPOT ${s.side}')),
              ),
            ),
            Wrap(
              spacing: 6,
              children: ['5m', '15m', '1h', '4h', '1D'].map((t) {
                return ChoiceChip(
                  label: Text(t),
                  selected: tf == t,
                  onSelected: (_) {
                    setState(() => tf = t);
                    _load();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                FilterChip(
                  label: const Text('EMA20'),
                  selected: showEma20,
                  onSelected: (v) => setState(() => showEma20 = v),
                ),
                FilterChip(
                  label: const Text('EMA50'),
                  selected: showEma50,
                  onSelected: (v) => setState(() => showEma50 = v),
                ),
                FilterChip(
                  label: const Text('EMA200'),
                  selected: showEma200,
                  onSelected: (v) => setState(() => showEma200 = v),
                ),
                FilterChip(
                  label: const Text('BB'),
                  selected: showBb,
                  onSelected: (v) => setState(() => showBb = v),
                ),
                FilterChip(
                  label: const Text('VWAP'),
                  selected: showVwap,
                  onSelected: (v) => setState(() => showVwap = v),
                ),
                FilterChip(
                  label: Text(en ? 'Vol' : 'حجم'),
                  selected: showVolume,
                  onSelected: (v) => setState(() => showVolume = v),
                ),
              ],
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
                height: 280,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _CandlePainter(
                      candles: candles,
                      entry: fillPx ?? s.entry,
                      sl: s.stopLoss,
                      tp1: s.tp1,
                      tp2: s.tp2,
                      tp3: s.tp3,
                      ema20: showEma20 ? ChartIndicators.ema(candles, 20) : null,
                      ema50: showEma50 ? ChartIndicators.ema(candles, 50) : null,
                      ema200: showEma200 ? ChartIndicators.ema(candles, 200) : null,
                      bb: showBb ? ChartIndicators.bollinger(candles) : null,
                      vwap: showVwap ? ChartIndicators.vwap(candles) : null,
                      showVolume: showVolume,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _orderBookCard(en),
            _levelsCard(en, s, px, fillPx),
            if (trail != null)
              Card(
                child: ListTile(
                  title: Text(en ? 'Suggested trail (analysis only)' : 'Trailing پیشنهادی (فقط تحلیل)'),
                  subtitle: Text(
                    '${trail.toStringAsFixed(5)} — ${en ? 'NOT placed on exchange' : 'روی صرافی ثبت نمی‌شود'}',
                  ),
                ),
              ),
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
            Text(
              '${en ? 'Order book' : 'اردربوک'} ($depthSource)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Bid: ${bidVol.toStringAsFixed(3)}  Ask: ${askVol.toStringAsFixed(3)}'),
            Text(
              'Imbalance: ${(imb * 100).toStringAsFixed(1)}%  '
              '${imb > 0.05 ? 'BUY' : (imb < -0.05 ? 'SELL' : 'NEUTRAL')}',
            ),
            if (bestBid != null && bestAsk != null)
              Text(
                'Best ${bestBid.toStringAsFixed(4)} / ${bestAsk.toStringAsFixed(4)}'
                '${spread != null ? '  spread ${spread.toStringAsFixed(4)}' : ''}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _levelsCard(bool en, MarketSignal s, double px, double? fillPx) {
    final entry = fillPx ?? s.entry;
    final distEntry = ((px - entry) / entry * 100);
    final distSl = ((px - s.stopLoss) / entry * 100).abs();
    final distTp = ((s.tp1 - px) / entry * 100).abs();
    final rsi = ChartIndicators.lastRsi(candles);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(en ? 'Levels' : 'سطوح',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${fillPx != null ? (en ? 'Real fill entry' : 'ورود واقعی') : 'ENTRY'} '
              '${entry.toStringAsFixed(5)}',
            ),
            Text('SL ${s.stopLoss.toStringAsFixed(5)}'),
            Text(
              'TP1 ${s.tp1.toStringAsFixed(5)}  TP2 ${s.tp2.toStringAsFixed(5)}  TP3 ${s.tp3.toStringAsFixed(5)}',
            ),
            Text('R/R 1:${s.riskReward.toStringAsFixed(1)}'),
            if (rsi != null) Text('RSI(14): ${rsi.toStringAsFixed(1)}'),
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
            Text(en ? 'AI MARKET ANALYSIS' : 'تحلیل بازار AI',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${en ? 'Signal' : 'سیگنال'}: ${a.direction}'),
            Text('${en ? 'Score' : 'امتیاز'}: ${a.score.toStringAsFixed(0)}/100'),
            Text('${en ? 'Confidence' : 'اعتماد'}: ${a.confidence}%'),
            Text('${en ? 'Risk' : 'ریسک'}: ${a.riskLevel}'),
            if (a.breakdown.isNotEmpty)
              Text(a.breakdown.entries
                  .map((e) => '${e.key}:${e.value.toStringAsFixed(1)}')
                  .join(' · ')),
            if (a.missing.isNotEmpty)
              Text('${en ? 'Missing' : 'ناقص'}: ${a.missing.join(', ')}'),
            const Divider(),
            ...a.reasons.take(12).map((r) => Text('• $r')),
          ],
        ),
      ),
    );
  }

  Widget _fillCard(bool en, Map<String, dynamic> fill) {
    return Card(
      color: Colors.green.withOpacity(0.08),
      child: ListTile(
        title: Text(en ? 'Real SPOT fill' : 'اجرای واقعی اسپات'),
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
  final List<double?>? ema20, ema50, ema200, vwap;
  final ({List<double?> mid, List<double?> upper, List<double?> lower})? bb;
  final bool showVolume;

  _CandlePainter({
    required this.candles,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.tp3,
    this.ema20,
    this.ema50,
    this.ema200,
    this.bb,
    this.vwap,
    this.showVolume = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final pad = 12.0;
    final volH = showVolume ? size.height * 0.18 : 0.0;
    final chartH = size.height - pad * 2 - volH;
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

    void line(List<double?> series, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      final n = candles.length;
      final cw = chartW / n;
      for (var i = 0; i < n; i++) {
        final v = series[i];
        if (v == null) continue;
        final x = pad + i * cw + cw / 2;
        final y = yOf(v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (started) canvas.drawPath(path, paint);
    }

    if (ema20 != null) line(ema20!, const Color(0xFFFFC107));
    if (ema50 != null) line(ema50!, const Color(0xFF42A5F5));
    if (ema200 != null) line(ema200!, const Color(0xFFAB47BC));
    if (vwap != null) line(vwap!, const Color(0xFF26C6DA));
    if (bb != null) {
      line(bb!.upper, const Color(0x55FFFFFF));
      line(bb!.mid, const Color(0x88FFFFFF));
      line(bb!.lower, const Color(0x55FFFFFF));
    }

    level(entry, Colors.blueAccent, 'ENTRY');
    level(sl, Colors.redAccent, 'SL');
    level(tp1, Colors.greenAccent, 'TP1');
    level(tp2, Colors.green, 'TP2');
    level(tp3, Colors.tealAccent, 'TP3');

    final n = candles.length;
    final cw = chartW / n;
    final maxVol = candles.map((c) => c.volume).fold<double>(0, math.max);

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

      if (showVolume && maxVol > 0) {
        final vh = (c.volume / maxVol) * volH * 0.9;
        final vy = size.height - pad - vh;
        canvas.drawRect(
          Rect.fromLTRB(x - cw * 0.35, vy, x + cw * 0.35, size.height - pad),
          Paint()..color = (up ? const Color(0x5526A69A) : const Color(0x55EF5350)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles || old.entry != entry || old.showVolume != showVolume;
}
