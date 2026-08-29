/// Optional MetaTrader 5 analysis/data provider.
///
/// MT5 is ANALYSIS ONLY.
/// - Does NOT place Tabdeal orders.
/// - Is NOT connected to SpotAutoTrader.
/// - Is NOT required for the app to function.
///
/// Real MT5 connectivity typically needs an external bridge/backend.
/// This file defines a clean interface + a disabled default implementation.
library;

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

/// Optional external market-analysis provider (Tabdeal remains execution source).
abstract class MarketAnalysisProvider {
  String get name;
  bool get isAvailable;

  Future<List<AnalysisBar>> fetchBars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  });
}

/// Disabled MT5 adapter — enable only when a real bridge is configured.
class Mt5AnalysisProvider implements MarketAnalysisProvider {
  Mt5AnalysisProvider({this.bridgeBaseUrl});

  /// Optional bridge URL. When null/empty, provider stays unavailable.
  final String? bridgeBaseUrl;

  @override
  String get name => 'MT5';

  @override
  bool get isAvailable =>
      bridgeBaseUrl != null && bridgeBaseUrl!.trim().isNotEmpty;

  @override
  Future<List<AnalysisBar>> fetchBars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  }) async {
    // No hard dependency / no order execution.
    // Without a configured bridge, return empty so analysis continues on Tabdeal.
    if (!isAvailable) return const [];
    // Bridge integration is intentionally not implemented here.
    return const [];
  }
}
