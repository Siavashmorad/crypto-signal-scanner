import 'dart:convert';

import 'package:http/http.dart' as http;

/// Read-only client for an MT5 bridge/backend.
///
/// Expected bridge contract (JSON):
/// GET  /health -> {"ok":true}
/// POST /session -> {"token":"..."} (optional token flow)
/// GET  /account -> {"balance":...,"equity":...,"margin":...}
/// GET  /positions -> [{"symbol":...,"side":...,"volume":...,"openPrice":...,"sl":...,"tp":...}]
/// GET  /symbols -> ["EURUSD", ...]
/// GET  /bars?symbol=EURUSD&timeframe=H1&limit=100 -> [{"time":...,"open":...,"high":...,"low":...,"close":...,"volume":...}]
///
/// This client intentionally exposes no order/modify/close operation.
class Mt5BridgeClient {
  Mt5BridgeClient({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null && _token!.isNotEmpty)
          'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<bool> health() async {
    final response = await _client.get(_uri('/health'), headers: _headers);
    _ensureOk(response);
    final body = _json(response);
    return body is Map && (body['ok'] == true || body['status'] == 'ok');
  }

  Future<void> authenticate({required String login, required String password}) async {
    final response = await _client.post(
      _uri('/session'),
      headers: _headers,
      body: jsonEncode({'login': login, 'password': password}),
    );
    _ensureOk(response);
    final body = _json(response);
    if (body is Map && body['token'] is String) {
      _token = body['token'] as String;
    }
  }

  Future<Mt5AccountSnapshot> account() async {
    final response = await _client.get(_uri('/account'), headers: _headers);
    _ensureOk(response);
    final body = _json(response);
    if (body is! Map) throw const Mt5BridgeException('پاسخ حساب MT5 نامعتبر است');
    return Mt5AccountSnapshot(
      balance: _number(body['balance']),
      equity: _number(body['equity']),
      margin: _number(body['margin']),
    );
  }

  Future<List<Mt5PositionSnapshot>> positions() async {
    final response = await _client.get(_uri('/positions'), headers: _headers);
    _ensureOk(response);
    final body = _json(response);
    if (body is! List) throw const Mt5BridgeException('پاسخ پوزیشن‌های MT5 نامعتبر است');
    return body.whereType<Map>().map(Mt5PositionSnapshot.fromJson).toList();
  }

  Future<List<String>> symbols() async {
    final response = await _client.get(_uri('/symbols'), headers: _headers);
    _ensureOk(response);
    final body = _json(response);
    if (body is! List) throw const Mt5BridgeException('پاسخ نمادهای MT5 نامعتبر است');
    return body.whereType<String>().toList(growable: false);
  }

  Future<List<Mt5BarSnapshot>> bars({
    required String symbol,
    required String timeframe,
    int limit = 100,
  }) async {
    final response = await _client.get(
      _uri('/bars', {
        'symbol': symbol,
        'timeframe': timeframe,
        'limit': '$limit',
      }),
      headers: _headers,
    );
    _ensureOk(response);
    final body = _json(response);
    if (body is! List) throw const Mt5BridgeException('پاسخ کندل‌های MT5 نامعتبر است');
    return body.whereType<Map>().map(Mt5BarSnapshot.fromJson).toList();
  }

  void dispose() => _client.close();

  static Object? _json(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw const Mt5BridgeException('پاسخ JSON از پل MT5 قابل خواندن نیست');
    }
  }

  static void _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Mt5BridgeException('پل MT5 خطای HTTP ${response.statusCode}');
    }
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

class Mt5AccountSnapshot {
  const Mt5AccountSnapshot({required this.balance, required this.equity, required this.margin});
  final double balance;
  final double equity;
  final double margin;
}

class Mt5PositionSnapshot {
  const Mt5PositionSnapshot({
    required this.symbol,
    required this.side,
    required this.volume,
    required this.openPrice,
    this.stopLoss,
    this.takeProfit,
  });

  final String symbol;
  final String side;
  final double volume;
  final double openPrice;
  final double? stopLoss;
  final double? takeProfit;

  factory Mt5PositionSnapshot.fromJson(Map data) => Mt5PositionSnapshot(
        symbol: '${data['symbol'] ?? ''}',
        side: '${data['side'] ?? ''}',
        volume: Mt5BridgeClient._number(data['volume']),
        openPrice: Mt5BridgeClient._number(data['openPrice'] ?? data['price']),
        stopLoss: data['sl'] == null ? null : Mt5BridgeClient._number(data['sl']),
        takeProfit: data['tp'] == null ? null : Mt5BridgeClient._number(data['tp']),
      );
}

class Mt5BarSnapshot {
  const Mt5BarSnapshot({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  factory Mt5BarSnapshot.fromJson(Map data) => Mt5BarSnapshot(
        time: DateTime.tryParse('${data['time']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        open: Mt5BridgeClient._number(data['open']),
        high: Mt5BridgeClient._number(data['high']),
        low: Mt5BridgeClient._number(data['low']),
        close: Mt5BridgeClient._number(data['close']),
        volume: Mt5BridgeClient._number(data['volume']),
      );
}

class Mt5BridgeException implements Exception {
  const Mt5BridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}
