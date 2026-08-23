import 'dart:math' as math;

import 'account_balance.dart';

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
  invalidStop,
  noTrade,
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
  final double riskAmount;
  final double riskPercent;
  final double availableQuote;
  final double stopDistance;

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
    this.riskAmount = 0,
    this.riskPercent = 0,
    this.availableQuote = 0,
    this.stopDistance = 0,
  });

  bool get canSubmit => status == OrderSizeStatus.ok && finalQty > 0;
}

/// Risk-based position size + exchange rules. Never inflates risk to meet min order.
class OrderSizingEngine {
  /// [riskPercent] e.g. 0.01 = 1% of available quote.
  /// [entry] and [stopLoss] for risk distance; if stopDistance invalid → NO TRADE.
  OrderSizeResult compute({
    required SymbolFilters filters,
    required double configuredQty,
    required double currentPrice,
    double availableQuote = 0,
    double maxRiskQuote = 0,
    double riskPercent = 0.01,
    double? entry,
    double? stopLoss,
    bool isBuy = true,
  }) {
    if (!filters.trading) {
      return _fail(
        OrderSizeStatus.notTrading,
        configuredQty,
        filters,
        currentPrice,
        'بازار ${filters.symbol} فعال نیست.',
        availableQuote: availableQuote,
      );
    }
    if (currentPrice <= 0) {
      return _fail(
        OrderSizeStatus.invalidPrice,
        configuredQty,
        filters,
        currentPrice,
        'قیمت معتبر برای ${filters.symbol} در دسترس نیست.',
        availableQuote: availableQuote,
      );
    }

    final e = entry ?? currentPrice;
    final sl = stopLoss;
    double stopDist = 0;
    if (sl != null && sl > 0) {
      stopDist = (e - sl).abs();
    }

    // Risk-based size when we have balance + stop
    double riskBasedQty = configuredQty;
    double riskAmount = 0;
    if (availableQuote > 0 && riskPercent > 0 && stopDist > 0) {
      riskAmount = availableQuote * riskPercent;
      riskBasedQty = riskAmount / stopDist;
    } else if (availableQuote > 0 && maxRiskQuote > 0) {
      riskAmount = maxRiskQuote;
      riskBasedQty = maxRiskQuote / currentPrice;
    }

    // Prefer max(configured, riskBased) then apply exchange mins — but re-check risk
    var target = math.max(configuredQty, riskBasedQty);

    final fromNotional = filters.minNotional / currentPrice;
    final exchangeMin = math.max(filters.minQty, fromNotional);

    // If exchange min > risk-based target and that would exceed risk → NO TRADE
    if (stopDist > 0 && riskAmount > 0) {
      final minRiskIfExchange = exchangeMin * stopDist;
      if (exchangeMin > target && minRiskIfExchange > riskAmount * 1.05) {
        return OrderSizeResult(
          status: OrderSizeStatus.noTrade,
          requestedQty: configuredQty,
          finalQty: 0,
          minQty: filters.minQty,
          minNotional: filters.minNotional,
          stepSize: filters.stepSize,
          approxNotional: exchangeMin * currentPrice,
          price: currentPrice,
          message:
              'حداقل سفارش صرافی ریسک را بیش از حد مجاز می‌کند (ریسک مجاز ~${riskAmount.toStringAsFixed(2)}، ریسک حداقل سفارش ~${minRiskIfExchange.toStringAsFixed(2)}). NO TRADE',
          riskAmount: riskAmount,
          riskPercent: riskPercent * 100,
          availableQuote: availableQuote,
          stopDistance: stopDist,
        );
      }
    }

    var needed = math.max(target, exchangeMin);
    needed = _roundUpToStep(needed, filters.stepSize);
    needed = _clampPrecision(needed, filters.qtyPrecision);

    if (needed > filters.maxQty) {
      return _fail(
        OrderSizeStatus.exceedsMaxQty,
        configuredQty,
        filters,
        currentPrice,
        'حجم لازم از حداکثر مجاز صرافی بیشتر است.',
        availableQuote: availableQuote,
        riskAmount: riskAmount,
        riskPercent: riskPercent * 100,
        stopDist: stopDist,
      );
    }

    final notional = needed * currentPrice;

    // Re-check risk after rounding to exchange min
    if (stopDist > 0 && riskAmount > 0) {
      final actualRisk = needed * stopDist;
      if (actualRisk > riskAmount * 1.15) {
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
              'پس از رعایت حداقل صرافی، ریسک واقعی (~${actualRisk.toStringAsFixed(2)}) از حد مجاز (~${riskAmount.toStringAsFixed(2)}) بیشتر است. NO TRADE',
          usedExchangeMin: needed > target,
          riskAmount: riskAmount,
          riskPercent: riskPercent * 100,
          availableQuote: availableQuote,
          stopDistance: stopDist,
        );
      }
    }

    if (maxRiskQuote > 0 && notional > maxRiskQuote && stopDist <= 0) {
      return _fail(
        OrderSizeStatus.exceedsMaxRisk,
        configuredQty,
        filters,
        currentPrice,
        'ارزش سفارش از سقف مجاز بیشتر است.',
        availableQuote: availableQuote,
        notional: notional,
      );
    }

    if (availableQuote > 0 && isBuy && notional > availableQuote) {
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
            'موجودی ${AccountSnapshot.quoteAsset(filters.symbol)} کافی نیست (آزاد: ${availableQuote.toStringAsFixed(4)}، نیاز ~${notional.toStringAsFixed(4)}).',
        usedExchangeMin: needed > configuredQty,
        riskAmount: riskAmount,
        riskPercent: riskPercent * 100,
        availableQuote: availableQuote,
        stopDistance: stopDist,
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
          ? 'حجم بر اساس ریسک/حداقل صرافی تنظیم شد.'
          : 'حجم با ریسک و قوانین صرافی سازگار است.',
      usedExchangeMin: needed > configuredQty,
      riskAmount: riskAmount > 0 ? riskAmount : (stopDist > 0 ? needed * stopDist : 0),
      riskPercent: riskPercent * 100,
      availableQuote: availableQuote,
      stopDistance: stopDist,
    );
  }

  OrderSizeResult _fail(
    OrderSizeStatus status,
    double configured,
    SymbolFilters filters,
    double price,
    String msg, {
    double availableQuote = 0,
    double riskAmount = 0,
    double riskPercent = 0,
    double stopDist = 0,
    double notional = 0,
  }) {
    return OrderSizeResult(
      status: status,
      requestedQty: configured,
      finalQty: 0,
      minQty: filters.minQty,
      minNotional: filters.minNotional,
      stepSize: filters.stepSize,
      approxNotional: notional,
      price: price,
      message: msg,
      availableQuote: availableQuote,
      riskAmount: riskAmount,
      riskPercent: riskPercent,
      stopDistance: stopDist,
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
