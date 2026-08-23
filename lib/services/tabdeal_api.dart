import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_data.dart';

class TabdealApiException implements Exception {
  final String message;
  const TabdealApiException(this.message);
  @override
  String toString() => message;
}

class HostProbeResult {
  final String host;
  final String path;
  final bool ok;
  final String detail;
  final int ms;
  HostProbeResult({
    required this.host,
    required this.path,
    required this.ok,
    required this.detail,
    required this.ms,
  });
}

class TabdealApi {
  static const hosts = <String>[
    'https://api1.tabdeal.org',
    'https://api.tabdeal.org',
  ];

  static const fallbackSymbols = <String>[
    'BTCIRT',
    'ETHIRT',
    'USDTIRT',
    'SOLIRT',
    'XRPIRT',
    'DOGEIRT',
    'TRXIRT',
    'ADAIRT',
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'BNBUSDT',
  ];

  final http.Client client;
  final Duration timeout;
  String _activeHost = hosts.first;
  String? lastErrorDetail;

  TabdealApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : client = client ?? http.Client();

  String get activeHost => _activeHost;

  Map<String, String> get _headers => const {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'fa-IR,fa;q=0.9,en;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
      };

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    Object? lastError;
    for (final host in hosts) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final uri = Uri.parse('$host$path').replace(queryParameters: query);
        try {
          final response =
              await client.get(uri, headers: _headers).timeout(timeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError =
                'HTTP ${response.statusCode} $host$path (${response.body.length}b)';
            continue;
          }
          _activeHost = host;
          lastErrorDetail = null;
          if (response.body.isEmpty) return <String, dynamic>{};
          return jsonDecode(response.body);
        } catch (e) {
          lastError = e;
        }
      }
    }
    lastErrorDetail = '$lastError';
    throw TabdealApiException(
      'API تبدیل در دسترس نیست.\n'
      '• اینترنت ایران (نه VPN خارجی)\n'
      '• داده موبایل را یک‌بار خاموش/روشن کنید\n'
      '• در تنظیمات DNS را روی خودکار بگذارید\n'
      'جزئیات فنی: $lastError',
    );
  }

  /// Diagnose every host — shown in UI so user sees exact failure.
  Future<List<HostProbeResult>> diagnose() async {
    final results = <HostProbeResult>[];
    const paths = ['/r/api/v1/time', '/r/api/v1/ping'];
    for (final host in hosts) {
      for (final path in paths) {
        final started = DateTime.now();
        try {
          final uri = Uri.parse('$host$path');
          final res =
              await client.get(uri, headers: _headers).timeout(timeout);
          final ms = DateTime.now().difference(started).inMilliseconds;
          final ok = res.statusCode >= 200 && res.statusCode < 300;
          results.add(HostProbeResult(
            host: host,
            path: path,
            ok: ok,
            detail: ok
                ? 'OK ${res.statusCode} (${res.body.length} bytes)'
                : 'HTTP ${res.statusCode}',
            ms: ms,
          ));
          if (ok) _activeHost = host;
        } catch (e) {
          final ms = DateTime.now().difference(started).inMilliseconds;
          results.add(HostProbeResult(
            host: host,
            path: path,
            ok: false,
            detail: e.toString(),
            ms: ms,
          ));
        }
      }
    }
    return results;
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

  String normalizeSymbol(String raw) =>
      raw.toUpperCase().replaceAll('_', '').replaceAll('-', '');

  String toTabdealSymbol(String compact) {
    final s = normalizeSymbol(compact);
    for (final q in ['USDT', 'IRT', 'TMN']) {
      if (s.endsWith(q) && s.length > q.length) {
        return '${s.substring(0, s.length - q.length)}_$q';
      }
    }
    return s;
  }

  Future<List<String>> activeUsdtSymbols({int maxSymbols = 40}) async {
    try {
      final payload = await _get('/r/api/v1/exchangeInfo');
      final raw = payload is Map
          ? (payload['symbols'] ?? payload['data'] ?? payload)
          : payload;
      if (raw is! List) return fallbackSymbols.take(maxSymbols).toList();

      final found = <String>{};
      for (final item in raw) {
        String symbol = '';
        if (item is String) {
          symbol = normalizeSymbol(item);
        } else if (item is Map) {
          symbol = normalizeSymbol(
              '${item['symbol'] ?? item['tabdealSymbol'] ?? item['name'] ?? ''}');
        }
        if (symbol.endsWith('IRT') ||
            symbol.endsWith('USDT') ||
            symbol.endsWith('TMN')) {
          found.add(symbol);
        }
      }
      if (found.isEmpty) return fallbackSymbols.take(maxSymbols).toList();

      final ordered = <String>[];
      for (final p in fallbackSymbols) {
        if (found.contains(p)) ordered.add(p);
      }
      for (final s in found) {
        if (!ordered.contains(s)) ordered.add(s);
        if (ordered.length >= maxSymbols) break;
      }
      return ordered.take(maxSymbols).toList();
    } catch (_) {
      return fallbackSymbols.take(maxSymbols).toList();
    }
  }

  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) async {
    final sym = normalizeSymbol(symbol);
    Object? err;
    for (final q in [
      {'symbol': sym, 'limit': '$limit'},
      {'tabdealSymbol': toTabdealSymbol(sym), 'limit': '$limit'},
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
          if (p != null && qq != null && p > 0) {
            result.add(TradePoint(price: p, quantity: qq, timestampMs: t));
          }
        }
        if (result.isNotEmpty) return result;
      } catch (e) {
        err = e;
      }
    }
    throw TabdealApiException('trades $sym: $err');
  }

  Future<Map<String, dynamic>> depth(String symbol) async {
    final sym = normalizeSymbol(symbol);
    for (final q in [
      {'symbol': sym, 'limit': '20'},
      {'tabdealSymbol': toTabdealSymbol(sym), 'limit': '20'},
    ]) {
      try {
        final payload = await _get('/r/api/v1/depth', q);
        if (payload is Map) return Map<String, dynamic>.from(payload);
      } catch (_) {}
    }
    return {'bids': [], 'asks': []};
  }
}
