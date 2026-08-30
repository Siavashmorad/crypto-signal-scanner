import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mt5_bridge_client.dart';

/// Read-only MetaAPI cloud client for MetaTrader accounts.
///
/// Uses MetaAPI REST Client API:
///   GET /users/current/accounts/{accountId}/account-information
///   GET /users/current/accounts/{accountId}/positions
///   GET /users/current/accounts/{accountId}/symbols
///
/// Auth header: `auth-token` (MetaAPI token from metaapi.cloud).
/// Account must already be provisioned in MetaAPI dashboard.
///
/// **No trade / order / modify / close endpoints are implemented.**
class Mt5MetaApiClient {
  Mt5MetaApiClient({
    required this.authToken,
    required this.accountId,
    this.region = 'new-york',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// MetaAPI API token (not MT5 password).
  final String authToken;

  /// MetaAPI account UUID (from dashboard after adding MT5 account).
  final String accountId;

  /// API region host segment, e.g. new-york, london, singapore.
  final String region;

  final http.Client _client;

  String get baseUrl =>
      'https://mt-client-api-v1.${region.trim()}.agiliumtrade.ai';

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'auth-token': authToken.trim(),
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  String get _accountPrefix =>
      '/users/current/accounts/${Uri.encodeComponent(accountId.trim())}';

  /// Lightweight connectivity check via account-information.
  Future<bool> health() async {
    try {
      await account();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Mt5AccountSnapshot> account({bool refresh = false}) async {
    final response = await _client.get(
      _uri(
        '$_accountPrefix/account-information',
        refresh ? {'refreshTerminalState': 'true'} : null,
      ),
      headers: _headers,
    );
    _ensureOk(response);
    final body = _jsonMap(response);
    return Mt5AccountSnapshot(
      balance: _number(body['balance']),
      equity: _number(body['equity']),
      margin: _number(body['margin']),
    );
  }

  Future<List<Mt5PositionSnapshot>> positions({bool refresh = false}) async {
    final response = await _client.get(
      _uri(
        '$_accountPrefix/positions',
        refresh ? {'refreshTerminalState': 'true'} : null,
      ),
      headers: _headers,
    );
    _ensureOk(response);
    final body = _json(response);
    if (body is! List) {
      throw const Mt5BridgeException('پاسخ پوزیشن‌های MetaAPI نامعتبر است');
    }
    return body.whereType<Map>().map(_positionFromMeta).toList();
  }

  Future<List<String>> symbols() async {
    final response = await _client.get(
      _uri('$_accountPrefix/symbols'),
      headers: _headers,
    );
    _ensureOk(response);
    final body = _json(response);
    if (body is! List) {
      throw const Mt5BridgeException('پاسخ نمادهای MetaAPI نامعتبر است');
    }
    return body.map((e) => '$e').where((s) => s.isNotEmpty).toList();
  }

  void dispose() => _client.close();

  static Mt5PositionSnapshot _positionFromMeta(Map data) {
    final type = '${data['type'] ?? data['side'] ?? ''}'.toUpperCase();
    final side = type.contains('SELL') || type.contains('SHORT')
        ? 'SHORT'
        : 'LONG';
    return Mt5PositionSnapshot(
      symbol: '${data['symbol'] ?? ''}',
      side: side,
      volume: _number(data['volume']),
      openPrice: _number(data['openPrice'] ?? data['price']),
      stopLoss: data['stopLoss'] == null && data['sl'] == null
          ? null
          : _number(data['stopLoss'] ?? data['sl']),
      takeProfit: data['takeProfit'] == null && data['tp'] == null
          ? null
          : _number(data['takeProfit'] ?? data['tp']),
    );
  }

  static Object? _json(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw const Mt5BridgeException('پاسخ JSON از MetaAPI قابل خواندن نیست');
    }
  }

  static Map<String, dynamic> _jsonMap(http.Response response) {
    final body = _json(response);
    if (body is! Map) {
      throw const Mt5BridgeException('پاسخ حساب MetaAPI نامعتبر است');
    }
    return body.map((k, v) => MapEntry('$k', v));
  }

  static void _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          detail = '${body['message']}';
        }
      } catch (_) {}
      throw Mt5BridgeException('MetaAPI: $detail');
    }
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
