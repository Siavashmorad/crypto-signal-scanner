import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_data.dart';

class TabdealApiException implements Exception {
  final String message;
  const TabdealApiException(this.message);
  @override
  String toString() => message;
}

class TabdealApi {
  /// Official + fallback hosts (some networks block one).
  static const hosts = <String>[
    'https://api1.tabdeal.org',
    'https://api.tabdeal.org',
  ];

  final http.Client client;
  final Duration timeout;
  String _activeHost = hosts.first;

  TabdealApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : client = client ?? http.Client();

  String get activeHost => _activeHost;

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    Object? lastError;
    for (final host in hosts) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final uri = Uri.parse('$host$path').replace(queryParameters: query);
        try {
          final response = await client
              .get(uri, headers: const {
                'Accept': 'application/json',
                'User-Agent': 'SignalYab/1.0',
              })
              .timeout(timeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = TabdealApiException('HTTP ${response.statusCode} @ $host');
            continue;
          }
          _activeHost = host;
          return jsonDecode(response.body);
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw TabdealApiException(
      'اتصال به تبدیل برقرار نشد. اینترنت را چک کنید. جزئیات: $lastError',
    );
  }

  /// Quick connectivity check used by the home screen.
  Future<bool> ping() async {
    try {
      await _get('/r/api/v1/ping');
      return true;
    } catch (_) {
      try {
        await _get('/r/api/v1/time');
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<List<String>> activeUsdtSymbols({int maxSymbols = 40}) async {
    final payload = await _get('/r/api/v1/exchangeInfo');
    final raw = payload is Map<String, dynamic>
        ? (payload['symbols'] ?? payload['data'] ?? payload)
        : payload;
    if (raw is! List) {
      throw const TabdealApiException('پاسخ exchangeInfo نامعتبر است');
    }

    const priority = <String>[
      'BTCUSDT',
      'ETHUSDT',
      'BNBUSDT',
      'SOLUSDT',
      'XRPUSDT',
      'DOGEUSDT',
      'ADAUSDT',
      'TRXUSDT',
      'TONUSDT',
      'AVAXUSDT',
      'LINKUSDT',
      'DOTUSDT',
      'MATICUSDT',
      'LTCUSDT',
      'BCHUSDT',
      'NEARUSDT',
      'APTUSDT',
      'ARBUSDT',
      'OPUSDT',
      'SUIUSDT',
    ];

    final found = <String>{};
    for (final item in raw) {
      if (item is String) {
        final symbol = item.toUpperCase().replaceAll('_', '');
        if (symbol.endsWith('USDT')) found.add(symbol);
      } else if (item is Map) {
        final symbol =
            '${item['symbol'] ?? item['name'] ?? ''}'.toUpperCase().replaceAll('_', '');
        final status = '${item['status'] ?? 'TRADING'}'.toUpperCase();
        if (symbol.endsWith('USDT') &&
            (status == 'TRADING' ||
                status == 'ACTIVE' ||
                !item.containsKey('status'))) {
          found.add(symbol);
        }
      }
    }

    final ordered = <String>[];
    for (final p in priority) {
      if (found.contains(p)) ordered.add(p);
    }
    for (final s in (found.toList()..sort())) {
      if (!ordered.contains(s)) ordered.add(s);
      if (ordered.length >= maxSymbols) break;
    }
    return ordered.take(maxSymbols).toList();
  }

  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) async {
    final payload = await _get('/r/api/v1/trades', {
      'symbol': symbol,
      'limit': '$limit',
    });
    if (payload is! List) {
      throw const TabdealApiException('پاسخ trades نامعتبر است');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <TradePoint>[];
    for (final item in payload) {
      dynamic price, quantity, timestamp;
      if (item is List && item.length >= 2) {
        price = item[0];
        quantity = item[1];
        timestamp = item.length >= 3 ? item[2] : now;
      } else if (item is Map) {
        price = item['price'];
        quantity = item['qty'] ?? item['quantity'];
        timestamp = item['time'] ?? item['timestamp'] ?? now;
      }
      final p = double.tryParse('$price');
      final q = double.tryParse('$quantity');
      final t = int.tryParse('$timestamp') ?? now;
      if (p != null && q != null && p > 0 && q >= 0) {
        result.add(TradePoint(price: p, quantity: q, timestampMs: t));
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> depth(String symbol) async {
    final payload = await _get('/r/api/v1/depth', {
      'symbol': symbol,
      'limit': '20',
    });
    if (payload is! Map) {
      throw const TabdealApiException('پاسخ depth نامعتبر است');
    }
    return Map<String, dynamic>.from(payload);
  }
}
