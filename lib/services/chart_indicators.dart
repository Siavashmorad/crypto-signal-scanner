import '../models/market_data.dart';

/// Pure helpers — computed only from real OHLCV, no synthetic prices.
class ChartIndicators {
  static List<double?> ema(List<Candle> candles, int period) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period || period < 1) return out;
    final closes = candles.map((c) => c.close).toList();
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += closes[i];
    }
    var prev = sum / period;
    out[period - 1] = prev;
    final k = 2 / (period + 1);
    for (var i = period; i < closes.length; i++) {
      prev = (closes[i] - prev) * k + prev;
      out[i] = prev;
    }
    return out;
  }

  static List<double?> emaSeries(List<double?> values, int period) {
    final out = List<double?>.filled(values.length, null);
    if (period < 1) return out;
    final k = 2 / (period + 1);
    double? prev;
    var seed = 0.0;
    var count = 0;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      if (prev == null) {
        seed += v;
        count++;
        if (count == period) {
          prev = seed / period;
          out[i] = prev;
        }
      } else {
        prev = (v - prev) * k + prev;
        out[i] = prev;
      }
    }
    return out;
  }

  static List<double?> sma(List<Candle> candles, int period) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    final closes = candles.map((c) => c.close).toList();
    var sum = 0.0;
    for (var i = 0; i < closes.length; i++) {
      sum += closes[i];
      if (i >= period) sum -= closes[i - period];
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  static List<double?> smaSeries(List<double> values, int period) {
    final out = List<double?>.filled(values.length, null);
    if (values.length < period) return out;
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      sum += values[i];
      if (i >= period) sum -= values[i - period];
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  static ({
    List<double?> macd,
    List<double?> signal,
    List<double?> hist,
  }) macd(
    List<Candle> candles, {
    int fast = 12,
    int slow = 26,
    int signalPeriod = 9,
  }) {
    final n = candles.length;
    final empty = (
      macd: List<double?>.filled(n, null),
      signal: List<double?>.filled(n, null),
      hist: List<double?>.filled(n, null),
    );
    if (n < slow + signalPeriod) return empty;

    final fastE = ema(candles, fast);
    final slowE = ema(candles, slow);
    final line = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final f = fastE[i];
      final s = slowE[i];
      if (f != null && s != null) line[i] = f - s;
    }
    final sig = emaSeries(line, signalPeriod);
    final hist = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final m = line[i];
      final g = sig[i];
      if (m != null && g != null) hist[i] = m - g;
    }
    return (macd: line, signal: sig, hist: hist);
  }

  static ({List<double?> mid, List<double?> upper, List<double?> lower}) bollinger(
    List<Candle> candles, {
    int period = 20,
    double mult = 2,
  }) {
    final mid = sma(candles, period);
    final upper = List<double?>.filled(candles.length, null);
    final lower = List<double?>.filled(candles.length, null);
    final closes = candles.map((c) => c.close).toList();
    for (var i = period - 1; i < closes.length; i++) {
      final m = mid[i];
      if (m == null) continue;
      var varSum = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        final d = closes[j] - m;
        varSum += d * d;
      }
      final s = _sqrt(varSum / period);
      upper[i] = m + mult * s;
      lower[i] = m - mult * s;
    }
    return (mid: mid, upper: upper, lower: lower);
  }

  /// Bollinger Band Width = (upper - lower) / mid
  static List<double?> bollingerWidth(List<Candle> candles, {int period = 20}) {
    final bb = bollinger(candles, period: period);
    final out = List<double?>.filled(candles.length, null);
    for (var i = 0; i < candles.length; i++) {
      final u = bb.upper[i], l = bb.lower[i], m = bb.mid[i];
      if (u == null || l == null || m == null || m == 0) continue;
      out[i] = (u - l) / m;
    }
    return out;
  }

  static List<double?> atr(List<Candle> candles, {int period = 14}) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (n < period + 1) return out;
    final trs = <double>[];
    for (var i = 1; i < n; i++) {
      final c = candles[i];
      final p = candles[i - 1];
      trs.add([
        c.high - c.low,
        (c.high - p.close).abs(),
        (c.low - p.close).abs(),
      ].reduce((a, b) => a > b ? a : b));
    }
    // Wilder-style smoothed ATR after seed SMA
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += trs[i];
    }
    var prev = sum / period;
    out[period] = prev; // index aligns with candle period
    for (var i = period; i < trs.length; i++) {
      prev = (prev * (period - 1) + trs[i]) / period;
      out[i + 1] = prev;
    }
    return out;
  }

  static double? lastAtr(List<Candle> candles, {int period = 14}) {
    final a = atr(candles, period: period);
    for (var i = a.length - 1; i >= 0; i--) {
      if (a[i] != null) return a[i];
    }
    return null;
  }

  /// ADX(14) with +DI/-DI. Returns last ADX or null.
  static ({double? adx, double? plusDi, double? minusDi}) adx(
    List<Candle> candles, {
    int period = 14,
  }) {
    final n = candles.length;
    if (n < period * 2 + 1) {
      return (adx: null, plusDi: null, minusDi: null);
    }
    final plusDM = <double>[];
    final minusDM = <double>[];
    final tr = <double>[];
    for (var i = 1; i < n; i++) {
      final up = candles[i].high - candles[i - 1].high;
      final down = candles[i - 1].low - candles[i].low;
      plusDM.add(up > down && up > 0 ? up : 0);
      minusDM.add(down > up && down > 0 ? down : 0);
      final c = candles[i];
      final p = candles[i - 1];
      tr.add([
        c.high - c.low,
        (c.high - p.close).abs(),
        (c.low - p.close).abs(),
      ].reduce((a, b) => a > b ? a : b));
    }

    double smooth(List<double> src) {
      var s = src.take(period).reduce((a, b) => a + b);
      for (var i = period; i < src.length; i++) {
        s = s - s / period + src[i];
      }
      return s;
    }

    final smoothTr = smooth(tr);
    final smoothPlus = smooth(plusDM);
    final smoothMinus = smooth(minusDM);
    if (smoothTr <= 0) return (adx: null, plusDi: null, minusDi: null);

    final plusDi = 100 * smoothPlus / smoothTr;
    final minusDi = 100 * smoothMinus / smoothTr;
    final diSum = plusDi + minusDi;
    final dx = diSum == 0 ? 0.0 : (100 * (plusDi - minusDi).abs() / diSum);

    // Approximate ADX as recent DX average (sufficient for regime)
    final dxList = <double>[];
    var sTr = tr.take(period).reduce((a, b) => a + b);
    var sP = plusDM.take(period).reduce((a, b) => a + b);
    var sM = minusDM.take(period).reduce((a, b) => a + b);
    for (var i = period; i < tr.length; i++) {
      sTr = sTr - sTr / period + tr[i];
      sP = sP - sP / period + plusDM[i];
      sM = sM - sM / period + minusDM[i];
      if (sTr <= 0) continue;
      final pDi = 100 * sP / sTr;
      final mDi = 100 * sM / sTr;
      final sum = pDi + mDi;
      dxList.add(sum == 0 ? 0 : 100 * (pDi - mDi).abs() / sum);
    }
    if (dxList.length < period) {
      return (adx: dx, plusDi: plusDi, minusDi: minusDi);
    }
    final adxVal =
        dxList.skip(dxList.length - period).reduce((a, b) => a + b) / period;
    return (adx: adxVal, plusDi: plusDi, minusDi: minusDi);
  }

  static List<double?> rsiSeries(List<Candle> candles, {int period = 14}) {
    final closes = candles.map((c) => c.close).toList();
    final out = List<double?>.filled(closes.length, null);
    if (closes.length <= period) return out;
    for (var i = period; i < closes.length; i++) {
      var gain = 0.0, loss = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        final d = closes[j] - closes[j - 1];
        if (d >= 0) {
          gain += d;
        } else {
          loss -= d;
        }
      }
      if (loss == 0) {
        out[i] = 100;
      } else {
        final rs = gain / loss;
        out[i] = 100 - (100 / (1 + rs));
      }
    }
    return out;
  }

  static double? lastRsi(List<Candle> candles, {int period = 14}) {
    final s = rsiSeries(candles, period: period);
    for (var i = s.length - 1; i >= 0; i--) {
      if (s[i] != null) return s[i];
    }
    return null;
  }

  /// Stochastic RSI: stoch of RSI values.
  static ({List<double?> k, List<double?> d}) stochRsi(
    List<Candle> candles, {
    int rsiPeriod = 14,
    int stochPeriod = 14,
    int smoothK = 3,
    int smoothD = 3,
  }) {
    final rsi = rsiSeries(candles, period: rsiPeriod);
    final n = candles.length;
    final raw = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      if (rsi[i] == null) continue;
      if (i < stochPeriod - 1) continue;
      double minR = double.infinity, maxR = -double.infinity;
      var ok = true;
      for (var j = i - stochPeriod + 1; j <= i; j++) {
        final v = rsi[j];
        if (v == null) {
          ok = false;
          break;
        }
        if (v < minR) minR = v;
        if (v > maxR) maxR = v;
      }
      if (!ok) continue;
      final range = maxR - minR;
      raw[i] = range == 0 ? 50 : 100 * (rsi[i]! - minR) / range;
    }
    final k = _smoothNullable(raw, smoothK);
    final d = _smoothNullable(k, smoothD);
    return (k: k, d: d);
  }

  static List<double?> _smoothNullable(List<double?> src, int period) {
    final out = List<double?>.filled(src.length, null);
    if (period <= 1) return List<double?>.from(src);
    for (var i = 0; i < src.length; i++) {
      if (i < period - 1) continue;
      var sum = 0.0;
      var cnt = 0;
      for (var j = i - period + 1; j <= i; j++) {
        final v = src[j];
        if (v == null) {
          cnt = -1;
          break;
        }
        sum += v;
        cnt++;
      }
      if (cnt > 0) out[i] = sum / cnt;
    }
    return out;
  }

  static List<double?> cci(List<Candle> candles, {int period = 20}) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    final tp = candles.map((c) => (c.high + c.low + c.close) / 3).toList();
    for (var i = period - 1; i < tp.length; i++) {
      var sum = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += tp[j];
      }
      final sma = sum / period;
      var mad = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        mad += (tp[j] - sma).abs();
      }
      mad /= period;
      out[i] = mad == 0 ? 0 : (tp[i] - sma) / (0.015 * mad);
    }
    return out;
  }

  static List<double?> roc(List<Candle> candles, {int period = 12}) {
    final out = List<double?>.filled(candles.length, null);
    final closes = candles.map((c) => c.close).toList();
    for (var i = period; i < closes.length; i++) {
      final prev = closes[i - period];
      if (prev == 0) continue;
      out[i] = ((closes[i] - prev) / prev) * 100;
    }
    return out;
  }

  static List<double?> williamsR(List<Candle> candles, {int period = 14}) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    for (var i = period - 1; i < candles.length; i++) {
      var hh = -double.infinity, ll = double.infinity;
      for (var j = i - period + 1; j <= i; j++) {
        if (candles[j].high > hh) hh = candles[j].high;
        if (candles[j].low < ll) ll = candles[j].low;
      }
      final range = hh - ll;
      out[i] = range == 0 ? -50 : -100 * (hh - candles[i].close) / range;
    }
    return out;
  }

  static List<double?> vwap(List<Candle> candles) {
    final out = List<double?>.filled(candles.length, null);
    var cumPv = 0.0;
    var cumV = 0.0;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final tp = (c.high + c.low + c.close) / 3;
      cumPv += tp * c.volume;
      cumV += c.volume;
      if (cumV > 0) out[i] = cumPv / cumV;
    }
    return out;
  }

  static List<double?> volumeSma(List<Candle> candles, {int period = 20}) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    var sum = 0.0;
    for (var i = 0; i < candles.length; i++) {
      sum += candles[i].volume;
      if (i >= period) sum -= candles[i - period].volume;
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  /// Relative volume = last volume / SMA(volume)
  static double? relativeVolume(List<Candle> candles, {int period = 20}) {
    if (candles.isEmpty) return null;
    final vs = volumeSma(candles, period: period);
    final last = vs.last;
    if (last == null || last <= 0) return null;
    return candles.last.volume / last;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var r = x / 2;
    for (var i = 0; i < 12; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}
