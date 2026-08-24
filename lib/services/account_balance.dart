/// Parsed balances from Tabdeal — no fake zeros when unavailable.
class AssetBalance {
  final String asset;
  final double free;
  final double locked;

  const AssetBalance({
    required this.asset,
    required this.free,
    required this.locked,
  });

  double get total => free + locked;
}

class AccountSnapshot {
  final List<AssetBalance> balances;
  final bool available;
  final String? error;
  final DateTime? fetchedAt;

  const AccountSnapshot({
    required this.balances,
    this.available = true,
    this.error,
    this.fetchedAt,
  });

  factory AccountSnapshot.unavailable(String reason) =>
      AccountSnapshot(balances: const [], available: false, error: reason);

  factory AccountSnapshot.fromApi(Map<String, dynamic> raw) {
    final list = raw['balances'] ?? raw['balance'] ?? raw['assets'];
    if (list is! List) {
      return AccountSnapshot.unavailable('ساختار موجودی از API ناشناخته است');
    }
    final out = <AssetBalance>[];
    for (final item in list) {
      if (item is! Map) continue;
      final asset = '${item['asset'] ?? item['currency'] ?? item['coin'] ?? ''}'
          .toUpperCase();
      if (asset.isEmpty) continue;
      final free =
          double.tryParse('${item['free'] ?? item['available'] ?? item['a'] ?? 0}') ??
              0;
      final locked =
          double.tryParse('${item['locked'] ?? item['freeze'] ?? item['l'] ?? 0}') ??
              0;
      if (free == 0 && locked == 0) continue;
      out.add(AssetBalance(asset: asset, free: free, locked: locked));
    }
    return AccountSnapshot(balances: out, fetchedAt: DateTime.now());
  }

  AssetBalance? of(String asset) {
    final a = asset.toUpperCase();
    for (final b in balances) {
      if (b.asset == a) return b;
    }
    return null;
  }

  static String quoteAsset(String symbol) {
    final s = symbol.toUpperCase().replaceAll('_', '');
    for (final q in ['USDT', 'IRT', 'TMN', 'BTC', 'ETH']) {
      if (s.endsWith(q) && s.length > q.length) return q;
    }
    return 'USDT';
  }

  static String baseAsset(String symbol) {
    final s = symbol.toUpperCase().replaceAll('_', '');
    final q = quoteAsset(s);
    return s.substring(0, s.length - q.length);
  }

  double freeQuote(String symbol) => of(quoteAsset(symbol))?.free ?? 0;

  double freeBase(String symbol) => of(baseAsset(symbol))?.free ?? 0;
}

class FuturesAssetBalance {
  final String asset;
  final double walletBalance;
  final double availableBalance;
  final double crossWalletBalance;
  final double crossUnPnl;

  const FuturesAssetBalance({
    required this.asset,
    required this.walletBalance,
    required this.availableBalance,
    required this.crossWalletBalance,
    required this.crossUnPnl,
  });

  factory FuturesAssetBalance.fromMap(Map item) => FuturesAssetBalance(
        asset: '${item['asset'] ?? ''}'.toUpperCase(),
        walletBalance: double.tryParse('${item['walletBalance'] ?? 0}') ?? 0,
        availableBalance:
            double.tryParse('${item['availableBalance'] ?? 0}') ?? 0,
        crossWalletBalance:
            double.tryParse('${item['crossWalletBalance'] ?? 0}') ?? 0,
        crossUnPnl: double.tryParse('${item['crossUnPnl'] ?? 0}') ?? 0,
      );
}

class FuturesBalanceSnapshot {
  final List<FuturesAssetBalance> balances;
  final bool available;
  final bool futuresActive;
  final String? error;
  final DateTime? fetchedAt;

  const FuturesBalanceSnapshot({
    required this.balances,
    this.available = true,
    this.futuresActive = true,
    this.error,
    this.fetchedAt,
  });

  factory FuturesBalanceSnapshot.unavailable(String reason,
          {bool futuresActive = true}) =>
      FuturesBalanceSnapshot(
        balances: const [],
        available: false,
        futuresActive: futuresActive,
        error: reason,
      );

  factory FuturesBalanceSnapshot.notActive() => FuturesBalanceSnapshot(
        balances: const [],
        available: false,
        futuresActive: false,
        error: 'حساب Futures برای این کاربر فعال نیست',
      );

  factory FuturesBalanceSnapshot.fromApi(dynamic raw) {
    List list;
    if (raw is List) {
      list = raw;
    } else if (raw is Map && raw['list'] is List) {
      list = raw['list'] as List;
    } else if (raw is Map && raw['balances'] is List) {
      list = raw['balances'] as List;
    } else {
      return FuturesBalanceSnapshot.unavailable('ساختار موجودی Futures ناشناخته');
    }
    final out = <FuturesAssetBalance>[];
    for (final item in list) {
      if (item is! Map) continue;
      final b = FuturesAssetBalance.fromMap(Map<String, dynamic>.from(item));
      if (b.asset.isEmpty) continue;
      out.add(b);
    }
    return FuturesBalanceSnapshot(balances: out, fetchedAt: DateTime.now());
  }

  FuturesAssetBalance? of(String asset) {
    final a = asset.toUpperCase();
    for (final b in balances) {
      if (b.asset == a) return b;
    }
    return null;
  }
}

class FuturesPosition {
  final String symbol;
  final double positionAmt;
  final double entryPrice;
  final double markPrice;
  final double unRealizedProfit;
  final double liquidationPrice;
  final double leverage;
  final String marginType;
  final String positionSide;
  final int? positionId;

  const FuturesPosition({
    required this.symbol,
    required this.positionAmt,
    required this.entryPrice,
    required this.markPrice,
    required this.unRealizedProfit,
    required this.liquidationPrice,
    required this.leverage,
    required this.marginType,
    required this.positionSide,
    this.positionId,
  });

  bool get isOpen => positionAmt.abs() > 1e-12;
  bool get isLong => positionAmt > 0;
  bool get isShort => positionAmt < 0;

  factory FuturesPosition.fromMap(Map item) => FuturesPosition(
        symbol:
            '${item['symbol'] ?? ''}'.toUpperCase().replaceAll('_', ''),
        positionAmt: double.tryParse('${item['positionAmt'] ?? 0}') ?? 0,
        entryPrice: double.tryParse('${item['entryPrice'] ?? 0}') ?? 0,
        markPrice: double.tryParse('${item['markPrice'] ?? 0}') ?? 0,
        unRealizedProfit:
            double.tryParse('${item['unRealizedProfit'] ?? 0}') ?? 0,
        liquidationPrice:
            double.tryParse('${item['liquidationPrice'] ?? 0}') ?? 0,
        leverage: double.tryParse('${item['leverage'] ?? 1}') ?? 1,
        marginType: '${item['marginType'] ?? 'cross'}',
        positionSide: '${item['positionSide'] ?? 'BOTH'}',
        positionId:
            int.tryParse('${item['positionId'] ?? item['id'] ?? ''}'),
      );
}

class FuturesPositionsSnapshot {
  final List<FuturesPosition> positions;
  final bool available;
  final bool futuresActive;
  final String? error;

  const FuturesPositionsSnapshot({
    required this.positions,
    this.available = true,
    this.futuresActive = true,
    this.error,
  });

  factory FuturesPositionsSnapshot.unavailable(String reason,
          {bool futuresActive = true}) =>
      FuturesPositionsSnapshot(
        positions: const [],
        available: false,
        futuresActive: futuresActive,
        error: reason,
      );

  factory FuturesPositionsSnapshot.notActive() => FuturesPositionsSnapshot(
        positions: const [],
        available: false,
        futuresActive: false,
        error: 'حساب Futures برای این کاربر فعال نیست',
      );

  factory FuturesPositionsSnapshot.fromApi(dynamic raw) {
    List list;
    if (raw is List) {
      list = raw;
    } else if (raw is Map && raw['list'] is List) {
      list = raw['list'] as List;
    } else if (raw is Map && raw['positions'] is List) {
      list = raw['positions'] as List;
    } else {
      return FuturesPositionsSnapshot.unavailable('ساختار پوزیشن ناشناخته');
    }
    final out = <FuturesPosition>[];
    for (final item in list) {
      if (item is! Map) continue;
      final p = FuturesPosition.fromMap(Map<String, dynamic>.from(item));
      if (p.symbol.isEmpty || !p.isOpen) continue;
      out.add(p);
    }
    return FuturesPositionsSnapshot(positions: out);
  }
}

enum BalanceHealth { live, degraded, stale, offline }

String balanceHealthLabel(BalanceHealth h) {
  switch (h) {
    case BalanceHealth.live:
      return 'LIVE';
    case BalanceHealth.degraded:
      return 'DEGRADED';
    case BalanceHealth.stale:
      return 'STALE';
    case BalanceHealth.offline:
      return 'OFFLINE';
  }
}
