import 'package:shared_preferences/shared_preferences.dart';

import 'binance_market_data_source.dart';
import 'market_data_source.dart';
import 'tabdeal_api.dart';
import 'tabdeal_market_data_source.dart';

/// Resolves the active [MarketDataSource] for scanning / Focus / AI.
///
/// Default remains **Tabdeal** (`api1.tabdeal.org`).
/// Preference key allows a future UI switch without rewriting the engine.
///
/// Order path is unchanged: live orders still go only through Tabdeal trade
/// client + Live Gate + notional cap — never through this registry alone.
class ExchangeRegistry {
  ExchangeRegistry._();

  static const prefKey = 'market_data_source_id';
  static const defaultId = 'tabdeal';

  static final TabdealApi sharedTabdealApi = TabdealApi();

  /// Build source by id. Unknown ids fall back to Tabdeal.
  static MarketDataSource byId(String id, {TabdealApi? tabdealApi}) {
    switch (id) {
      case 'binance':
        return BinanceMarketDataSource();
      case 'tabdeal':
      default:
        return TabdealMarketDataSource(api: tabdealApi ?? sharedTabdealApi);
    }
  }

  /// Active source from SharedPreferences (default Tabdeal).
  static Future<MarketDataSource> active({TabdealApi? tabdealApi}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(prefKey) ?? defaultId;
    return byId(id, tabdealApi: tabdealApi);
  }

  static Future<void> setActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, id);
  }

  static Future<String> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefKey) ?? defaultId;
  }

  /// Known sources for future settings UI.
  static List<({String id, String labelFa})> catalog() => const [
        (id: 'tabdeal', labelFa: 'تبدیل (پیش‌فرض)'),
        (id: 'binance', labelFa: 'Binance عمومی (فقط داده)'),
      ];
}
