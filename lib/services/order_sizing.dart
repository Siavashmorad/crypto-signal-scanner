import 'dart:math' as math;

/// Exchange filters for one symbol (from Tabdeal exchangeInfo when available).
class SymbolFilters {
  final String symbol;
  final double minQty;
  final double maxQty;
  final double stepSize;
  final double minNotional;
  final double tickSize;
  final int qtyPrecision;
  final bool trading;

  const SymbolFilters({
    required this.symbol,
    this.minQty = 0.001,
    this.maxQty = 1e9,
    this.stepSize = 0.001,
    this.minNotional = 10,
    this.tickSize = 0.01,
    this.qtyPrecision = 6,
    this.trading = true,
  });

  /// Conservative defaults when exchangeInfo lacks filter fields.
  factory SymbolFilters.fallback(String symbol) {
    final s = symbol.toUpperCase().replaceAll('_', '');
    if (s.startsWith('BTC')) {
      return SymbolFilters(
        symbol: s,
        minQty: 0.0001,
        stepSize: 0.0001,
        minNotional: 10,
        qtyPrecision: 6,
      );
    }
    if (s.startsWith('ETH')) {
      return SymbolFilters(
        symbol: s,
        minQty: 0.001,
        stepSize: 0.001,
        minNotional: 10,
        qtyPrecision: 5,
      );
    }
    if (s.startsWith('BCH') || s.startsWith('LTC')) {
      return SymbolFilters(
        symbol: s,
        minQty: 0.01,
        stepSize: 0.01,
        minNotional: 10,
        qtyPrecision: 4,
      );
    }
    return SymbolFilters(symbol: s);
  }

  factory SymbolFilters.fromExchangeItem(Map item) {
    final symbol =
        '${item['symbol'] ?? item['tabdealSymbol'] ?? ''}'.toUpperCase().replaceAll('_', '');
    double minQty = 0.001, maxQty = 1e9, step = 0.001, minNotional = 10, tick = 0.01;
    int prec = 6;
    bool trading = true;

    final status = '${item['status'] ?? 'TRADING'}'.toUpperCase();
    if (status.isNotEmpty && status != 'TRADING' && status != 'ACTIVE') {
      trading = false;
    }

    final filters = item['filters'];
    if (filters is List) {
      for (final f in filters) {
        if (f is! Map) continue;
        final type = '${f['filterType'] ?? f['type'] ?? ''}'.toUpperCase();
        if (type.contains('LOT_SIZE') || type.contains('LOTSIZE')) {
          minQty = double.tryParse('${f['minQty'] ?? f['min_qty'] ?? minQty}') ?? minQty;
          maxQty = double.tryParse('${f['maxQty'] ?? f['max_qty'] ?? maxQty}') ?? maxQty;
          step = double.tryParse('${f['stepSize'] ?? f['step_size'] ?? step}') ?? step;
        }
        if (type.contains('NOTIONAL') || type.contains('MIN_NOTIONAL')) {
          minNotional = double.tryParse(
                  '${f['minNotional'] ?? f['notional'] ?? f['min_notional'] ?? minNotional}') ??
              minNotional;
        }
        if (type.contains('PRICE')) {
          tick = double.tryParse('${f['tickSize'] ?? f['tick_size'] ?? tick}') ?? tick;
        }
      }
    }

    // Tabdeal sometimes puts fields at top level
    minQty = double.tryParse('${item['minQty'] ?? item['min_qty'] ?? minQty}') ?? minQty;
    step = double.tryParse('${item['stepSize'] ?? item['step_size'] ?? step}') ?? step;
    minNotional =
        double.tryParse('${item['minNotional'] ?? item['min_notional'] ?? minNotional}') ??
            minNotional;
    prec = int.tryParse('${item['quantityPrecision'] ?? item['baseAssetPrecision'] ?? prec}') ??
        prec;

    if (minQty <= 0) minQty = 0.001;
    if (step <= 0) step = minQty;
    if (minNotional <= 0) minNotional = 10;

    return SymbolFilters(
      symbol: symbol,
      minQty: minQty,
      maxQty: maxQty,
      stepSize: step,
      minNotional: minNotional,
      tickSize: tick,
      qtyPrecision: prec,
      trading: trading,
    );
  }
}

enum OrderSizeStatus {
  ok,
  notTrading,
  insufficientBalance,
  exceedsMaxRisk,
  exceedsMaxQty,
  invalidPrice,
}

class OrderSizeResult {
  final OrderSizeStatus status;
  final double requestedQty;
  final double finalQty;
  final double minQty;
  final double minNotional;
  final double stepSize;
  final double approxNotional;
  final double price;
  final String message;
  final bool usedExchangeMin;

  const OrderSizeResult({
    required this.status,
    required this.requestedQty,
    required this.finalQty,
    required this.minQty,
    required this.minNotional,
    required this.stepSize,
    required this.approxNotional,
    required this.price,
    required this.message,
    this.usedExchangeMin = false,
  });

  bool get canSubmit => status == OrderSizeStatus.ok && finalQty > 0;
}

/// Computes exchange-compliant quantity without blindly inflating size.
class OrderSizingEngine {
  /// [maxRiskQuote] max quote currency (USDT/IRT) willing to risk on this order notional.
  /// [availableQuote] free balance in quote asset (0 = skip balance check).
  OrderSizeResult compute({
    required SymbolFilters filters,
    required double configuredQty,
    required double currentPrice,
    double availableQuote = 0,
    double maxRiskQuote = 0,
  }) {
    if (!filters.trading) {
      return OrderSizeResult(
        status: OrderSizeStatus.notTrading,
        requestedQty: configuredQty,
        finalQty: 0,
        minQty: filters.minQty,
        minNotional: filters.minNotional,
        stepSize: filters.stepSize,
        approxNotional: 0,
        price: currentPrice,
        message: 'بازار ${filters.symbol} فعال نیست.',
      );
    }
    if (currentPrice <= 0) {
      return OrderSizeResult(
        status: OrderSizeStatus.invalidPrice,
        requestedQty: configuredQty,
        finalQty: 0,
        minQty: filters.minQty,
        minNotional: filters.minNotional,
        stepSize: filters.stepSize,
        approxNotional: 0,
        price: currentPrice,
        message: 'قیمت معتبر برای ${filters.symbol} در دسترس نیست.',
      );
    }

    final fromNotional = filters.minNotional / currentPrice;
    var needed = math.max(configuredQty, math.max(filters.minQty, fromNotional));
    needed = _roundUpToStep(needed, filters.stepSize);
    needed = _clampPrecision(needed, filters.qtyPrecision);

    if (needed > filters.maxQty) {
      return OrderSizeResult(
        status: OrderSizeStatus.exceedsMaxQty,
        requestedQty: configuredQty,
        finalQty: 0,
        minQty: filters.minQty,
        minNotional: filters.minNotional,
        stepSize: filters.stepSize,
        approxNotional: needed * currentPrice,
        price: currentPrice,
        message: 'حجم لازم از حداکثر مجاز صرافی بیشتر است.',
        usedExchangeMin: needed > configuredQty,
      );
    }

    final notional = needed * currentPrice;

    if (maxRiskQuote > 0 && notional > maxRiskQuote) {
      return OrderSizeResult(
        status: OrderSizeStatus.exceedsMaxRisk,
        requestedQty: configuredQty,
        finalQty: 0,
        minQty: filters.minQty,
        minNotional: filters.minNotional,
        stepSize: filters.stepSize,
        approxNotional: notional,
        price: currentPrice,
        message:
            'حداقل سفارش (~${notional.toStringAsFixed(2)}) از سقف ریسک مجاز (~${maxRiskQuote.toStringAsFixed(2)}) بیشتر است. سفارش ارسال نمی‌شود.',
        usedExchangeMin: needed > configuredQty,
      );
    }

    if (availableQuote > 0 && notional > availableQuote) {
      return OrderSizeResult(
        status: OrderSizeStatus.insufficientBalance,
        requestedQty: configuredQty,
        finalQty: 0,
        minQty: filters.minQty,
        minNotional: filters.minNotional,
        stepSize: filters.stepSize,
        approxNotional: notional,
        price: currentPrice,
        message:
            'موجودی برای حداقل سفارش ${filters.symbol} کافی نیست (نیاز ~${notional.toStringAsFixed(2)}).',
        usedExchangeMin: needed > configuredQty,
      );
    }

    return OrderSizeResult(
      status: OrderSizeStatus.ok,
      requestedQty: configuredQty,
      finalQty: needed,
      minQty: filters.minQty,
      minNotional: filters.minNotional,
      stepSize: filters.stepSize,
      approxNotional: notional,
      price: currentPrice,
      message: needed > configuredQty
          ? 'حجم به حداقل مجاز صرافی افزایش یافت.'
          : 'حجم با محدودیت‌های صرافی سازگار است.',
      usedExchangeMin: needed > configuredQty,
    );
  }

  double _roundUpToStep(double qty, double step) {
    if (step <= 0) return qty;
    final n = (qty / step).ceilToDouble();
    return n * step;
  }

  double _clampPrecision(double qty, int precision) {
    final p = math.pow(10, precision).toDouble();
    return (qty * p).ceilToDouble() / p;
  }
}
