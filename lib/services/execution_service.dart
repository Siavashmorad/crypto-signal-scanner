import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client for approval-gated open/close. Nothing executes without /approve.
class ExecutionService {
  ExecutionService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ??
            const String.fromEnvironment('AI_BACKEND_URL', defaultValue: '');

  final http.Client _client;
  final String baseUrl;

  bool get configured => baseUrl.trim().isNotEmpty;

  Map<String, String> _headers(String username, String password) => {
        'Content-Type': 'application/json',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  Future<Map<String, dynamic>> status({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/status');
    final res = await _client
        .get(uri, headers: _headers(username, password))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('execution status failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> pending({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/pending');
    final res = await _client
        .get(uri, headers: _headers(username, password))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('pending failed: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['pending'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Live mark prices + unrealized PnL; may auto-propose CLOSE on TP/SL.
  Future<Map<String, dynamic>> monitor({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/monitor');
    final res = await _client
        .get(uri, headers: _headers(username, password))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw StateError(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> proposeOpen({
    required String username,
    required String password,
    required String symbol,
    required String side,
    required double quantity,
    double? entry,
    double? stopLoss,
    double? takeProfit,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/propose-open');
    final res = await _client
        .post(
          uri,
          headers: _headers(username, password),
          body: jsonEncode({
            'symbol': symbol,
            'side': side,
            'quantity': quantity,
            if (entry != null) 'entry': entry,
            if (stopLoss != null) 'stop_loss': stopLoss,
            if (takeProfit != null) 'take_profit': takeProfit,
            'reason': 'from app signal card',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      throw StateError(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> proposeClose({
    required String username,
    required String password,
    required String symbol,
    double? quantity,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/propose-close');
    final res = await _client
        .post(
          uri,
          headers: _headers(username, password),
          body: jsonEncode({
            'symbol': symbol,
            if (quantity != null) 'quantity': quantity,
            'reason': 'from app close request',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      throw StateError(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approve({
    required String username,
    required String password,
    required String actionId,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/approve');
    final res = await _client
        .post(
          uri,
          headers: _headers(username, password),
          body: jsonEncode({'action_id': actionId}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) {
      throw StateError(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reject({
    required String username,
    required String password,
    required String actionId,
  }) async {
    final uri = Uri.parse('$baseUrl/execution/reject');
    final res = await _client
        .post(
          uri,
          headers: _headers(username, password),
          body: jsonEncode({'action_id': actionId}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      throw StateError(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }

  void dispose() => _client.close();
}
