import 'order_sizing.dart';

class FuturesSizeResult {
  final bool allow;
  final double quantity;
  final double requiredMargin;
  final double riskAmount;
  final double leverage;
  final double notional;
  final String reason;

  const FuturesSizeResult({
    required this.allow,
    required this.quantity,
    required this.requiredMargin,
    required this.riskAmount,
    required this.leverage,
    required this.notional,
    required this.reason,
  });

  factory FuturesSizeResult.noTrade(String reason) => FuturesSizeResult(
        allow: false,
        quantity: 0,
        requiredMargin: 0,
        riskAmount: 0,
        leverage: 1,
        notional: 0,
        reason: reason,
      );
}

/// Futures risk sizing. Never increases risk to satisfy exchange minimum.
class FuturesSizingEngine {
  const FuturesSizingEngine();

  FuturesSizeResult size({
    required double equity,
    required double availableBalance,
    required double riskPercent,
    required double entry,
    required double stopLoss,
    required double leverage,
    required SymbolFilters filters,
    double feeBufferPct = 0.001,
  }) {
    if (equity <= 0 || availableBalance <= 0) {
      return FuturesSizeResult.noTrade('موجودی Futures کافی نیست');
    }
    if (entry <= 0 || stopLoss <= 0 || leverage < 1) {
      return FuturesSizeResult.noTrade('پارامتر نامعتبر');
    }
    if (!filters.trading) {
      return FuturesSizeResult.noTrade('نماد قابل معامله نیست');
    }

    final stopDistance = (entry - stopLoss).abs();
    if (stopDistance <= 0 || stopDistance / entry < 1e-6) {
      return FuturesSizeResult.noTrade('فاصله حد ضرر خیلی کوچک');
    }

    final riskAmount = equity * (riskPercent / 100.0);
    if (riskAmount <= 0) {
      return FuturesSizeResult.noTrade('مبلغ ریسک صفر');
    }

    var qty = riskAmount / stopDistance;
    var notional = qty * entry;
    var margin = notional / leverage * (1 + feeBufferPct);

    if (margin > availableBalance) {
      final scale = availableBalance / margin;
      qty *= scale;
      notional = qty * entry;
      margin = notional / leverage * (1 + feeBufferPct);
    }

    if (filters.stepSize > 0) {
      qty = (qty / filters.stepSize).floorToDouble() * filters.stepSize;
    }

    if (qty < filters.minQty) {
      final minRisk = filters.minQty * stopDistance;
      final minMargin =
          filters.minQty * entry / leverage * (1 + feeBufferPct);
      if (minRisk > riskAmount * 1.01 || minMargin > availableBalance) {
        return FuturesSizeResult.noTrade(
            'حداقل سفارش صرافی ریسک را بیش از حد مجاز می‌کند — NO TRADE');
      }
      qty = filters.minQty;
      notional = qty * entry;
      margin = notional / leverage * (1 + feeBufferPct);
    }

    if (filters.minNotional > 0 && qty * entry < filters.minNotional) {
      return FuturesSizeResult.noTrade(
          'حجم کمتر از حداقل ارزش صرافی — NO TRADE');
    }

    final actualRisk = qty * stopDistance;
    if (actualRisk > riskAmount * 1.05) {
      return FuturesSizeResult.noTrade('ریسک واقعی از حد مجاز بیشتر — NO TRADE');
    }
    if (margin > availableBalance * 1.001) {
      return FuturesSizeResult.noTrade('حاشیه مورد نیاز بیشتر از موجودی');
    }
    if (qty <= 0) return FuturesSizeResult.noTrade('حجم صفر');

    return FuturesSizeResult(
      allow: true,
      quantity: qty,
      requiredMargin: margin,
      riskAmount: actualRisk,
      leverage: leverage,
      notional: qty * entry,
      reason: 'OK',
    );
  }
}

/// Transfer ONLY required margin (+ optional fee buffer). Never full wallet.
double exactTransferAmount({
  required double requiredMargin,
  required double spotFree,
  double feeBuffer = 0.0,
}) {
  final need = requiredMargin + feeBuffer;
  if (need <= 0 || need > spotFree) return 0;
  return need;
}
