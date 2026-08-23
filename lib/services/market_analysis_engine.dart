import '../models/market_data.dart';

/// Multi-timeframe + market structure scoring from real OHLCV only.
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

  StructureSnapshot structure(List<Candle> candles) {
    if (candles.length < 20) {
      return const StructureSnapshot(
          available: false, note: 'داده ساختار کافی نیست');
    }
    final highs = <double>[];
    final lows = <double>[];
    for (var i = 2; i < candles.length - 2; i++) {
      final h = candles[i].high;
      final l = candles[i].low;
      if (h >= candles[i - 1].high &&
          h >= candles[i - 2].high &&
          h >= candles[i + 1].high &&
          h >= candles[i + 2].high) {
        highs.add(h);
      }
      if (l <= candles[i - 1].low &&
          l <= candles[i - 2].low &&
          l <= candles[i + 1].low &&
          l <= candles[i + 2].low) {
        lows.add(l);
      }
    }
    if (highs.length < 2 || lows.length < 2) {
      return const StructureSnapshot(available: false, note: 'سویینگ کافی نیست');
    }
    final hh = highs[highs.length - 1] > highs[highs.length - 2];
    final hl = lows[lows.length - 1] > lows[lows.length - 2];
    final lh = highs[highs.length - 1] < highs[highs.length - 2];
    final ll = lows[lows.length - 1] < lows[lows.length - 2];

    String label;
    if (hh && hl) {
      label = 'HH_HL';
    } else if (lh && ll) {
      label = 'LH_LL';
    } else if (hh && ll) {
      label = 'EXPANDING';
    } else {
      label = 'MIXED';
    }

    // Simple BOS / CHOCH from last close vs prior swing
    final last = candles.last.close;
    final priorHigh = highs[highs.length - 2];
    final priorLow = lows[lows.length - 2];
    String event = 'NONE';
    if (last > priorHigh && (lh || ll)) {
      event = 'BOS_UP';
    } else if (last < priorLow && (hh || hl)) {
      event = 'BOS_DOWN';
    } else if (last > priorHigh && label == 'LH_LL') {
      event = 'CHOCH_BULL';
    } else if (last < priorLow && label == 'HH_HL') {
      event = 'CHOCH_BEAR';
    }

    // Volatility regime via ATR vs price
    final atr = _atr(candles, 14);
    final atrPct = last > 0 ? (atr / last) * 100 : 0;
    final volRegime =
        atrPct >= 2.5 ? 'HIGH' : (atrPct >= 1.2 ? 'MEDIUM' : 'LOW');

    final support = lows.last;
    final resistance = highs.last;
    return StructureSnapshot(
      available: true,
      label: label,
      event: event,
      support: support,
      resistance: resistance,
      volatilityRegime: volRegime,
      note:
          'ساختار: $label $event | S=${support.toStringAsFixed(4)} R=${resistance.toStringAsFixed(4)} vol=$volRegime',
    );
  }

  /// Suggested trailing distance (analysis only — not placed on exchange).
  double? suggestedTrailDistance(List<Candle> candles) {
    final atr = _atr(candles, 14);
    if (atr <= 0) return null;
    return atr * 1.5;
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
    final struct = structure(candles);

    String bias;
    if (ema9 > ema21 && rsi >= 48 && rsi <= 72) {
      bias = 'BULLISH';
    } else if (ema9 < ema21 && rsi <= 52 && rsi >= 28) {
      bias = 'BEARISH';
    } else {
      bias = 'NEUTRAL';
    }

    if (struct.available) {
      if (struct.label == 'HH_HL' && bias != 'BEARISH') bias = 'BULLISH';
      if (struct.label == 'LH_LL' && bias != 'BULLISH') bias = 'BEARISH';
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
      structure: struct,
      note:
          '$label: $bias RSI=${rsi.toStringAsFixed(0)} ${struct.available ? struct.label : ''}',
    );
  }

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
        breakdown: const {},
      );
    }

    final isLong = signal.side.toUpperCase() == 'LONG';
    final breakdown = <String, double>{};
    final reasons = <String>[];
    final missing = <String>[];
    var total = 50.0;

    double mtf = 0;
    for (final s in available) {
      final w = switch (s.label) {
        '4h' => 6.0,
        '1h' => 5.0,
        '15m' => 4.0,
        '5m' => 3.0,
        _ => 3.0,
      };
      if (s.bias == 'BULLISH') {
        mtf += isLong ? w : -w * 0.8;
        reasons.add('${s.label}: صعودی');
      } else if (s.bias == 'BEARISH') {
        mtf += isLong ? -w * 0.8 : w;
        reasons.add('${s.label}: نزولی');
      } else {
        reasons.add('${s.label}: خنثی');
      }
      if (s.volumeRising) {
        breakdown['volume'] = (breakdown['volume'] ?? 0) + 2;
        reasons.add('${s.label}: حجم افزایشی');
      }
      if (s.structure.available) {
        final align =
            s.structure.label == (isLong ? 'HH_HL' : 'LH_LL') ? 4.0 : 0.0;
        breakdown['structure'] = (breakdown['structure'] ?? 0) + align;
        if (s.structure.event != 'NONE') {
          reasons.add('${s.label} ${s.structure.event}');
        }
        reasons.add(s.structure.note);
      }
    }
    breakdown['mtf'] = mtf;
    total += mtf;

    for (final s in snapshots.where((x) => !x.available)) {
      missing.add(s.label);
    }

    final higher =
        available.where((s) => s.label == '1h' || s.label == '4h').toList();
    final lower =
        available.where((s) => s.label == '5m' || s.label == '15m').toList();
    if (higher.isNotEmpty && lower.isNotEmpty) {
      final hb = higher.first.bias;
      final lb = lower.first.bias;
      if (hb != 'NEUTRAL' && lb != 'NEUTRAL' && hb != lb) {
        total -= 12;
        breakdown['conflict'] = -12;
        reasons.add('تضاد تایم‌فریم بالا/پایین → احتیاط');
      }
    }

    if (depth != null) {
      final bids = depth['bids'];
      final asks = depth['asks'];
      if (bids is List && asks is List && bids.isNotEmpty && asks.isNotEmpty) {
        double b = 0, a = 0;
        for (final row in bids.take(10)) {
          if (row is List && row.length >= 2) {
            b += double.tryParse('${row[1]}') ?? 0;
          }
        }
        for (final row in asks.take(10)) {
          if (row is List && row.length >= 2) {
            a += double.tryParse('${row[1]}') ?? 0;
          }
        }
        if (b + a > 0) {
          final imb = (b - a) / (b + a);
          final bookPts = isLong ? imb * 10 : -imb * 10;
          breakdown['orderbook'] = bookPts;
          total += bookPts;
          reasons.add('نبود تعادل اردربوک: ${(imb * 100).toStringAsFixed(1)}%');
        }
      } else {
        missing.add('orderbook');
      }
    } else {
      missing.add('orderbook');
    }

    if (signal.riskReward >= 2) {
      breakdown['rr'] = 8;
      total += 8;
      reasons.add('R/R مناسب 1:${signal.riskReward.toStringAsFixed(1)}');
    } else if (signal.riskReward < 1.2) {
      breakdown['rr'] = -10;
      total -= 10;
      reasons.add('R/R ضعیف');
    }

    total = total.clamp(0, 100);
    String direction;
    if (total >= 62) {
      direction = isLong ? 'LONG' : 'SHORT';
    } else {
      direction = 'WAIT';
    }
    if (total < 58) direction = 'WAIT';

    final atrPct = signal.entry > 0 ? (signal.atr / signal.entry) * 100 : 0;
    final risk =
        atrPct >= 2.5 ? 'HIGH' : (atrPct >= 1.2 ? 'MEDIUM' : 'CONTROLLED');

    return ScoredAnalysis(
      direction: direction,
      score: total,
      confidence: total.round(),
      riskLevel: risk,
      reasons: reasons,
      missing: missing,
      snapshots: snapshots,
      breakdown: breakdown,
    );
  }
}

class StructureSnapshot {
  final bool available;
  final String label;
  final String event;
  final double support;
  final double resistance;
  final String volatilityRegime;
  final String note;

  const StructureSnapshot({
    this.available = true,
    this.label = 'UNKNOWN',
    this.event = 'NONE',
    this.support = 0,
    this.resistance = 0,
    this.volatilityRegime = 'UNKNOWN',
    this.note = '',
  });
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
  final StructureSnapshot structure;
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
    this.structure = const StructureSnapshot(available: false),
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
  final Map<String, double> breakdown;

  const ScoredAnalysis({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.riskLevel,
    required this.reasons,
    required this.missing,
    required this.snapshots,
    this.breakdown = const {},
  });
}
