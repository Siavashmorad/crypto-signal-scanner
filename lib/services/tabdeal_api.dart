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
    'BCHUSDT',
  ];

  final http.Client client;
  final Duration timeout;
  String _activeHost = hosts.first;
  String? lastErrorDetail;

  /// Cached futures symbols from official FAPI exchangeInfo.
  List<String>? _futuresSymbolCache;
  DateTime? _futuresSymbolCacheAt;

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
      'جزئیات فنی: $lastError',
    );
  }

  Future<dynamic> rawExchangeInfo() => _get('/r/api/v1/exchangeInfo');

  /// Official FAPI: GET /r/fapi/v1/exchangeInfo [NONE]
  Future<dynamic> futuresExchangeInfo() => _get('/r/fapi/v1/exchangeInfo');

  Future<List<HostProbeResult>> diagnose() async {
    final results = <HostProbeResult>[];
    const paths = [
      '/r/api/v1/time',
      '/r/api/v1/ping',
      '/r/fapi/v1/ping',
      '/r/fapi/v1/time',
    ];
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

  /// Active Futures symbols from official FAPI exchangeInfo (cached ~10m).
  Future<List<String>> activeFuturesSymbols({int maxSymbols = 40}) async {
    final now = DateTime.now();
    if (_futuresSymbolCache != null &&
        _futuresSymbolCacheAt != null &&
        now.difference(_futuresSymbolCacheAt!) < const Duration(minutes: 10)) {
      return _futuresSymbolCache!.take(maxSymbols).toList();
    }
    try {
      final payload = await futuresExchangeInfo();
      final raw = payload is Map
          ? (payload['symbols'] ?? payload['data'] ?? payload)
          : payload;
      if (raw is! List) {
        return activeUsdtSymbols(maxSymbols: maxSymbols);
      }
      final found = <String>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final status =
            '${item['status'] ?? item['contractStatus'] ?? 'TRADING'}'
                .toUpperCase();
        if (status.contains('BREAK') ||
            status.contains('HALT') ||
            status == 'INACTIVE') {
          continue;
        }
        final symbol = normalizeSymbol(
            '${item['symbol'] ?? item['tabdealSymbol'] ?? item['name'] ?? ''}');
        if (symbol.isEmpty) continue;
        if (symbol.endsWith('USDT') ||
            symbol.endsWith('IRT') ||
            symbol.endsWith('TMN')) {
          found.add(symbol);
        }
      }
      if (found.isEmpty) return activeUsdtSymbols(maxSymbols: maxSymbols);
      final ordered = <String>[];
      for (final p in fallbackSymbols) {
        if (found.contains(p)) ordered.add(p);
      }
      for (final s in found) {
        if (!ordered.contains(s)) ordered.add(s);
        if (ordered.length >= maxSymbols) break;
      }
      _futuresSymbolCache = ordered;
      _futuresSymbolCacheAt = now;
      return ordered.take(maxSymbols).toList();
    } catch (_) {
      return activeUsdtSymbols(maxSymbols: maxSymbols);
    }
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

  /// Official FAPI depth: GET /r/fapi/v1/depth [NONE]
  Future<Map<String, dynamic>> futuresDepth(String symbol,
      {int limit = 20}) async {
    final sym = normalizeSymbol(symbol);
    for (final q in [
      {'symbol': sym, 'limit': '$limit'},
      {'tabdealSymbol': toTabdealSymbol(sym), 'limit': '$limit'},
    ]) {
      try {
        final payload = await _get('/r/fapi/v1/depth', q);
        if (payload is Map &&
            ((payload['bids'] is List && (payload['bids'] as List).isNotEmpty) ||
                (payload['asks'] is List &&
                    (payload['asks'] as List).isNotEmpty))) {
          return Map<String, dynamic>.from(payload);
        }
      } catch (_) {}
    }
    return depth(symbol);
  }

  /// Build OHLCV candles from real trades (Tabdeal has no public kline in spot docs).
  List<Candle> candlesFromTrades(List<TradePoint> trades, Duration tf) {
    if (trades.isEmpty) return const [];
    final sorted = [...trades]
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final bucketMs = tf.inMilliseconds;
    final map = <int, Candle>{};
    for (final t in sorted) {
      final b = t.timestampMs - (t.timestampMs % bucketMs);
      final c = map[b];
      if (c == null) {
        map[b] = Candle(
          timestampMs: b,
          open: t.price,
          high: t.price,
          low: t.price,
          close: t.price,
          volume: t.quantity,
        );
      } else {
        map[b] = Candle(
          timestampMs: b,
          open: c.open,
          high: t.price > c.high ? t.price : c.high,
          low: t.price < c.low ? t.price : c.low,
          close: t.price,
          volume: c.volume + t.quantity,
        );
      }
    }
    return map.values.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }
}
