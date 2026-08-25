/// Pure decision helpers for FCM / notification open path.
/// Never places orders. Never invents market data.
import 'fcm_opportunity_payload.dart';
import '../models/market_data.dart';
import 'tradingview_opportunity_validator.dart';

enum PushOpenDecision {
  /// Show stale / invalid UI — no order button.
  reject,
  /// Proceed to existing placeOnPhone with [liveSignal].
  proceed,
}

class PushOpenResult {
  final PushOpenDecision decision;
  final String reasonFa;
  final String reasonEn;
  final MarketSignal? liveSignal;

  const PushOpenResult.reject(this.reasonFa, this.reasonEn)
      : decision = PushOpenDecision.reject,
        liveSignal = null;

  const PushOpenResult.proceed(this.liveSignal,
      {this.reasonFa = '', this.reasonEn = ''})
      : decision = PushOpenDecision.proceed;
}

class PushOpenHandler {
  PushOpenHandler({TradingViewOpportunityValidator? validator})
      : _validator = validator ?? TradingViewOpportunityValidator();

  final TradingViewOpportunityValidator _validator;

  /// Evaluate push payload against optional live rescan.
  /// [live] must come from ScannerService.scanSymbol (real data) or null.
  PushOpenResult evaluate({
    required FcmOpportunityPayload payload,
    MarketSignal? live,
  }) {
    if (!payload.isOpportunity) {
      return const PushOpenResult.reject(
        'فرصت نامعتبر است',
        'Invalid opportunity payload',
      );
    }
    if (payload.isStale()) {
      return const PushOpenResult.reject(
        'فرصت دیگر معتبر نیست',
        'Opportunity is no longer valid (stale)',
      );
    }
    if (live == null) {
      return const PushOpenResult.reject(
        'فرصت دیگر معتبر نیست — داده زنده در دسترس نیست',
        'Opportunity invalid — live market data unavailable',
      );
    }
    if (live.side.toUpperCase() != payload.side.toUpperCase()) {
      return const PushOpenResult.reject(
        'فرصت دیگر معتبر نیست — جهت بازار تغییر کرده',
        'Opportunity invalid — market side changed',
      );
    }
    if (live.symbol.toUpperCase() != payload.symbol.toUpperCase()) {
      return const PushOpenResult.reject(
        'فرصت دیگر معتبر نیست',
        'Opportunity invalid — symbol mismatch',
      );
    }
    final reval = _validator.revalidate(
      side: payload.side,
      alertPrice: payload.entry,
      livePrice: live.entry,
      alertTime: payload.timestampMs != null
          ? DateTime.fromMillisecondsSinceEpoch(payload.timestampMs!)
          : null,
    );
    if (!reval.valid) {
      return PushOpenResult.reject(
        'فرصت دیگر معتبر نیست — ${reval.reason}',
        'Opportunity invalid — ${reval.reason}',
      );
    }
    // Prefer live Scanner levels; do not trust notification Entry/SL/TP.
    return PushOpenResult.proceed(live);
  }
}
