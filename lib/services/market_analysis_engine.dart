import '../models/market_data.dart';

/// Multi-timeframe technical scoring from real OHLCV only — no fake data.
class MarketAnalysisEngine {
  double _ema(List<double> v, int period) {
    if (v.length < period) return v.isEmpty ? 0 : v.last;
    var ema = v.take(period).reduce((a, b) => a + b) / period;
    final m = 2 / (period + 1);
    for (final x in v.skip(period)) {
      ema = (x - ema) * m + ema;
    }
    return ema;
  }

  double _rsi(List<double> closes, int period) {
    if (closes.length <= period) return 50;
    var gain = 0.0, loss = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      final d = closes[i] - closes[i - 1];
      if (d >= 0) {
        gain += d;
      } else {
        loss -= d;
      }
    }
    if (loss == 0) return 100;
    final rs = gain / loss;
    return 100 - (100 / (1 + rs));
  }

  double _atr(List<Candle> c, int period) {
    if (c.length < period + 1) return 0;
    final trs = <double>[];
    for (var i = 1; i < c.length; i++) {
      final cur = c[i];
      final prev = c[i - 1];
      trs.add([
        cur.high - cur.low,
        (cur.high - prev.close).abs(),
        (cur.low - prev.close).abs(),
      ].reduce((a, b) => a > b ? a : b));
    }
    return trs.skip(trs.length - period).reduce((a, b) => a + b) / period;
  }

  TfSnapshot analyzeTf(List<Candle> candles, String label) {
    if (candles.length < 15) {
      return TfSnapshot(
        label: label,
        available: false,
        note: 'داده کافی برای $label نیست',
      );
    }
    final closes = candles.map((e) => e.close).toList();
    final vols = candles.map((e) => e.volume).toList();
    final last = closes.last;
    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final rsi = _rsi(closes, 14);
    final atr = _atr(candles, 14);
    final volAvg = vols.length >= 10
        ? vols.skip(vols.length - 10).reduce((a, b) => a + b) / 10
        : vols.reduce((a, b) => a + b) / vols.length;
    final volLast = vols.last;
    final volRising = volLast > volAvg * 1.1;

    String bias;
    if (ema9 > ema21 && rsi >= 48 && rsi <= 72) {
      bias = 'BULLISH';
    } else if (ema9 < ema21 && rsi <= 52 && rsi >= 28) {
      bias = 'BEARISH';
    } else {
      bias = 'NEUTRAL';
    }

    return TfSnapshot(
      label: label,
      available: true,
      bias: bias,
      ema9: ema9,
      ema21: ema21,
      rsi: rsi,
      atr: atr,
      last: last,
      volumeRising: volRising,
      note: '$label: $bias RSI=${rsi.toStringAsFixed(0)}',
    );
  }

  /// Weighted multi-TF score. Missing TF does not invent data — weight redistributed.
  ScoredAnalysis score({
    required MarketSignal signal,
    required Map<String, List<Candle>> candlesByTf,
    Map<String, dynamic>? depth,
  }) {
    final snapshots = <TfSnapshot>[];
    for (final e in candlesByTf.entries) {
      snapshots.add(analyzeTf(e.value, e.key));
    }

    final available = snapshots.where((s) => s.available).toList();
    if (available.isEmpty) {
      return ScoredAnalysis(
        direction: 'WAIT',
        score: 0,
        confidence: 0,
        riskLevel: 'UNKNOWN',
        reasons: const ['داده تایم‌فریم کافی از صرافی دریافت نشد'],
        missing: const ['all timeframes'],
        snapshots: snapshots,
      );
    }

    // Weights: Trend(1h) 25, Momentum(15m) 20, Structure 15, Structure 15, Vol 10, S/R 10, Book 5
    var score = 50.0;
    final reasons = <String>[];
    final missing = <String>[];
    final isLong = signal.side.toUpperCase() == 'LONG';

    for (final s in available) {
      if (s.bias == 'BULLISH') {
        score += isLong ? 8 : -6;
        reasons.add('${s.label}: صعودی');
      } else if (s.bias == 'BEARISH') {
        score += isLong ? -6 : 8;
        reasons.add('${s.label}: نزولی');
      } else {
        reasons.add('${s.label}: خنثی');
      }
      if (s.volumeRising) {
        score += 3;
        reasons.add('${s.label}: حجم افزایشی');
      }
    }
    for (final s in snapshots.where((x) => !x.available)) {
      missing.add(s.label);
    }

    // Order book if real depth present
    var bookNote = 'اردربوک: در دسترس نیست';
    if (depth != null) {
      final bids = depth['bids'];
      final asks = depth['asks'];
      if (bids is List && asks is List && bids.isNotEmpty && asks.isNotEmpty) {
        double b = 0, a = 0;
        for (final row in bids.take(10)) {
          if (row is List && row.length >= 2) b += double.tryParse('${row[1]}') ?? 0;
        }
        for (final row in asks.take(10)) {
          if (row is List && row.length >= 2) a += double.tryParse('${row[1]}') ?? 0;
        }
        if (b + a > 0) {
          final imb = (b - a) / (b + a);
          score += isLong ? imb * 10 : -imb * 10;
          bookNote = 'نبود تعادل اردربوک: ${imb.toStringAsFixed(2)}';
          reasons.add(bookNote);
        }
      } else {
        missing.add('orderbook');
      }
    } else {
      missing.add('orderbook');
    }

    score = score.clamp(0, 100);
    String direction;
    if (score >= 62 && isLong) {
      direction = 'LONG';
    } else if (score >= 62 && !isLong) {
      direction = 'SHORT';
    } else if (score <= 40) {
      direction = 'WAIT';
    } else {
      direction = 'WAIT';
    }

    // Selective: low score → WAIT
    if (score < 58) direction = 'WAIT';

    final atrPct = signal.entry > 0 ? (signal.atr / signal.entry) * 100 : 0;
    final risk = atrPct >= 2.5 ? 'HIGH' : (atrPct >= 1.2 ? 'MEDIUM' : 'CONTROLLED');

    return ScoredAnalysis(
      direction: direction,
      score: score,
      confidence: score.round(),
      riskLevel: risk,
      reasons: reasons,
      missing: missing,
      snapshots: snapshots,
    );
  }
}

class TfSnapshot {
  final String label;
  final bool available;
  final String bias;
  final double ema9;
  final double ema21;
  final double rsi;
  final double atr;
  final double last;
  final bool volumeRising;
  final String note;

  const TfSnapshot({
    required this.label,
    this.available = true,
    this.bias = 'NEUTRAL',
    this.ema9 = 0,
    this.ema21 = 0,
    this.rsi = 50,
    this.atr = 0,
    this.last = 0,
    this.volumeRising = false,
    this.note = '',
  });
}

class ScoredAnalysis {
  final String direction;
  final double score;
  final int confidence;
  final String riskLevel;
  final List<String> reasons;
  final List<String> missing;
  final List<TfSnapshot> snapshots;

  const ScoredAnalysis({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.riskLevel,
    required this.reasons,
    required this.missing,
    required this.snapshots,
  });
}
