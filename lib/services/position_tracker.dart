import 'tabdeal_trade.dart';

enum TrackedOrderState {
  unknown,
  pending,
  partiallyFilled,
  filled,
  canceled,
  rejected,
  closed,
}

class TrackedOrder {
  final String symbol;
  final int? orderId;
  final String side;
  final double requestedQty;
  final double executedQty;
  final double avgPrice;
  final TrackedOrderState state;
  final String rawStatus;
  final Map<String, dynamic> raw;

  const TrackedOrder({
    required this.symbol,
    required this.orderId,
    required this.side,
    required this.requestedQty,
    required this.executedQty,
    required this.avgPrice,
    required this.state,
    required this.rawStatus,
    required this.raw,
  });

  bool get isOpen =>
      state == TrackedOrderState.pending ||
      state == TrackedOrderState.partiallyFilled ||
      state == TrackedOrderState.filled;

  factory TrackedOrder.fromApi(Map<String, dynamic> raw, {String? fallbackSymbol}) {
    final status = '${raw['status'] ?? ''}'.toUpperCase();
    TrackedOrderState st;
    switch (status) {
      case 'NEW':
      case 'PENDING':
        st = TrackedOrderState.pending;
        break;
      case 'PARTIALLY_FILLED':
        st = TrackedOrderState.partiallyFilled;
        break;
      case 'FILLED':
        st = TrackedOrderState.filled;
        break;
      case 'CANCELED':
      case 'CANCELLED':
        st = TrackedOrderState.canceled;
        break;
      case 'REJECTED':
      case 'EXPIRED':
        st = TrackedOrderState.rejected;
        break;
      default:
        st = TrackedOrderState.unknown;
    }

    final exec = double.tryParse('${raw['executedQty'] ?? raw['executed_qty'] ?? 0}') ?? 0;
    final orig = double.tryParse('${raw['origQty'] ?? raw['orig_qty'] ?? raw['quantity'] ?? 0}') ?? 0;
    final cumQuote =
        double.tryParse('${raw['cummulativeQuoteQty'] ?? raw['cumulativeQuoteQty'] ?? 0}') ?? 0;
    var avg = double.tryParse('${raw['avgPrice'] ?? raw['price'] ?? 0}') ?? 0;
    if ((avg <= 0 || avg.isNaN) && exec > 0 && cumQuote > 0) {
      avg = cumQuote / exec;
    }

    // Prefer fill price from fills array if present
    final fills = raw['fills'];
    if (fills is List && fills.isNotEmpty) {
      double q = 0, pq = 0;
      for (final f in fills) {
        if (f is! Map) continue;
        final fp = double.tryParse('${f['price'] ?? 0}') ?? 0;
        final fq = double.tryParse('${f['qty'] ?? f['quantity'] ?? 0}') ?? 0;
        if (fp > 0 && fq > 0) {
          pq += fp * fq;
          q += fq;
        }
      }
      if (q > 0) avg = pq / q;
    }

    final id = int.tryParse('${raw['orderId'] ?? raw['order_id'] ?? ''}');
    return TrackedOrder(
      symbol: '${raw['symbol'] ?? fallbackSymbol ?? ''}'.toUpperCase(),
      orderId: id,
      side: '${raw['side'] ?? ''}'.toUpperCase(),
      requestedQty: orig,
      executedQty: exec,
      avgPrice: avg,
      state: st,
      rawStatus: status.isEmpty ? 'UNKNOWN' : status,
      raw: raw,
    );
  }
}

class PositionTracker {
  PositionTracker(this.client);

  final TabdealTradeClient client;
  final Map<String, TrackedOrder> bySymbol = {};

  void rememberFill(String symbol, Map<String, dynamic> orderResponse) {
    bySymbol[symbol.toUpperCase()] =
        TrackedOrder.fromApi(orderResponse, fallbackSymbol: symbol);
  }

  Future<TrackedOrder?> refresh(String symbol, {int? orderId}) async {
    final sym = symbol.toUpperCase().replaceAll('_', '');
    final id = orderId ?? bySymbol[sym]?.orderId;
    if (id == null) return bySymbol[sym];
    try {
      final raw = await client.getOrder(symbol: sym, orderId: id);
      final t = TrackedOrder.fromApi(raw, fallbackSymbol: sym);
      bySymbol[sym] = t;
      return t;
    } catch (_) {
      return bySymbol[sym];
    }
  }
}
