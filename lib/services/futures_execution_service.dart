import 'account_balance.dart';
import 'futures_sizing.dart';
import 'order_sizing.dart';
import 'tabdeal_trade.dart';

class FuturesExecPlan {
  final String symbol;
  final String side;
  final double entry;
  final double stopLoss;
  final double? takeProfit;
  final double riskPercent;
  final double leverage;
  final FuturesSizeResult size;
  final double transferAmount;
  final double spotFree;
  final double futuresAvailable;
  final bool needsTransfer;

  const FuturesExecPlan({
    required this.symbol,
    required this.side,
    required this.entry,
    required this.stopLoss,
    this.takeProfit,
    required this.riskPercent,
    required this.leverage,
    required this.size,
    required this.transferAmount,
    required this.spotFree,
    required this.futuresAvailable,
    required this.needsTransfer,
  });

  String get orderSide => side.toUpperCase() == 'SHORT' ? 'SELL' : 'BUY';
}

class FuturesExecResult {
  final bool ok;
  final String message;
  final FuturesPosition? position;
  final bool slActive;
  final bool tpActive;
  final int? orderId;

  const FuturesExecResult({
    required this.ok,
    required this.message,
    this.position,
    this.slActive = false,
    this.tpActive = false,
    this.orderId,
  });

  factory FuturesExecResult.fail(String m) =>
      FuturesExecResult(ok: false, message: m);
}

/// Safe Futures open/close. Official Tabdeal FAPI only. No blind retry.
class FuturesExecutionService {
  FuturesExecutionService(this.client,
      {this.sizing = const FuturesSizingEngine()});

  final TabdealTradeClient client;
  final FuturesSizingEngine sizing;

  Future<FuturesExecPlan?> buildPlan({
    required String symbol,
    required String side,
    required double entry,
    required double stopLoss,
    double? takeProfit,
    required double riskPercent,
    required double leverage,
    required SymbolFilters filters,
  }) async {
    final futBal = await client.futuresBalanceSnapshot();
    if (!futBal.futuresActive || !futBal.available) return null;

    final quote = AccountSnapshot.quoteAsset(symbol);
    final futAvail = futBal.of(quote)?.availableBalance ?? 0;
    final equity = futBal.of(quote)?.walletBalance ?? futAvail;

    final size = sizing.size(
      equity: equity > 0 ? equity : (futAvail > 0 ? futAvail : 1),
      availableBalance: futAvail > 0 ? futAvail : 1e12,
      riskPercent: riskPercent,
      entry: entry,
      stopLoss: stopLoss,
      leverage: leverage,
      filters: filters,
    );

    final spot = await client.accountSnapshot();
    final spotFree = spot.of(quote)?.free ?? 0;
    final needsTransfer = size.allow && size.requiredMargin > futAvail * 0.999;
    double transferAmt = 0;

    if (needsTransfer) {
      transferAmt = exactTransferAmount(
        requiredMargin: size.requiredMargin - futAvail,
        spotFree: spotFree,
      );
      if (transferAmt <= 0) {
        return FuturesExecPlan(
          symbol: symbol,
          side: side,
          entry: entry,
          stopLoss: stopLoss,
          takeProfit: takeProfit,
          riskPercent: riskPercent,
          leverage: leverage,
          size: FuturesSizeResult.noTrade('موجودی اسپات برای انتقال کافی نیست'),
          transferAmount: 0,
          spotFree: spotFree,
          futuresAvailable: futAvail,
          needsTransfer: true,
        );
      }
    }

    final finalSize = sizing.size(
      equity: (equity > 0 ? equity : futAvail) + transferAmt,
      availableBalance: futAvail + transferAmt,
      riskPercent: riskPercent,
      entry: entry,
      stopLoss: stopLoss,
      leverage: leverage,
      filters: filters,
    );

    return FuturesExecPlan(
      symbol: symbol,
      side: side,
      entry: entry,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      riskPercent: riskPercent,
      leverage: leverage,
      size: finalSize,
      transferAmount: transferAmt,
      spotFree: spotFree,
      futuresAvailable: futAvail,
      needsTransfer: needsTransfer && transferAmt > 0,
    );
  }

  Future<FuturesExecResult> execute(FuturesExecPlan plan) async {
    if (!plan.size.allow) return FuturesExecResult.fail(plan.size.reason);

    // Exact transfer only
    if (plan.needsTransfer && plan.transferAmount > 0) {
      try {
        await client.transfer(
          type: 2,
          asset: AccountSnapshot.quoteAsset(plan.symbol),
          amount: plan.transferAmount,
        );
      } catch (e) {
        return FuturesExecResult.fail('انتقال ناموفق: $e');
      }

      // Balance re-check — never continue on local assumptions
      final after = await client.futuresBalanceSnapshot();
      if (!after.available) {
        return FuturesExecResult.fail(
            'پس از انتقال موجودی خوانده نشد — NO TRADE');
      }
      final avail =
          after.of(AccountSnapshot.quoteAsset(plan.symbol))?.availableBalance ??
              0;
      if (avail + 1e-8 < plan.size.requiredMargin * 0.98) {
        return FuturesExecResult.fail(
            'موجودی Futures پس از انتقال کافی نیست — NO TRADE');
      }
    }

    try {
      await client.changeLeverage(
        symbol: plan.symbol,
        leverage: plan.leverage.round().clamp(1, 125),
      );
    } catch (_) {}

    // Duplicate protection
    final before = await client.futuresPositionsSnapshot(symbol: plan.symbol);
    if (before.available) {
      for (final p in before.positions) {
        if (p.isOpen) {
          return FuturesExecResult.fail(
              'پوزیشن باز موجود — سفارش تکراری ارسال نشد');
        }
      }
    }

    Map<String, dynamic> orderRes;
    try {
      orderRes = await client.futuresMarketOrder(
        symbol: plan.symbol,
        side: plan.orderSide,
        quantity: plan.size.quantity,
      );
    } catch (e) {
      final amb = await _resolveAmbiguous(plan.symbol);
      if (amb != null) return amb;
      return FuturesExecResult.fail('سفارش ناموفق/نامشخص: $e');
    }

    final orderId = int.tryParse('${orderRes['orderId'] ?? ''}');
    await Future.delayed(const Duration(milliseconds: 800));
    var pos = await client.futuresPositionsSnapshot(symbol: plan.symbol);
    if (!pos.available || pos.positions.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 1200));
      pos = await client.futuresPositionsSnapshot(symbol: plan.symbol);
      if (!pos.available || pos.positions.isEmpty) {
        return FuturesExecResult(
          ok: false,
          message: 'سفارش ارسال شد ولی پوزیشن تأیید نشد',
          orderId: orderId,
        );
      }
    }
    return await _attachSlTp(plan, pos.positions.first, orderId);
  }

  Future<FuturesExecResult?> _resolveAmbiguous(String symbol) async {
    try {
      final open = await client.futuresOpenOrders(symbol: symbol);
      final list = open['list'] ?? open['orders'] ?? open;
      if (list is List && list.isNotEmpty) {
        return FuturesExecResult(
          ok: false,
          message: 'سفارش باز موجود — ارسال مجدد نشد',
        );
      }
      final pos = await client.futuresPositionsSnapshot(symbol: symbol);
      if (pos.available && pos.positions.isNotEmpty) {
        return FuturesExecResult(
          ok: true,
          message: 'پوزیشن پس از timeout تأیید شد',
          position: pos.positions.first,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<FuturesExecResult> _attachSlTp(
    FuturesExecPlan plan,
    FuturesPosition pos,
    int? orderId,
  ) async {
    bool slOk = false;
    bool tpOk = false;
    final pid = pos.positionId;
    if (pid != null) {
      try {
        final res = await client.futuresPositionSlTp(
          positionId: pid,
          symbol: plan.symbol,
          slPrice: plan.stopLoss > 0 ? plan.stopLoss : null,
          tpPrice: plan.takeProfit,
        );
        final msg = '${res['msg'] ?? res['message'] ?? ''}'.toLowerCase();
        if (msg.contains('success') || res['code'] == null) {
          slOk = plan.stopLoss > 0;
          tpOk = plan.takeProfit != null && plan.takeProfit! > 0;
        }
      } catch (_) {}
    }
    return FuturesExecResult(
      ok: true,
      message: 'FUTURES POSITION OPEN',
      position: pos,
      slActive: slOk,
      tpActive: tpOk,
      orderId: orderId,
    );
  }

  Future<FuturesExecResult> closePosition(String symbol) async {
    final before = await client.futuresPositionsSnapshot(symbol: symbol);
    if (!before.available) {
      return FuturesExecResult.fail('وضعیت پوزیشن خوانده نشد');
    }
    if (before.positions.isEmpty) {
      return FuturesExecResult.fail('پوزیشن بازی وجود ندارد');
    }
    try {
      await client.futuresClosePosition(symbol: symbol);
    } catch (e) {
      return FuturesExecResult.fail('بستن ناموفق: $e');
    }
    await Future.delayed(const Duration(milliseconds: 800));
    final after = await client.futuresPositionsSnapshot(symbol: symbol);
    if (after.available && after.positions.isEmpty) {
      return const FuturesExecResult(ok: true, message: 'CLOSED');
    }
    if (!after.available) {
      return FuturesExecResult.fail('CLOSE STATE UNKNOWN');
    }
    return FuturesExecResult.fail('CLOSE STATE UNKNOWN — پوزیشن هنوز باز است');
  }
}
