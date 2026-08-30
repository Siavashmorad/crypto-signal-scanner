import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure local storage for MT5 connection credentials.
/// Supports both custom bridge and MetaAPI cloud modes.
class Mt5SettingsStore {
  const Mt5SettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _modeKey = 'mt5_mode'; // bridge | metaapi
  static const _urlKey = 'mt5_bridge_url';
  static const _loginKey = 'mt5_login';
  static const _passwordKey = 'mt5_password';
  static const _tokenKey = 'mt5_metaapi_token';
  static const _accountIdKey = 'mt5_metaapi_account_id';
  static const _regionKey = 'mt5_metaapi_region';

  Future<String> get mode async =>
      (await _storage.read(key: _modeKey))?.trim() ?? 'metaapi';

  Future<String?> get bridgeUrl => _storage.read(key: _urlKey);
  Future<String?> get login => _storage.read(key: _loginKey);
  Future<String?> get password => _storage.read(key: _passwordKey);
  Future<String?> get metaApiToken => _storage.read(key: _tokenKey);
  Future<String?> get metaApiAccountId => _storage.read(key: _accountIdKey);
  Future<String> get metaApiRegion async =>
      (await _storage.read(key: _regionKey))?.trim().isNotEmpty == true
          ? (await _storage.read(key: _regionKey))!.trim()
          : 'new-york';

  Future<void> saveBridge({
    required String bridgeUrl,
    required String login,
    required String password,
  }) async {
    await _storage.write(key: _modeKey, value: 'bridge');
    await _storage.write(key: _urlKey, value: bridgeUrl.trim());
    await _storage.write(key: _loginKey, value: login.trim());
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> saveMetaApi({
    required String token,
    required String accountId,
    String region = 'new-york',
  }) async {
    await _storage.write(key: _modeKey, value: 'metaapi');
    await _storage.write(key: _tokenKey, value: token.trim());
    await _storage.write(key: _accountIdKey, value: accountId.trim());
    await _storage.write(key: _regionKey, value: region.trim());
  }

  /// Legacy helper used by older callers.
  Future<void> save({
    required String bridgeUrl,
    required String login,
    required String password,
  }) =>
      saveBridge(bridgeUrl: bridgeUrl, login: login, password: password);

  Future<void> clear() async {
    await _storage.delete(key: _modeKey);
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _loginKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _accountIdKey);
    await _storage.delete(key: _regionKey);
  }
}
