import '../models/market_data.dart';
import 'binance_public.dart';
import 'market_data_source.dart';

/// Public Binance market data adapter — fallback / future multi-exchange.
/// Read-only. Does not place orders. Does not change Tabdeal trading path.
class BinanceMarketDataSource implements MarketDataSource {
  BinanceMarketDataSource({BinancePublic? client})
      : client = client ?? BinancePublic();

  final BinancePublic client;

  static const _fallback = <String>[
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'BNBUSDT',
    'XRPUSDT',
    'DOGEUSDT',
    'ADAUSDT',
    'TRXUSDT',
    'AVAXUSDT',
    'LINKUSDT',
  ];

  @override
  String get id => 'binance';

  @override
  String get displayName => 'Binance (public)';

  @override
  Future<bool> ping() => client.ping();

  @override
  String normalizeSymbol(String raw) {
    var s = raw.toUpperCase().replaceAll('_', '').replaceAll('-', '');
    if (s.endsWith('IRT') || s.endsWith('TMN')) {
      s = '${s.substring(0, s.length - 3)}USDT';
    }
    if (!s.endsWith('USDT') && s.isNotEmpty) s = '${s}USDT';
    return s;
  }

  @override
  Future<List<String>> listSymbols({
    int maxSymbols = 40,
    bool preferSpot = true,
  }) async {
    // Public list without auth — curated liquid USDT pairs.
    return _fallback.take(maxSymbols).toList();
  }

  @override
  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) =>
      client.trades(normalizeSymbol(symbol), limit: limit);

  @override
  Future<Map<String, dynamic>> depth(String symbol, {int limit = 20}) =>
      client.depth(normalizeSymbol(symbol));
}
