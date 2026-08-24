import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'account_balance.dart';

/// Signed Tabdeal client — Spot + official Futures (FAPI) endpoints only.
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
        } else if (method == 'DELETE') {
          res = await _client
              .delete(
                Uri.parse('$host$path?$fullQuery'),
                headers: headers,
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

  // ─── Official Futures (FAPI) — docs.tabdeal.org ───

  Future<Map<String, dynamic>> futuresBalance() async {
    await syncServerTime();
    return _signed(method: 'GET', path: '/r/fapi/v3/balance');
  }

  Future<FuturesBalanceSnapshot> futuresBalanceSnapshot() async {
    try {
      final raw = await futuresBalance();
      final code = raw['code'];
      final msg = '${raw['msg'] ?? raw['message'] ?? ''}'.toLowerCase();
      if (code == 1207 ||
          msg.contains('futures not active') ||
          msg.contains('not active')) {
        return FuturesBalanceSnapshot.notActive();
      }
      return FuturesBalanceSnapshot.fromApi(raw);
    } catch (e) {
      final s = '$e'.toLowerCase();
      if (s.contains('1207') || s.contains('futures not active')) {
        return FuturesBalanceSnapshot.notActive();
      }
      return FuturesBalanceSnapshot.unavailable('$e');
    }
  }

  Future<Map<String, dynamic>> futuresAccount() async {
    await syncServerTime();
    return _signed(method: 'GET', path: '/r/fapi/v3/account');
  }

  Future<dynamic> futuresPositionRisk({String? symbol}) async {
    await syncServerTime();
    final body = <String, String>{};
    if (symbol != null && symbol.isNotEmpty) {
      body['symbol'] = _compact(symbol);
    }
    return _signed(method: 'GET', path: '/r/fapi/v3/positionRisk', body: body);
  }

  Future<FuturesPositionsSnapshot> futuresPositionsSnapshot(
      {String? symbol}) async {
    try {
      final raw = await futuresPositionRisk(symbol: symbol);
      if (raw is Map) {
        final code = raw['code'];
        final msg = '${raw['msg'] ?? raw['message'] ?? ''}'.toLowerCase();
        if (code == 1207 || msg.contains('futures not active')) {
          return FuturesPositionsSnapshot.notActive();
        }
      }
      return FuturesPositionsSnapshot.fromApi(raw);
    } catch (e) {
      final s = '$e'.toLowerCase();
      if (s.contains('1207') || s.contains('futures not active')) {
        return FuturesPositionsSnapshot.notActive();
      }
      return FuturesPositionsSnapshot.unavailable('$e');
    }
  }

  Future<Map<String, dynamic>> changeLeverage({
    required String symbol,
    required int leverage,
  }) async {
    if (leverage < 1) throw StateError('leverage must be >= 1');
    await syncServerTime();
    return _signed(method: 'POST', path: '/fapi/v1/leverage', body: {
      'symbol': _compact(symbol),
      'leverage': '$leverage',
    });
  }

  /// type=2 Spot→Futures, type=1 Futures→Spot
  Future<Map<String, dynamic>> transfer({
    required int type,
    required String asset,
    required double amount,
  }) async {
    if (type != 1 && type != 2) throw StateError('transfer type must be 1 or 2');
    if (amount <= 0) throw StateError('transfer amount must be > 0');
    await syncServerTime();
    return _signed(method: 'POST', path: '/fapi/v1/transfer', body: {
      'type': '$type',
      'asset': asset.toUpperCase(),
      'amount': _qty(amount),
    });
  }

  Future<Map<String, dynamic>> futuresMarketOrder({
    required String symbol,
    required String side,
    required double quantity,
  }) async {
    await syncServerTime();
    return _signed(method: 'POST', path: '/fapi/v1/order', body: {
      'symbol': _compact(symbol),
      'side': side.toUpperCase(),
      'type': 'MARKET',
      'quantity': _qty(quantity),
    });
  }

  Future<Map<String, dynamic>> futuresGetOrder({
    required String symbol,
    required int orderId,
  }) async {
    await syncServerTime();
    return _signed(method: 'GET', path: '/r/fapi/v1/order', body: {
      'symbol': _compact(symbol),
      'orderId': '$orderId',
    });
  }

  Future<Map<String, dynamic>> futuresOpenOrders({String? symbol}) async {
    await syncServerTime();
    final body = <String, String>{};
    if (symbol != null) body['symbol'] = _compact(symbol);
    return _signed(method: 'GET', path: '/r/fapi/v1/openOrders', body: body);
  }

  /// Official: POST /fapi/v1/positionSlTp
  Future<Map<String, dynamic>> futuresPositionSlTp({
    required int positionId,
    required String symbol,
    double? slPrice,
    double? tpPrice,
    String workingType = 'MARK_PRICE',
  }) async {
    if (slPrice == null && tpPrice == null) {
      throw StateError('at least one of slPrice or tpPrice required');
    }
    await syncServerTime();
    final body = <String, String>{
      'positionId': '$positionId',
      'symbol': _compact(symbol),
      'workingType': workingType,
    };
    if (slPrice != null) body['slPrice'] = _qty(slPrice);
    if (tpPrice != null) body['tpPrice'] = _qty(tpPrice);
    return _signed(method: 'POST', path: '/fapi/v1/positionSlTp', body: body);
  }

  /// Official: DELETE /fapi/v1/position
  Future<Map<String, dynamic>> futuresClosePosition(
      {required String symbol}) async {
    await syncServerTime();
    return _signed(method: 'DELETE', path: '/fapi/v1/position', body: {
      'symbol': _compact(symbol),
    });
  }

  String _qty(double q) {
    if (q >= 1) return q.toStringAsFixed(4);
    if (q >= 0.01) return q.toStringAsFixed(6);
    return q.toStringAsFixed(8);
  }

  void dispose() => _client.close();
}
