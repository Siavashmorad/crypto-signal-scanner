import '../models/market_data.dart';

/// Exchange-agnostic market data contract.
/// Signal / Focus / Background engines talk only to this interface.
/// Trading execution stays separate and gated (Tabdeal today).
///
/// Safety: implementations provide **read-only** market data.
/// No order placement belongs here.
abstract class MarketDataSource {
  /// Stable id: `tabdeal` | `binance` | future ids.
  String get id;

  /// Human-readable name (Persian or English).
  String get displayName;

  /// True if public endpoints respond.
  Future<bool> ping();

  /// Active symbols for scanning (prefer USDT / local quote).
  Future<List<String>> listSymbols({int maxSymbols = 40, bool preferSpot = true});

  /// Recent trades for candle construction.
  Future<List<TradePoint>> trades(String symbol, {int limit = 200});

  /// Order book depth (bids/asks).
  Future<Map<String, dynamic>> depth(String symbol, {int limit = 20});

  /// Normalize symbol to exchange form (e.g. BTCUSDT).
  String normalizeSymbol(String raw);
}
