import 'tabdeal_api.dart';
import 'order_sizing.dart';

/// Loads and caches per-symbol trading rules from Tabdeal exchangeInfo.
class SymbolRulesService {
  SymbolRulesService(this.api);

  final TabdealApi api;
  final Map<String, SymbolFilters> _cache = {};
  DateTime? _loadedAt;

  Future<SymbolFilters> filtersFor(String symbol) async {
    final key = symbol.toUpperCase().replaceAll('_', '');
    await _ensureLoaded();
    return _cache[key] ?? SymbolFilters.fallback(key);
  }

  Future<void> _ensureLoaded() async {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 30) &&
        _cache.isNotEmpty) {
      return;
    }
    try {
      final payload = await api.rawExchangeInfo();
      final raw = payload is Map
          ? (payload['symbols'] ?? payload['data'] ?? payload)
          : payload;
      if (raw is! List) return;
      for (final item in raw) {
        if (item is Map) {
          final f = SymbolFilters.fromExchangeItem(Map<String, dynamic>.from(item));
          if (f.symbol.isNotEmpty) _cache[f.symbol] = f;
        } else if (item is String) {
          final s = item.toUpperCase().replaceAll('_', '');
          _cache[s] = SymbolFilters.fallback(s);
        }
      }
      _loadedAt = DateTime.now();
    } catch (_) {
      // Keep fallbacks; do not invent market data.
    }
  }

  void clearCache() {
    _cache.clear();
    _loadedAt = null;
  }
}
