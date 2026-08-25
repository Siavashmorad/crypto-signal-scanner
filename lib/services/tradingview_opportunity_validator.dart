/// Re-validates a TradingView alert against live market price.
/// Does not invent indicators. Does not place orders.
class TradingViewRevalidation {
  final bool valid;
  final String reason;
  final double? currentPrice;
  final double? entryHint;
  final double priceDriftPct;

  const TradingViewRevalidation({
    required this.valid,
    required this.reason,
    this.currentPrice,
    this.entryHint,
    this.priceDriftPct = 0,
  });
}

class TradingViewOpportunityValidator {
  /// Max acceptable drift from alert price to current (percent). Configurable.
  TradingViewOpportunityValidator({this.maxDriftPct = 1.5});

  final double maxDriftPct;

  /// [alertPrice] from TV payload; [livePrice] from Tabdeal/trades.
  /// Missing live price → not valid for live trade.
  TradingViewRevalidation revalidate({
    required String side,
    double? alertPrice,
    double? livePrice,
    DateTime? alertTime,
    Duration maxAge = const Duration(minutes: 15),
  }) {
    final now = DateTime.now();
    if (alertTime != null && now.difference(alertTime) > maxAge) {
      return const TradingViewRevalidation(
        valid: false,
        reason: 'SIGNAL EXPIRED',
      );
    }
    if (livePrice == null || livePrice <= 0) {
      return const TradingViewRevalidation(
        valid: false,
        reason: 'DATA INSUFFICIENT',
      );
    }
    if (alertPrice == null || alertPrice <= 0) {
      return TradingViewRevalidation(
        valid: true,
        reason: 'NO ALERT PRICE — USE MARKET ENTRY',
        currentPrice: livePrice,
      );
    }
    final drift = ((livePrice - alertPrice).abs() / alertPrice) * 100.0;
    if (drift > maxDriftPct) {
      return TradingViewRevalidation(
        valid: false,
        reason: 'REJECT STALE SIGNAL',
        currentPrice: livePrice,
        entryHint: alertPrice,
        priceDriftPct: drift,
      );
    }
    final s = side.toUpperCase();
    if (s == 'LONG' && livePrice > alertPrice * (1 + maxDriftPct / 100)) {
      return TradingViewRevalidation(
        valid: false,
        reason: 'WAIT FOR BETTER ENTRY',
        currentPrice: livePrice,
        entryHint: alertPrice,
        priceDriftPct: drift,
      );
    }
    if (s == 'SHORT' && livePrice < alertPrice * (1 - maxDriftPct / 100)) {
      return TradingViewRevalidation(
        valid: false,
        reason: 'WAIT FOR BETTER ENTRY',
        currentPrice: livePrice,
        entryHint: alertPrice,
        priceDriftPct: drift,
      );
    }
    return TradingViewRevalidation(
      valid: true,
      reason: 'OK',
      currentPrice: livePrice,
      entryHint: alertPrice,
      priceDriftPct: drift,
    );
  }
}
