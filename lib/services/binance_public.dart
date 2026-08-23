import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_data.dart';

/// Public Binance market data — used only when Tabdeal is unreachable.
/// Trading still goes only to Tabdeal when keys work.
class BinancePublic {
  static const base = 'https://api.binance.com';
  final http.Client client;
  BinancePublic({http.Client? client}) : client = client ?? http.Client();

  Future<bool> ping() async {
    try {
      final res = await client
          .get(Uri.parse('$base/api/v3/ping'))
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<TradePoint>> trades(String symbol, {int limit = 200}) async {
    final sym = symbol.toUpperCase().replaceAll('_', '');
    // Map IRT pairs to USDT for global data fallback
    final mapped = sym.endsWith('IRT')
        ? '${sym.substring(0, sym.length - 3)}USDT'
        : sym;
    final uri = Uri.parse('$base/api/v3/trades').replace(queryParameters: {
      'symbol': mapped,
      'limit': '$limit',
    });
    final res = await client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Binance HTTP ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return TradePoint(
        price: double.parse('${m['price']}'),
        quantity: double.parse('${m['qty']}'),
        timestampMs: (m['time'] as num).toInt(),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> depth(String symbol) async {
    final sym = symbol.toUpperCase().replaceAll('_', '');
    final mapped = sym.endsWith('IRT')
        ? '${sym.substring(0, sym.length - 3)}USDT'
        : sym;
    final uri = Uri.parse('$base/api/v3/depth').replace(queryParameters: {
      'symbol': mapped,
      'limit': '20',
    });
    final res = await client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return {'bids': [], 'asks': []};
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }
}
