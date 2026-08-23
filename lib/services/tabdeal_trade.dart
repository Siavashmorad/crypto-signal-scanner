import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Signed Tabdeal client on phone — signature matches official Python SDK.
class TabdealTradeClient {
  TabdealTradeClient({
    required this.apiKey,
    required this.apiSecret,
    this.baseUrl = 'https://api1.tabdeal.org',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String apiSecret;
  final String baseUrl;
  final http.Client _client;

  static const hosts = ['https://api1.tabdeal.org', 'https://api.tabdeal.org'];

  bool get configured => apiKey.trim().isNotEmpty && apiSecret.trim().isNotEmpty;

  /// Official Python uses urllib urlencode order (insertion order), NOT sorted keys.
  String _sign(Map<String, String> params) {
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final digest =
        Hmac(sha256, utf8.encode(apiSecret)).convert(utf8.encode(query));
    return digest.toString();
  }

  String _compact(String symbol) =>
      symbol.toUpperCase().replaceAll('_', '').replaceAll('-', '');

  String _tabdealSymbol(String compact) {
    final s = _compact(compact);
    for (final q in ['USDT', 'IRT', 'TMN']) {
      if (s.endsWith(q) && s.length > q.length) {
        return '${s.substring(0, s.length - q.length)}_$q';
      }
    }
    return s;
  }

  Future<Map<String, dynamic>> _signed({
    required String method,
    required String path,
    Map<String, String>? body,
  }) async {
    Object? lastErr;
    for (final host in hosts) {
      try {
        // Build params in stable insertion order (same as tabdeal-python).
        final params = <String, String>{};
        if (body != null) {
          for (final e in body.entries) {
            params[e.key] = e.value;
          }
        }
        params['timestamp'] = '${DateTime.now().millisecondsSinceEpoch}';
        params['recvWindow'] = '60000';
        final signature = _sign(params);
        params['signature'] = signature;

        final uri = Uri.parse('$host$path');
        final headers = {
          'X-MBX-APIKEY': apiKey.trim(),
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 SignalYab-Phone/1.1',
        };

        late http.Response res;
        if (method == 'POST') {
          res = await _client
              .post(uri, headers: headers, body: params)
              .timeout(const Duration(seconds: 25));
        } else {
          res = await _client
              .get(uri.replace(queryParameters: params), headers: headers)
              .timeout(const Duration(seconds: 25));
        }

        Map<String, dynamic> decoded = {};
        try {
          final raw = jsonDecode(res.body);
          if (raw is Map<String, dynamic>) {
            decoded = raw;
          } else if (raw is List) {
            decoded = {'list': raw};
          } else {
            decoded = {'raw': raw};
          }
        } catch (_) {
          decoded = {'raw_body': res.body};
        }

        if (res.statusCode < 200 || res.statusCode >= 300) {
          final msg = decoded['msg'] ??
              decoded['message'] ??
              decoded['detail'] ??
              decoded['code'] ??
              decoded['raw_body'] ??
              'HTTP ${res.statusCode}';
          lastErr = msg;
          // try next host
          continue;
        }
        return decoded;
      } catch (e) {
        lastErr = e;
      }
    }
    throw StateError('اتصال/سفارش تبدیل ناموفق: $lastErr');
  }

  /// Spot MARKET. Uses tabdealSymbol (BTC_IRT) preferred by API docs.
  Future<Map<String, dynamic>> marketOrder({
    required String symbol,
    required String side,
    required double quantity,
  }) {
    final compact = _compact(symbol);
    final td = _tabdealSymbol(compact);
    return _signed(
      method: 'POST',
      path: '/api/v1/order',
      body: {
        'tabdealSymbol': td,
        'symbol': compact,
        'side': side.toUpperCase(),
        'type': 'MARKET',
        'quantity': _qty(quantity),
      },
    );
  }

  Future<Map<String, dynamic>> account() =>
      _signed(method: 'GET', path: '/r/api/v1/account');

  Future<Map<String, dynamic>> openOrders({String? symbol}) {
    final body = <String, String>{};
    if (symbol != null) {
      body['tabdealSymbol'] = _tabdealSymbol(symbol);
      body['symbol'] = _compact(symbol);
    }
    return _signed(method: 'GET', path: '/r/api/v1/openOrders', body: body);
  }

  String _qty(double q) {
    if (q >= 1) return q.toStringAsFixed(4);
    if (q >= 0.01) return q.toStringAsFixed(6);
    return q.toStringAsFixed(8);
  }

  void dispose() => _client.close();
}
