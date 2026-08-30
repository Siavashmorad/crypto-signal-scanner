import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure local storage for MT5 bridge credentials.
class Mt5SettingsStore {
  const Mt5SettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _urlKey = 'mt5_bridge_url';
  static const _loginKey = 'mt5_login';
  static const _passwordKey = 'mt5_password';

  Future<String?> get bridgeUrl => _storage.read(key: _urlKey);
  Future<String?> get login => _storage.read(key: _loginKey);
  Future<String?> get password => _storage.read(key: _passwordKey);

  Future<void> save({
    required String bridgeUrl,
    required String login,
    required String password,
  }) async {
    await _storage.write(key: _urlKey, value: bridgeUrl.trim());
    await _storage.write(key: _loginKey, value: login.trim());
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _loginKey);
    await _storage.delete(key: _passwordKey);
  }
}
