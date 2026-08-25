import 'dart:convert';

import 'package:http/http.dart' as http;

/// One TradingView alert accepted by the SignalYab webhook backend.
/// Never invents indicator values — only fields present on the wire.
class TradingViewAlert {
  final String symbol;
  final String signal; // LONG | SHORT
  final String exchange;
  final String timeframe;
  final double? price;
  final int timestampMs;
  final double? volume;
  final Map<String, double> indicators;
  final String fingerprint;
  final bool stale;

  const TradingViewAlert({
    required this.symbol,
    required this.signal,
    this.exchange = '',
    this.timeframe = '',
    this.price,
    this.timestampMs = 0,
    this.volume,
    this.indicators = const {},
    this.fingerprint = '',
    this.stale = false,
  });

  factory TradingViewAlert.fromJson(Map<String, dynamic> j) {
    final ind = <String, double>{};
    final raw = j['indicators'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num) ind['${e.key}'] = v.toDouble();
      }
    }
    return TradingViewAlert(
      symbol: '${j['symbol'] ?? ''}'.toUpperCase(),
      signal: '${j['signal'] ?? ''}'.toUpperCase(),
      exchange: '${j['exchange'] ?? ''}',
      timeframe: '${j['timeframe'] ?? ''}',
      price: (j['price'] is num) ? (j['price'] as num).toDouble() : null,
      timestampMs: (j['timestamp_ms'] is num)
          ? (j['timestamp_ms'] as num).toInt()
          : 0,
      volume: (j['volume'] is num) ? (j['volume'] as num).toDouble() : null,
      indicators: ind,
      fingerprint: '${j['fingerprint'] ?? ''}',
      stale: j['stale'] == true,
    );
  }

  bool get isActionable =>
      !stale &&
      (signal == 'LONG' || signal == 'SHORT') &&
      symbol.length >= 3;
}

/// Polls owner-authenticated backend for recent TradingView alerts.
/// Does NOT place orders. Backend webhook is the public intake.
class TradingViewSignalService {
  TradingViewSignalService({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    http.Client? client,
  }) : client = client ?? http.Client();

  /// e.g. https://crypto-signal-scanner-api.onrender.com
  String baseUrl;
  String username;
  String password;
  final http.Client client;
  bool enabled = false;

  Uri? _uri(String path, [Map<String, String>? q]) {
    final b = baseUrl.trim();
    if (b.isEmpty) return null;
    final root = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    return Uri.parse('$root$path').replace(queryParameters: q);
  }

  Map<String, String> get _authHeaders {
    if (username.isEmpty || password.isEmpty) return {};
    final token = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $token', 'Accept': 'application/json'};
  }

  /// Fetch fresh alerts. Returns empty on misconfig / network — never fakes.
  Future<List<TradingViewAlert>> fetchAlerts({int limit = 20}) async {
    if (!enabled) return const [];
    final uri = _uri('/webhook/tradingview/alerts', {
      'limit': '$limit',
      'only_fresh': 'true',
    });
    if (uri == null) return const [];
    try {
      final res = await client
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final body = jsonDecode(res.body);
      if (body is! Map) return const [];
      final list = body['alerts'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => TradingViewAlert.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.isActionable)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    client.close();
  }
}
