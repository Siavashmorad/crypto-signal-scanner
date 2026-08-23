import 'package:shared_preferences/shared_preferences.dart';

/// API keys + default size stored only on this phone.
class LocalTradeStore {
  static const _kKey = 'tabdeal_api_key';
  static const _kSecret = 'tabdeal_api_secret';
  static const _kQty = 'default_order_qty';
  static const _kLive = 'live_trading_enabled';

  Future<void> save({
    required String apiKey,
    required String apiSecret,
    required double defaultQty,
    required bool liveEnabled,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, apiKey.trim());
    await p.setString(_kSecret, apiSecret.trim());
    await p.setDouble(_kQty, defaultQty);
    await p.setBool(_kLive, liveEnabled);
  }

  Future<String> apiKey() async =>
      (await SharedPreferences.getInstance()).getString(_kKey) ?? '';

  Future<String> apiSecret() async =>
      (await SharedPreferences.getInstance()).getString(_kSecret) ?? '';

  Future<double> defaultQty() async =>
      (await SharedPreferences.getInstance()).getDouble(_kQty) ?? 0.001;

  Future<bool> liveEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kLive) ?? false;

  Future<bool> hasKeys() async {
    final k = await apiKey();
    final s = await apiSecret();
    return k.isNotEmpty && s.isNotEmpty;
  }

  Future<void> clearKeys() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    await p.remove(_kSecret);
    await p.setBool(_kLive, false);
  }
}
