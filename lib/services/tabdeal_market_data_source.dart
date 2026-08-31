import '../models/market_data.dart';
import 'market_data_source.dart';
import 'tabdeal_api.dart';

/// Default production market data source — api1.tabdeal.org first.
/// Does not place orders.
class TabdealMarketDataSource implements MarketDataSource {
  TabdealMarketDataSource({TabdealApi? api}) : api = api ?? TabdealApi();

  final TabdealApi api;

  @override
  String get id => 'tabdeal';

  @override
  String get displayName => 'تبدیل (Tabdeal)';

  @override
  Future<bool> ping() => api.ping();

  @override
  String normalizeSymbol(String raw) => api.normalizeSymbol(raw);

  @override
  Future<List<String>> listSymbols({
    int maxSymbols = 40,
    bool preferSpot = true,
  }) async {
    if (preferSpot) {
      return api.activeUsdtSymbols(maxSymbols: maxSymbols);
    }
    return api.activeFuturesSymbols(maxSymbols: maxSymbols);
  }

  @override
  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) =>
      api.trades(symbol, limit: limit);

  @override
  Future<Map<String, dynamic>> depth(String symbol, {int limit = 20}) async {
    try {
      final d = await api.futuresDepth(symbol, limit: limit);
      if ((d['bids'] as List?)?.isNotEmpty == true) return d;
    } catch (_) {}
    return api.depth(symbol);
  }
}
