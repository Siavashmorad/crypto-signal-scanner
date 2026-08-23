import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Spot market depth via official Tabdeal WS.
/// Primary: wss://api1.tabdeal.org/stream/
/// Fallback: caller uses REST depth when [onDepth] not firing.
/// No extra packages — dart:io WebSocket only.
class TabdealDepthSocket {
  TabdealDepthSocket({
    this.baseUrl = 'wss://api1.tabdeal.org/stream/',
    this.onDepth,
    this.onStatus,
  });

  final String baseUrl;
  final void Function(Map<String, dynamic> depth)? onDepth;
  final void Function(String status)? onStatus;

  WebSocket? _ws;
  Timer? _reconnect;
  Timer? _watchdog;
  String? _symbol;
  bool _disposed = false;
  int _attempt = 0;

  bool get connected => _ws != null;

  Future<void> subscribe(String symbol) async {
    _symbol = symbol.toLowerCase().replaceAll('_', '');
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _symbol == null) return;
    await _closeSocket();
    try {
      onStatus?.call('connecting');
      final ws = await WebSocket.connect(baseUrl).timeout(
        const Duration(seconds: 12),
      );
      if (_disposed) {
        await ws.close();
        return;
      }
      _ws = ws;
      _attempt = 0;
      onStatus?.call('connected');

      // Official subscribe: "{symbol}@depth@2000ms"
      final payload = jsonEncode({
        'method': 'SUBSCRIBE',
        'params': ['${_symbol!}@depth@2000ms'],
        'id': 1,
      });
      ws.add(payload);

      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 45), () {
        onStatus?.call('stale');
        _scheduleReconnect();
      });

      ws.listen(
        (message) {
          _watchdog?.cancel();
          _watchdog = Timer(const Duration(seconds: 45), () {
            onStatus?.call('stale');
            _scheduleReconnect();
          });
          _handleMessage(message);
        },
        onError: (_) {
          onStatus?.call('error');
          _scheduleReconnect();
        },
        onDone: () {
          onStatus?.call('closed');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      onStatus?.call('failed');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final raw = message is String ? jsonDecode(message) : message;
      if (raw is! Map) return;
      final data = raw['data'] ?? raw;
      if (data is! Map) return;
      final event = '${data['e'] ?? ''}';
      if (event.isNotEmpty && event != 'depthUpdate') return;

      final bids = data['b'] ?? data['bids'];
      final asks = data['a'] ?? data['asks'];
      if (bids is! List && asks is! List) return;

      onDepth?.call({
        'bids': bids is List ? bids : const [],
        'asks': asks is List ? asks : const [],
        'source': 'websocket',
        'E': data['E'],
        's': data['s'],
      });
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnect?.cancel();
    _attempt++;
    final delay = Duration(seconds: (_attempt * 3).clamp(3, 30));
    _reconnect = Timer(delay, () => _connect());
  }

  Future<void> _closeSocket() async {
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnect?.cancel();
    _watchdog?.cancel();
    await _closeSocket();
  }
}
