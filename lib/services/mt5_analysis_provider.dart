import 'mt5_bridge_client.dart';

/// OHLC bar from an external analysis source.
class AnalysisBar {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const AnalysisBar({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });
}

abstract class MarketAnalysisProvider {
  String get name;
  bool get isAvailable;

  Future<List<AnalysisBar>> fetchBars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  });
}

/// Real read-only MT5 bridge provider. It has no order API by design.
class Mt5AnalysisProvider implements MarketAnalysisProvider {
  Mt5AnalysisProvider({required this.client});

  final Mt5BridgeClient client;

  @override
  String get name => 'MT5';

  @override
  bool get isAvailable => true;

  Future<bool> checkConnection() => client.health();

  Future<void> login({required String login, required String password}) =>
      client.authenticate(login: login, password: password);

  Future<Mt5AccountSnapshot> account() => client.account();

  Future<List<Mt5PositionSnapshot>> positions() => client.positions();

  Future<List<String>> symbols() => client.symbols();

  @override
  Future<List<AnalysisBar>> fetchBars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  }) async {
    final bars = await client.bars(symbol: symbol, timeframe: timeframe, limit: limit);
    return bars
        .map((bar) => AnalysisBar(
              time: bar.time,
              open: bar.open,
              high: bar.high,
              low: bar.low,
              close: bar.close,
              volume: bar.volume,
            ))
        .toList(growable: false);
  }

  void dispose() => client.dispose();
}
