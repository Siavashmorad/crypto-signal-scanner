import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'account_balance.dart';

/// Signed Tabdeal client — Spot only (POST /api/v1/order).
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

  int _serverOffsetMs = 0;

  bool get configured =>
      apiKey.trim().isNotEmpty && apiSecret.trim().isNotEmpty;

  String _urlEncode(Map<String, String> params) {
    return params.entries.map((e) {
      final k =
          Uri.encodeQueryComponent(e.key, encoding: utf8).replaceAll('%20', '+');
      final v =
          Uri.encodeQueryComponent(e.value, encoding: utf8).replaceAll('%20', '+');
      return '$k=$v';
    }).join('&');
  }

  String _hmacHex(String payload) {
    final digest = Hmac(sha256, utf8.encode(apiSecret.trim()))
        .convert(utf8.encode(payload));
    return digest.toString();
  }

  String _compact(String symbol) =>
      symbol.toUpperCase().replaceAll('_', '').replaceAll('-', '');

  Future<void> syncServerTime() async {
    try {
      final uri = Uri.parse('${hosts.first}/r/api/v1/time');
      final res = await _client
          .get(uri, headers: {
            'Accept': 'application/json',
            'User-Agent': 'SignalYab-Phone/1.4',
          })
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final raw = jsonDecode(res.body);
        final server = int.tryParse(
            '${raw is Map ? (raw['serverTime'] ?? raw['time'] ?? '') : ''}');
        if (server != null && server > 0) {
          _serverOffsetMs = server - DateTime.now().millisecondsSinceEpoch;
        }
      }
    } catch (_) {}
  }

  int _timestampMs() =>
      DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  Future<Map<String, dynamic>> _signed({
    required String method,
    required String path,
    Map<String, String>? body,
  }) async {
    Object? lastErr;
    for (final host in hosts) {
      try {
        final params = <String, String>{};
        if (body != null) {
          for (final e in body.entries) {
            params[e.key] = e.value;
          }
        }
        params['timestamp'] = '${_timestampMs()}';
        params['recvWindow'] = '60000';

        final dataQuery = _urlEncode(params);
        final signature = _hmacHex(dataQuery);
        final fullQuery = '$dataQuery&signature=$signature';

        final headers = {
          'X-MBX-APIKEY': apiKey.trim(),
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'SignalYab-Phone/1.4',
        };

        late http.Response res;
        if (method == 'POST') {
          res = await _client
              .post(
                Uri.parse('$host$path'),
                headers: headers,
                body: fullQuery,
              )
              .timeout(const Duration(seconds: 25));
        } else {
          res = await _client
              .get(
                Uri.parse('$host$path?$fullQuery'),
                headers: headers,
              )
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
          if ('$msg'.toLowerCase().contains('signature') ||
              '$msg'.contains('1103')) {
            await syncServerTime();
          }
          continue;
        }
        return decoded;
      } catch (e) {
        lastErr = e;
      }
    }
    throw StateError('اتصال/سفارش تبدیل ناموفق: $lastErr');
  }

  Future<Map<String, dynamic>> marketOrder({
    required String symbol,
    required String side,
    required double quantity,
  }) async {
    await syncServerTime();
    final compact = _compact(symbol);
    return _signed(
      method: 'POST',
      path: '/api/v1/order',
      body: {
        'side': side.toUpperCase(),
        'type': 'MARKET',
        'quantity': _qty(quantity),
        'price': '0',
        'stopPrice': '0',
        'symbol': compact,
      },
    );
  }

  Future<Map<String, dynamic>> account() async {
    await syncServerTime();
    return _signed(method: 'GET', path: '/r/api/v1/account');
  }

  Future<AccountSnapshot> accountSnapshot() async {
    try {
      final raw = await account();
      return AccountSnapshot.fromApi(raw);
    } catch (e) {
      return AccountSnapshot.unavailable('$e');
    }
  }

  Future<Map<String, dynamic>> openOrders({String? symbol}) async {
    await syncServerTime();
    final body = <String, String>{};
    if (symbol != null) {
      body['symbol'] = _compact(symbol);
    }
    return _signed(method: 'GET', path: '/r/api/v1/openOrders', body: body);
  }

  Future<Map<String, dynamic>> getOrder({
    required String symbol,
    required int orderId,
  }) async {
    await syncServerTime();
    return _signed(
      method: 'GET',
      path: '/r/api/v1/order',
      body: {
        'symbol': _compact(symbol),
        'orderId': '$orderId',
      },
    );
  }

  String _qty(double q) {
    if (q >= 1) return q.toStringAsFixed(4);
    if (q >= 0.01) return q.toStringAsFixed(6);
    return q.toStringAsFixed(8);
  }

  void dispose() => _client.close();
}
