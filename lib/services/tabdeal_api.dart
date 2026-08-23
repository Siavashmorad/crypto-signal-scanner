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
  /// Hosts used by official SDK / docs.
  static const hosts = <String>[
    'https://api1.tabdeal.org',
    'https://api.tabdeal.org',
  ];

  /// Fallback liquid pairs if exchangeInfo is slow/blocked (IRT is primary on Tabdeal).
  static const fallbackSymbols = <String>[
    'BTCIRT',
    'ETHIRT',
    'USDTIRT',
    'BNIRT',
    'SOLIRT',
    'XRPIRT',
    'DOGEIRT',
    'ADAIRT',
    'TRXIRT',
    'TONIRT',
    'BTCUSDT',
    'ETHUSDT',
    'BNBUSDT',
    'SOLUSDT',
    'XRPUSDT',
    'DOGEUSDT',
  ];

  final http.Client client;
  final Duration timeout;
  String _activeHost = hosts.first;
  String? lastErrorDetail;

  TabdealApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 18),
  }) : client = client ?? http.Client();

  String get activeHost => _activeHost;

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    Object? lastError;
    for (final host in hosts) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final uri = Uri.parse('$host$path').replace(queryParameters: query);
        try {
          final response = await client
              .get(
                uri,
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13) SignalYab/1.1',
                },
              )
              .timeout(timeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError =
                'HTTP ${response.statusCode} @ $host path=$path body=${response.body.length > 120 ? response.body.substring(0, 120) : response.body}';
            continue;
          }
          _activeHost = host;
          lastErrorDetail = null;
          if (response.body.isEmpty) return <String, dynamic>{};
          return jsonDecode(response.body);
        } catch (e) {
          lastError = '$e @ $host$path';
        }
      }
    }
    lastErrorDetail = '$lastError';
    throw TabdealApiException(
      'اتصال به API تبدیل برقرار نشد.\n'
      '۱) اینترنت موبایل/وای‌فای را چک کنید\n'
      '۲) اگر خارج ایران هستید ممکن است API بلاک باشد\n'
      'جزئیات: $lastError',
    );
  }

  Future<bool> ping() async {
    try {
      await _get('/r/api/v1/time');
      return true;
    } catch (_) {
      try {
        await _get('/r/api/v1/ping');
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Normalize Tabdeal symbols: BTC_IRT → BTCIRT, keep USDT/IRT pairs.
  String normalizeSymbol(String raw) {
    return raw.toUpperCase().replaceAll('_', '').replaceAll('-', '');
  }

  Future<List<String>> activeUsdtSymbols({int maxSymbols = 40}) async {
    try {
      final payload = await _get('/r/api/v1/exchangeInfo');
      final raw = payload is Map<String, dynamic>
          ? (payload['symbols'] ?? payload['data'] ?? payload)
          : payload;
      if (raw is! List) {
        return fallbackSymbols.take(maxSymbols).toList();
      }

      const priority = <String>[
        'BTCIRT',
        'ETHIRT',
        'USDTIRT',
        'BTCUSDT',
        'ETHUSDT',
        'SOLIRT',
        'BNIRT',
        'XRPIRT',
        'DOGEIRT',
        'TRXIRT',
        'SOLUSDT',
        'BNBUSDT',
      ];

      final found = <String>{};
      for (final item in raw) {
        String symbol = '';
        String status = 'TRADING';
        if (item is String) {
          symbol = normalizeSymbol(item);
        } else if (item is Map) {
          symbol = normalizeSymbol(
              '${item['symbol'] ?? item['tabdealSymbol'] ?? item['name'] ?? ''}');
          status = '${item['status'] ?? 'TRADING'}'.toUpperCase();
        }
        if (symbol.isEmpty) continue;
        final okQuote = symbol.endsWith('IRT') ||
            symbol.endsWith('USDT') ||
            symbol.endsWith('TMN');
        if (!okQuote) continue;
        if (status == 'TRADING' ||
            status == 'ACTIVE' ||
            status == 'BREAK' ||
            status.isEmpty) {
          found.add(symbol);
        }
      }

      if (found.isEmpty) {
        return fallbackSymbols.take(maxSymbols).toList();
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
    } catch (_) {
      // Soft fallback so scan can still try known liquid markets.
      return fallbackSymbols.take(maxSymbols).toList();
    }
  }

  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) async {
    final sym = normalizeSymbol(symbol);
    // Try symbol= then tabdealSymbol=
    Object? err;
    for (final q in [
      {'symbol': sym, 'limit': '$limit'},
      {
        'tabdealSymbol': _toTabdealSymbol(sym),
        'limit': '$limit',
      },
    ]) {
      try {
        final payload = await _get('/r/api/v1/trades', q);
        if (payload is! List) continue;
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
          final qq = double.tryParse('$quantity');
          final t = int.tryParse('$timestamp') ?? now;
          if (p != null && qq != null && p > 0 && qq >= 0) {
            result.add(TradePoint(price: p, quantity: qq, timestampMs: t));
          }
        }
        if (result.isNotEmpty) return result;
      } catch (e) {
        err = e;
      }
    }
    throw TabdealApiException('trades failed for $sym: $err');
  }

  Future<Map<String, dynamic>> depth(String symbol) async {
    final sym = normalizeSymbol(symbol);
    for (final q in [
      {'symbol': sym, 'limit': '20'},
      {'tabdealSymbol': _toTabdealSymbol(sym), 'limit': '20'},
    ]) {
      try {
        final payload = await _get('/r/api/v1/depth', q);
        if (payload is Map) return Map<String, dynamic>.from(payload);
      } catch (_) {}
    }
    return {'bids': [], 'asks': []};
  }

  /// BTCIRT → BTC_IRT , BTCUSDT → BTC_USDT
  String _toTabdealSymbol(String compact) {
    final s = normalizeSymbol(compact);
    for (final q in ['USDT', 'IRT', 'TMN']) {
      if (s.endsWith(q) && s.length > q.length) {
        return '${s.substring(0, s.length - q.length)}_$q';
      }
    }
    return s;
  }
}
