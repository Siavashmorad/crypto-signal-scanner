import '../models/market_data.dart';
import 'chart_indicators.dart';

enum MarketRegime {
  trendingBull,
  trendingBear,
  ranging,
  highVolatility,
  lowVolatility,
  breakout,
  breakdown,
  choppy,
  unknown,
}

extension MarketRegimeLabel on MarketRegime {
  String get label => switch (this) {
        MarketRegime.trendingBull => 'TRENDING BULL',
        MarketRegime.trendingBear => 'TRENDING BEAR',
        MarketRegime.ranging => 'RANGING',
        MarketRegime.highVolatility => 'HIGH VOLATILITY',
        MarketRegime.lowVolatility => 'LOW VOLATILITY',
        MarketRegime.breakout => 'BREAKOUT',
        MarketRegime.breakdown => 'BREAKDOWN',
        MarketRegime.choppy => 'CHOPPY',
        MarketRegime.unknown => 'UNKNOWN',
      };

  /// Preferred strategy style for this regime.
  String get strategy => switch (this) {
        MarketRegime.trendingBull || MarketRegime.trendingBear => 'TREND_FOLLOW',
        MarketRegime.ranging || MarketRegime.lowVolatility => 'MEAN_REVERSION',
        MarketRegime.breakout || MarketRegime.breakdown => 'BREAKOUT',
        MarketRegime.highVolatility => 'STRICT_FILTERS',
        MarketRegime.choppy => 'WAIT',
        MarketRegime.unknown => 'WAIT',
      };
}

class RegimeSnapshot {
  final MarketRegime regime;
  final double? adx;
  final double? atrPct;
  final double? bbWidth;
  final double? emaSlope;
  final String note;
  final bool available;

  const RegimeSnapshot({
    required this.regime,
    this.adx,
    this.atrPct,
    this.bbWidth,
    this.emaSlope,
    this.note = '',
    this.available = true,
  });

  factory RegimeSnapshot.unavailable(String why) => RegimeSnapshot(
        regime: MarketRegime.unknown,
        note: why,
        available: false,
      );
}

/// Deterministic regime from real OHLCV features only.
class MarketRegimeDetector {
  RegimeSnapshot detect(List<Candle> candles) {
    if (candles.length < 40) {
      return RegimeSnapshot.unavailable('داده کافی برای regime نیست');
    }

    final adxPack = ChartIndicators.adx(candles);
    final atr = ChartIndicators.lastAtr(candles);
    final last = candles.last.close;
    final atrPct = (atr != null && last > 0) ? (atr / last) * 100 : null;

    final bbw = ChartIndicators.bollingerWidth(candles);
    double? width;
    for (var i = bbw.length - 1; i >= 0; i--) {
      if (bbw[i] != null) {
        width = bbw[i];
        break;
      }
    }

    final ema20 = ChartIndicators.ema(candles, 20);
    final ema50 = ChartIndicators.ema(candles, 50);
    double? slope;
    final e20 = ema20.lastWhere((e) => e != null, orElse: () => null);
    final e50 = ema50.lastWhere((e) => e != null, orElse: () => null);
    if (e20 != null && e50 != null && e50 != 0) {
      slope = (e20 - e50) / e50 * 100;
    }

    // Structure quick check
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

    final adx = adxPack.adx;
    final plus = adxPack.plusDi;
    final minus = adxPack.minusDi;

    MarketRegime regime = MarketRegime.unknown;
    final notes = <String>[];

    if (atrPct != null && atrPct >= 3.0) {
      regime = MarketRegime.highVolatility;
      notes.add('ATR% بالا');
    } else if (adx != null && adx < 18 && (width == null || width < 0.04)) {
      regime = MarketRegime.choppy;
      notes.add('ADX پایین + BB باریک');
    } else if (adx != null && adx >= 25 && slope != null) {
      if (slope > 0.15 && (plus == null || minus == null || plus >= minus)) {
        regime = MarketRegime.trendingBull;
        notes.add('ADX روند + شیب EMA صعودی');
      } else if (slope < -0.15 &&
          (plus == null || minus == null || minus >= plus)) {
        regime = MarketRegime.trendingBear;
        notes.add('ADX روند + شیب EMA نزولی');
      }
    }

    // Breakout / breakdown vs recent swing
    if (highs.length >= 2 && lows.length >= 2) {
      final priorHigh = highs[highs.length - 2];
      final priorLow = lows[lows.length - 2];
      final relVol = ChartIndicators.relativeVolume(candles) ?? 1;
      if (last > priorHigh && relVol >= 1.3) {
        regime = MarketRegime.breakout;
        notes.add('شکست سقف + حجم');
      } else if (last < priorLow && relVol >= 1.3) {
        regime = MarketRegime.breakdown;
        notes.add('شکست کف + حجم');
      }
    }

    if (regime == MarketRegime.unknown) {
      if (adx != null && adx < 22) {
        regime = MarketRegime.ranging;
        notes.add('بازه / بدون روند قوی');
      } else if (atrPct != null && atrPct < 0.8) {
        regime = MarketRegime.lowVolatility;
        notes.add('نوسان پایین');
      } else {
        regime = MarketRegime.choppy;
        notes.add('شرایط مبهم → CHOPPY');
      }
    }

    return RegimeSnapshot(
      regime: regime,
      adx: adx,
      atrPct: atrPct,
      bbWidth: width,
      emaSlope: slope,
      note: notes.join(' · '),
    );
  }
}
