import 'dart:async';
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
  static const baseUrl = 'https://api1.tabdeal.org';
  final http.Client client;
  final Duration timeout;
  final int maxAttempts;

  TabdealApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.maxAttempts = 3,
  })  : client = client ?? http.Client(),
        assert(maxAttempts > 0);

  Future<dynamic> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await client
            .get(
              uri,
              headers: const {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            return jsonDecode(response.body);
          } on FormatException catch (e) {
            throw TabdealApiException('Invalid JSON from Tabdeal: $e');
          }
        }

        final retryable = response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!retryable || attempt == maxAttempts) {
          throw TabdealApiException('HTTP ${response.statusCode}');
        }
        lastError = TabdealApiException('HTTP ${response.statusCode}');
      } on TabdealApiException catch (e) {
        if (e.message.startsWith('HTTP ') && attempt < maxAttempts) {
          lastError = e;
        } else {
          rethrow;
        }
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }

    throw TabdealApiException('Network/API error after $maxAttempts attempts: $lastError');
  }

  Future<List<String>> activeUsdtSymbols() async {
    final payload = await _get('/r/api/v1/exchangeInfo');
    dynamic raw = payload;
    if (payload is Map<String, dynamic>) {
      raw = payload['symbols'] ?? payload['data'] ?? payload;
      if (raw is Map) {
        raw = raw['symbols'] ?? raw['data'] ?? raw;
      }
    }
    if (raw is! List) {
      throw const TabdealApiException('Unexpected exchangeInfo response');
    }

    final symbols = <String>{};
    for (final item in raw) {
      if (item is String) {
        final symbol = item.trim().toUpperCase();
        if (symbol.endsWith('USDT')) symbols.add(symbol);
      } else if (item is Map) {
        final symbol = '${item['symbol'] ?? item['name'] ?? ''}'.trim().toUpperCase();
        final status = '${item['status'] ?? 'TRADING'}'.toUpperCase();
        if (symbol.endsWith('USDT') &&
            (status == 'TRADING' || status == 'ACTIVE' || !item.containsKey('status'))) {
          symbols.add(symbol);
        }
      }
    }

    final result = symbols.toList()..sort();
    if (result.isEmpty) {
      throw const TabdealApiException('No active USDT markets returned by Tabdeal');
    }
    return result;
  }

  Future<List<TradePoint>> trades(String symbol, {int limit = 500}) async {
    final payload = await _get('/r/api/v1/trades', {
      'symbol': symbol,
      'limit': '$limit',
    });
    if (payload is! List) {
      throw const TabdealApiException('Unexpected trades response');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <TradePoint>[];
    for (final item in payload) {
      dynamic price;
      dynamic quantity;
      dynamic timestamp;
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
      'limit': '30',
    });
    if (payload is! Map) {
      throw const TabdealApiException('Unexpected depth response');
    }
    return Map<String, dynamic>.from(payload);
  }

  void dispose() => client.close();
}
