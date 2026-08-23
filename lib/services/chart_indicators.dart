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

  /// Bollinger: SMA ± 2 * std of closes.
  static ({List<double?> mid, List<double?> upper, List<double?> lower}) bollinger(
    List<Candle> candles, {
    int period = 20,
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
      final std = (varSum / period);
      final s = std > 0 ? (std).isNaN ? 0.0 : _sqrt(std) : 0.0;
      upper[i] = m + 2 * s;
      lower[i] = m - 2 * s;
    }
    return (mid: mid, upper: upper, lower: lower);
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var r = x / 2;
    for (var i = 0; i < 12; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

  /// Typical-price VWAP over available candles (session-less).
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

  static double? lastRsi(List<Candle> candles, {int period = 14}) {
    if (candles.length <= period) return null;
    final closes = candles.map((c) => c.close).toList();
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
}
