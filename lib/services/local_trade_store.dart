import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tabdeal API credentials via platform secure storage (Android Keystore / iOS Keychain).
/// One-time migration from SharedPreferences; plaintext keys cleared after success.
/// Never log secrets. Never expose secrets in toString/debug.
class LocalTradeStore {
  static const _kKey = 'tabdeal_api_key';
  static const _kSecret = 'tabdeal_api_secret';
  static const _kQty = 'default_order_qty';
  static const _kLive = 'live_trading_enabled';
  static const _kMigrated = 'secure_creds_migrated_v1';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> _migrateIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kMigrated) == true) return;

    final legacyKey = p.getString(_kKey) ?? '';
    final legacySecret = p.getString(_kSecret) ?? '';

    if (legacyKey.isNotEmpty) {
      final existing = await _secure.read(key: _kKey);
      if (existing == null || existing.isEmpty) {
        await _secure.write(key: _kKey, value: legacyKey);
      }
    }
    if (legacySecret.isNotEmpty) {
      final existing = await _secure.read(key: _kSecret);
      if (existing == null || existing.isEmpty) {
        await _secure.write(key: _kSecret, value: legacySecret);
      }
    }

    // Clear plaintext after write (or if already empty).
    await p.remove(_kKey);
    await p.remove(_kSecret);
    await p.setBool(_kMigrated, true);
  }

  Future<void> save({
    required String apiKey,
    required String apiSecret,
    required double defaultQty,
    required bool liveEnabled,
  }) async {
    await _migrateIfNeeded();
    await _secure.write(key: _kKey, value: apiKey.trim());
    await _secure.write(key: _kSecret, value: apiSecret.trim());
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kQty, defaultQty);
    await p.setBool(_kLive, liveEnabled);
  }

  Future<String> apiKey() async {
    await _migrateIfNeeded();
    return await _secure.read(key: _kKey) ?? '';
  }

  Future<String> apiSecret() async {
    await _migrateIfNeeded();
    return await _secure.read(key: _kSecret) ?? '';
  }

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
    await _secure.delete(key: _kKey);
    await _secure.delete(key: _kSecret);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    await p.remove(_kSecret);
    await p.setBool(_kLive, false);
  }

  /// Test helper: reports whether migration flag is set (no secrets returned).
  Future<bool> isMigrated() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kMigrated) == true;
  }
}
