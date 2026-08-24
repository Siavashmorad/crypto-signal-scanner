import '../models/market_data.dart';
import 'data_health.dart';
import 'market_regime.dart';

enum FilterVerdict { pass, wait, noTrade }

class FilterResult {
  final FilterVerdict verdict;
  final List<String> reasons;
  final String code;

  const FilterResult({
    required this.verdict,
    required this.reasons,
    this.code = '',
  });

  bool get allowsLive => verdict == FilterVerdict.pass;
}

/// Hard filters — cannot be overridden by soft score alone.
class TradeFilterEngine {
  TradeFilterEngine({
    this.minRiskReward = 1.4,
    this.maxAtrPct = 4.0,
    this.maxSpreadBps = 40,
    this.minRelativeVolume = 0.5,
  });

  final double minRiskReward;
  final double maxAtrPct;
  final double maxSpreadBps;
  final double minRelativeVolume;

  FilterResult evaluate({
    required DataHealth dataHealth,
    required MarketRegime regime,
    required double riskReward,
    double? atrPct,
    double? spreadBps,
    double? relativeVolume,
    bool timeframeConflict = false,
    bool weakStructure = false,
    bool minOrderViolatesRisk = false,
    bool insufficientBalance = false,
    bool orderBookUnavailable = false,
  }) {
    final reasons = <String>[];

    if (dataHealth == DataHealth.stale || dataHealth == DataHealth.offline) {
      return FilterResult(
        verdict: FilterVerdict.noTrade,
        reasons: ['STALE/OFFLINE market data'],
        code: 'STALE_DATA',
      );
    }

    if (minOrderViolatesRisk) {
      return FilterResult(
        verdict: FilterVerdict.noTrade,
        reasons: ['MINIMUM ORDER RISK VIOLATION'],
        code: 'MIN_ORDER_RISK',
      );
    }

    if (insufficientBalance) {
      return FilterResult(
        verdict: FilterVerdict.noTrade,
        reasons: ['INSUFFICIENT BALANCE'],
        code: 'BALANCE',
      );
    }

    if (regime == MarketRegime.choppy) {
      reasons.add('CHOPPY regime → WAIT');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'CHOPPY',
      );
    }

    if (timeframeConflict) {
      reasons.add('TIMEFRAME CONFLICT');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'MTF_CONFLICT',
      );
    }

    if (riskReward < minRiskReward) {
      reasons.add('BAD R/R ${riskReward.toStringAsFixed(2)} < $minRiskReward');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'BAD_RR',
      );
    }

    if (atrPct != null && atrPct > maxAtrPct) {
      reasons.add('HIGH VOLATILITY ATR% ${atrPct.toStringAsFixed(2)}');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'HIGH_VOL',
      );
    }

    if (spreadBps != null && spreadBps > maxSpreadBps) {
      reasons.add('HIGH SPREAD ${spreadBps.toStringAsFixed(1)} bps');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'HIGH_SPREAD',
      );
    }

    if (relativeVolume != null && relativeVolume < minRelativeVolume) {
      reasons.add('WEAK VOLUME rel=${relativeVolume.toStringAsFixed(2)}');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'WEAK_VOLUME',
      );
    }

    if (weakStructure) {
      reasons.add('WEAK STRUCTURE');
      return FilterResult(
        verdict: FilterVerdict.wait,
        reasons: reasons,
        code: 'WEAK_STRUCTURE',
      );
    }

    if (orderBookUnavailable) {
      reasons.add('order book unavailable — confidence reduced (soft)');
    }

    if (dataHealth == DataHealth.degraded) {
      reasons.add('DEGRADED data — proceed only with high quality');
    }

    return FilterResult(
      verdict: FilterVerdict.pass,
      reasons: reasons.isEmpty ? ['filters passed'] : reasons,
      code: 'OK',
    );
  }

  /// Spread in basis points from best bid/ask if available.
  static double? spreadBpsFromDepth(Map<String, dynamic>? depth) {
    if (depth == null) return null;
    final bids = depth['bids'];
    final asks = depth['asks'];
    if (bids is! List || asks is! List || bids.isEmpty || asks.isEmpty) {
      return null;
    }
    final bid = double.tryParse('${(bids.first is List) ? bids.first[0] : ''}');
    final ask = double.tryParse('${(asks.first is List) ? asks.first[0] : ''}');
    if (bid == null || ask == null || bid <= 0) return null;
    return ((ask - bid) / bid) * 10000;
  }
}
