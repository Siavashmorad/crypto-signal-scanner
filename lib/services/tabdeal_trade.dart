import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Signed Tabdeal client — runs entirely on the phone (no server).
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

  bool get configured => apiKey.trim().isNotEmpty && apiSecret.trim().isNotEmpty;

  String _sign(Map<String, String> params) {
    final sorted = params.keys.toList()..sort();
    final query = sorted.map((k) => '$k=${params[k]}').join('&');
    final digest = Hmac(sha256, utf8.encode(apiSecret)).convert(utf8.encode(query));
    return digest.toString();
  }

  Future<Map<String, dynamic>> _signed({
    required String method,
    required String path,
    Map<String, String>? body,
  }) async {
    final params = <String, String>{...(body ?? {})};
    params['timestamp'] = '${DateTime.now().millisecondsSinceEpoch}';
    params['recvWindow'] = '5000';
    params['signature'] = _sign(params);

    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'X-MBX-APIKEY': apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
      'User-Agent': 'SignalYab-Phone/1.0',
    };

    late http.Response res;
    if (method == 'POST') {
      res = await _client
          .post(uri, headers: headers, body: params)
          .timeout(const Duration(seconds: 20));
    } else if (method == 'DELETE') {
      res = await _client
          .delete(uri.replace(queryParameters: params), headers: headers)
          .timeout(const Duration(seconds: 20));
    } else {
      res = await _client
          .get(uri.replace(queryParameters: params), headers: headers)
          .timeout(const Duration(seconds: 20));
    }

    Map<String, dynamic> decoded = {};
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map<String, dynamic>) {
        decoded = raw;
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
          decoded['raw_body'] ??
          'HTTP ${res.statusCode}';
      throw StateError('سفارش ناموفق: $msg');
    }
    return decoded;
  }

  /// Spot MARKET order. side: BUY or SELL.
  Future<Map<String, dynamic>> marketOrder({
    required String symbol,
    required String side,
    required double quantity,
  }) {
    final sym = symbol.toUpperCase().replaceAll('_', '');
    return _signed(
      method: 'POST',
      path: '/api/v1/order',
      body: {
        'symbol': sym,
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
      body['symbol'] = symbol.toUpperCase().replaceAll('_', '');
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
