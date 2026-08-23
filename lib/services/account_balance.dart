/// Parsed balances from Tabdeal GET /r/api/v1/account — no fake zeros.
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

  const AccountSnapshot({
    required this.balances,
    this.available = true,
    this.error,
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
      final free = double.tryParse('${item['free'] ?? item['available'] ?? item['a'] ?? 0}') ?? 0;
      final locked = double.tryParse('${item['locked'] ?? item['freeze'] ?? item['l'] ?? 0}') ?? 0;
      if (free == 0 && locked == 0) continue;
      out.add(AssetBalance(asset: asset, free: free, locked: locked));
    }
    return AccountSnapshot(balances: out);
  }

  AssetBalance? of(String asset) {
    final a = asset.toUpperCase();
    for (final b in balances) {
      if (b.asset == a) return b;
    }
    return null;
  }

  /// Quote asset for symbol e.g. BCHUSDT → USDT, BTCIRT → IRT
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
