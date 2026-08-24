import '../models/market_data.dart';
import 'chart_indicators.dart';
import 'data_health.dart';
import 'market_analysis_engine.dart';
import 'market_regime.dart';
import 'trade_filter_engine.dart';

export 'market_regime.dart' show MarketRegime, MarketRegimeLabel, MarketRegimeDetector, RegimeSnapshot;
export 'trade_filter_engine.dart' show FilterVerdict, FilterResult, TradeFilterEngine;

enum TradeQuality { aPlus, a, b, c, noTrade }

extension TradeQualityLabel on TradeQuality {
  String get label => switch (this) {
        TradeQuality.aPlus => 'A+',
        TradeQuality.a => 'A',
        TradeQuality.b => 'B',
        TradeQuality.c => 'C',
        TradeQuality.noTrade => 'NO TRADE',
      };

  bool get allowsLive => this == TradeQuality.aPlus || this == TradeQuality.a;
  bool get allowsPaper =>
      this == TradeQuality.aPlus ||
      this == TradeQuality.a ||
      this == TradeQuality.b;
}

class QuantWeights {
  final double trend;
  final double structure;
  final double momentum;
  final double volume;
  final double mtf;
  final double orderFlow;
  final double sr;
  final double regime;
  final double riskReward;

  const QuantWeights({
    this.trend = 15,
    this.structure = 15,
    this.momentum = 10,
    this.volume = 10,
    this.mtf = 15,
    this.orderFlow = 10,
    this.sr = 10,
    this.regime = 5,
    this.riskReward = 10,
  });

  double get total =>
      trend +
      structure +
      momentum +
      volume +
      mtf +
      orderFlow +
      sr +
      regime +
      riskReward;
}

class QuantDecision {
  final String direction;
  final double score;
  final int confidence;
  final TradeQuality quality;
  final MarketRegime regime;
  final String regimeStrategy;
  final Map<String, double> breakdown;
  final List<String> reasons;
  final List<String> missing;
  final List<String> hardFilterReasons;
  final FilterVerdict filterVerdict;
  final double? entryLow;
  final double? entryHigh;
  final double? suggestedSl;
  final double? suggestedTp1;
  final double? suggestedTp2;
  final double? suggestedTp3;
  final double riskReward;
  final String invalidation;
  final ScoredAnalysis? baseAnalysis;

  const QuantDecision({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.quality,
    required this.regime,
    required this.regimeStrategy,
    required this.breakdown,
    required this.reasons,
    required this.missing,
    required this.hardFilterReasons,
    required this.filterVerdict,
    this.entryLow,
    this.entryHigh,
    this.suggestedSl,
    this.suggestedTp1,
    this.suggestedTp2,
    this.suggestedTp3,
    this.riskReward = 0,
    this.invalidation = '',
    this.baseAnalysis,
  });
}

/// Multi-layer quant engine on top of existing MarketAnalysisEngine.
class QuantSignalEngine {
  QuantSignalEngine({
    MarketAnalysisEngine? analysis,
    MarketRegimeDetector? regimeDetector,
    TradeFilterEngine? filters,
    this.weights = const QuantWeights(),
    this.minScoreLive = 72,
    this.minScorePaper = 58,
  })  : analysis = analysis ?? MarketAnalysisEngine(),
        regimeDetector = regimeDetector ?? MarketRegimeDetector(),
        filters = filters ?? TradeFilterEngine();

  final MarketAnalysisEngine analysis;
  final MarketRegimeDetector regimeDetector;
  final TradeFilterEngine filters;
  final QuantWeights weights;
  final double minScoreLive;
  final double minScorePaper;

  QuantDecision evaluate({
    required MarketSignal signal,
    required Map<String, List<Candle>> candlesByTf,
    Map<String, dynamic>? depth,
    DataHealth dataHealth = DataHealth.live,
    bool minOrderViolatesRisk = false,
    bool insufficientBalance = false,
  }) {
    final primary = candlesByTf['1h'] ??
        candlesByTf['15m'] ??
        (candlesByTf.isNotEmpty ? candlesByTf.values.first : <Candle>[]);

    final regimeSnap = primary.isEmpty
        ? RegimeSnapshot.unavailable('no candles')
        : regimeDetector.detect(primary);

    final base = analysis.score(
      signal: signal,
      candlesByTf: candlesByTf,
      depth: depth,
    );

    final isLong = signal.side.toUpperCase() == 'LONG' ||
        signal.side.toUpperCase() == 'BUY';
    final breakdown = <String, double>{};
    final reasons = <String>[...base.reasons];
    final missing = <String>[...base.missing];

    double trendPts = 0;
    if (primary.length >= 50) {
      final e20 = ChartIndicators.ema(primary, 20)
          .lastWhere((e) => e != null, orElse: () => null);
      final e50 = ChartIndicators.ema(primary, 50)
          .lastWhere((e) => e != null, orElse: () => null);
      final e200 = ChartIndicators.ema(primary, 200)
          .lastWhere((e) => e != null, orElse: () => null);
      if (e20 != null && e50 != null) {
        final alignLong = e20 > e50 && (e200 == null || e50 > e200);
        final alignShort = e20 < e50 && (e200 == null || e50 < e200);
        if (isLong && alignLong) {
          trendPts = weights.trend;
          reasons.add('EMA alignment bullish');
        } else if (!isLong && alignShort) {
          trendPts = weights.trend;
          reasons.add('EMA alignment bearish');
        } else if ((isLong && e20 > e50) || (!isLong && e20 < e50)) {
          trendPts = weights.trend * 0.5;
        }
      } else {
        missing.add('ema');
      }
    } else {
      missing.add('trend_data');
    }
    breakdown['trend'] = trendPts;

    double structPts = 0;
    final structOk = base.snapshots.any((s) =>
        s.available &&
        s.structure.available &&
        ((isLong && s.structure.label == 'HH_HL') ||
            (!isLong && s.structure.label == 'LH_LL')));
    if (structOk) {
      structPts = weights.structure;
      reasons.add('structure aligned');
    } else if (base.snapshots.any((s) => s.structure.available)) {
      structPts = weights.structure * 0.3;
    } else {
      missing.add('structure');
    }
    breakdown['structure'] = structPts;

    double momPts = 0;
    final rsi = ChartIndicators.lastRsi(primary);
    final macd = ChartIndicators.macd(primary);
    final stoch = ChartIndicators.stochRsi(primary);
    final lastMacd = macd.hist.lastWhere((e) => e != null, orElse: () => null);
    final lastK = stoch.k.lastWhere((e) => e != null, orElse: () => null);
    if (rsi != null) {
      if (isLong && rsi >= 45 && rsi <= 68) {
        momPts += weights.momentum * 0.4;
      } else if (!isLong && rsi <= 55 && rsi >= 32) {
        momPts += weights.momentum * 0.4;
      }
    } else {
      missing.add('rsi');
    }
    if (lastMacd != null) {
      if ((isLong && lastMacd > 0) || (!isLong && lastMacd < 0)) {
        momPts += weights.momentum * 0.35;
      }
    }
    if (lastK != null) {
      if ((isLong && lastK > 20 && lastK < 80) ||
          (!isLong && lastK < 80 && lastK > 20)) {
        momPts += weights.momentum * 0.25;
      }
    }
    breakdown['momentum'] = momPts.clamp(0, weights.momentum);

    double volPts = 0;
    final relVol = ChartIndicators.relativeVolume(primary);
    if (relVol != null) {
      if (relVol >= 1.2) {
        volPts = weights.volume;
        reasons.add('volume confirmation ${relVol.toStringAsFixed(2)}x');
      } else if (relVol >= 0.8) {
        volPts = weights.volume * 0.5;
      } else {
        reasons.add('weak relative volume');
      }
    } else {
      missing.add('volume');
    }
    breakdown['volume'] = volPts;

    final mtfRaw = (base.breakdown['mtf'] ?? 0).clamp(-20.0, 20.0);
    breakdown['mtf'] = ((mtfRaw + 20) / 40) * weights.mtf;

    double ofPts = 0;
    final spreadBps = TradeFilterEngine.spreadBpsFromDepth(depth);
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
          if ((isLong && imb > 0.05) || (!isLong && imb < -0.05)) {
            ofPts = weights.orderFlow;
            reasons.add(
                'order flow ${isLong ? 'BUY' : 'SELL'} pressure ${(imb * 100).toStringAsFixed(0)}%');
          } else {
            ofPts = weights.orderFlow * 0.3;
          }
        }
      } else {
        missing.add('orderbook');
      }
    } else {
      missing.add('orderbook');
    }
    breakdown['orderFlow'] = ofPts;

    double srPts = 0;
    final atr = ChartIndicators.lastAtr(primary) ?? signal.atr;
    if (primary.length >= 20 && atr > 0) {
      final res = primary.map((c) => c.high).reduce((a, b) => a > b ? a : b);
      final sup = primary.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      final px = primary.last.close;
      if (isLong && (px - sup).abs() <= atr * 1.5) {
        srPts = weights.sr;
        reasons.add('near support zone');
      } else if (!isLong && (res - px).abs() <= atr * 1.5) {
        srPts = weights.sr;
        reasons.add('near resistance zone');
      } else {
        srPts = weights.sr * 0.3;
      }
    } else {
      missing.add('sr');
    }
    breakdown['sr'] = srPts;

    double regimePts = 0;
    final reg = regimeSnap.regime;
    if (reg == MarketRegime.trendingBull && isLong) {
      regimePts = weights.regime;
    } else if (reg == MarketRegime.trendingBear && !isLong) {
      regimePts = weights.regime;
    } else if (reg == MarketRegime.breakout && isLong) {
      regimePts = weights.regime * 0.8;
    } else if (reg == MarketRegime.breakdown && !isLong) {
      regimePts = weights.regime * 0.8;
    } else if (reg != MarketRegime.choppy) {
      regimePts = weights.regime * 0.3;
    }
    breakdown['regime'] = regimePts;
    reasons.add('regime ${reg.label}: ${regimeSnap.note}');

    final rr = signal.riskReward;
    double rrPts = 0;
    if (rr >= 2.5) {
      rrPts = weights.riskReward;
    } else if (rr >= 1.8) {
      rrPts = weights.riskReward * 0.7;
    } else if (rr >= 1.4) {
      rrPts = weights.riskReward * 0.4;
    }
    breakdown['rr'] = rrPts;

    var score = breakdown.values.fold<double>(0, (a, b) => a + b);
    final maxW = weights.total <= 0 ? 100.0 : weights.total;
    score = (score / maxW * 100).clamp(0, 100);

    final higher = base.snapshots
        .where((s) => s.available && (s.label == '1h' || s.label == '4h'))
        .toList();
    final lower = base.snapshots
        .where((s) => s.available && (s.label == '5m' || s.label == '15m'))
        .toList();
    var conflict = false;
    if (higher.isNotEmpty && lower.isNotEmpty) {
      final hb = higher.first.bias;
      final lb = lower.first.bias;
      if (hb != 'NEUTRAL' && lb != 'NEUTRAL' && hb != lb) conflict = true;
    }

    final atrPct = regimeSnap.atrPct ??
        (signal.entry > 0 ? (signal.atr / signal.entry) * 100 : null);

    final filter = filters.evaluate(
      dataHealth: dataHealth,
      regime: reg,
      riskReward: rr,
      atrPct: atrPct,
      spreadBps: spreadBps,
      relativeVolume: relVol,
      timeframeConflict: conflict,
      weakStructure: !structOk && score < 70,
      minOrderViolatesRisk: minOrderViolatesRisk,
      insufficientBalance: insufficientBalance,
      orderBookUnavailable: depth == null,
    );

    final px = primary.isNotEmpty ? primary.last.close : signal.entry;
    final zonePad = (atr > 0 ? atr * 0.35 : px * 0.002);
    final entryLow = isLong ? px - zonePad : px - zonePad * 0.5;
    final entryHigh = isLong ? px + zonePad * 0.5 : px + zonePad;

    double? sugSl, tp1, tp2, tp3;
    if (atr > 0) {
      if (isLong) {
        sugSl = px - atr * 1.4;
        tp1 = px + atr * 1.4;
        tp2 = px + atr * 2.5;
        tp3 = px + atr * 3.5;
      } else {
        sugSl = px + atr * 1.4;
        tp1 = px - atr * 1.4;
        tp2 = px - atr * 2.5;
        tp3 = px - atr * 3.5;
      }
    }

    String direction = isLong ? 'LONG' : 'SHORT';
    if (score < minScorePaper) direction = 'WAIT';
    if (filter.verdict == FilterVerdict.wait) direction = 'WAIT';
    if (filter.verdict == FilterVerdict.noTrade) direction = 'WAIT';
    if (reg == MarketRegime.choppy) direction = 'WAIT';

    TradeQuality quality;
    if (filter.verdict == FilterVerdict.noTrade || score < 45) {
      quality = TradeQuality.noTrade;
      direction = 'WAIT';
    } else if (direction == 'WAIT' || score < minScorePaper) {
      quality = TradeQuality.c;
    } else if (score >= 85 &&
        filter.verdict == FilterVerdict.pass &&
        !conflict) {
      quality = TradeQuality.aPlus;
    } else if (score >= minScoreLive && filter.verdict == FilterVerdict.pass) {
      quality = TradeQuality.a;
    } else if (score >= minScorePaper) {
      quality = TradeQuality.b;
    } else {
      quality = TradeQuality.c;
    }

    var conf = score;
    if (filter.verdict != FilterVerdict.pass) conf *= 0.7;
    if (conflict) conf *= 0.85;
    if (dataHealth == DataHealth.degraded) conf *= 0.9;
    conf = conf.clamp(0, 100);

    return QuantDecision(
      direction: direction,
      score: score,
      confidence: conf.round(),
      quality: quality,
      regime: reg,
      regimeStrategy: reg.strategy,
      breakdown: breakdown,
      reasons: reasons.take(16).toList(),
      missing: missing,
      hardFilterReasons: filter.reasons,
      filterVerdict: filter.verdict,
      entryLow: entryLow,
      entryHigh: entryHigh,
      suggestedSl: sugSl ?? signal.stopLoss,
      suggestedTp1: tp1 ?? signal.tp1,
      suggestedTp2: tp2 ?? signal.tp2,
      suggestedTp3: tp3 ?? signal.tp3,
      riskReward: rr,
      invalidation: isLong
          ? 'Invalid if close below structure/SL zone'
          : 'Invalid if close above structure/SL zone',
      baseAnalysis: base,
    );
  }
}
