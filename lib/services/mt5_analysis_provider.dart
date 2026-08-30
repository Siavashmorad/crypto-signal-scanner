import 'mt5_bridge_client.dart';
import 'mt5_metaapi_client.dart';

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

/// Unified read-only MT5 provider. Supports MetaAPI cloud or custom bridge.
/// Intentionally exposes no order / modify / close API.
class Mt5AnalysisProvider implements MarketAnalysisProvider {
  Mt5AnalysisProvider.bridge({required Mt5BridgeClient client})
      : _bridge = client,
        _meta = null,
        sourceLabel = 'Bridge';

  Mt5AnalysisProvider.metaApi({required Mt5MetaApiClient client})
      : _meta = client,
        _bridge = null,
        sourceLabel = 'MetaAPI';

  /// Backward-compatible constructor (custom bridge).
  factory Mt5AnalysisProvider({required Mt5BridgeClient client}) =>
      Mt5AnalysisProvider.bridge(client: client);

  final Mt5BridgeClient? _bridge;
  final Mt5MetaApiClient? _meta;
  final String sourceLabel;

  @override
  String get name => 'MT5 ($sourceLabel)';

  @override
  bool get isAvailable => true;

  Future<bool> checkConnection() async {
    if (_meta != null) return _meta!.health();
    return _bridge!.health();
  }

  /// Bridge-only session login. MetaAPI uses token + accountId instead.
  Future<void> login({required String login, required String password}) async {
    if (_meta != null) return;
    await _bridge!.authenticate(login: login, password: password);
  }

  Future<Mt5AccountSnapshot> account() async {
    if (_meta != null) return _meta!.account();
    return _bridge!.account();
  }

  Future<List<Mt5PositionSnapshot>> positions() async {
    if (_meta != null) return _meta!.positions();
    return _bridge!.positions();
  }

  Future<List<String>> symbols() async {
    if (_meta != null) return _meta!.symbols();
    return _bridge!.symbols();
  }

  @override
  Future<List<AnalysisBar>> fetchBars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  }) async {
    if (_meta != null) {
      return const [];
    }
    final bars =
        await _bridge!.bars(symbol: symbol, timeframe: timeframe, limit: limit);
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

  void dispose() {
    _meta?.dispose();
    _bridge?.dispose();
  }
}
