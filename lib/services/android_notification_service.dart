import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationPayload {
  final String symbol;
  final String side;
  const NotificationPayload({required this.symbol, required this.side});
}

/// Real Android local notifications for SignalYab opportunities.
/// Does NOT place orders. Does NOT include API secrets.
class AndroidNotificationService {
  AndroidNotificationService({
    this.onSelect,
  });

  final void Function(String? payload)? onSelect;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool enabled = true;

  static const _channelId = 'signalyab_futures_opportunities';
  static const _channelName = 'SignalYab Futures Opportunities';
  static const _channelDesc =
      'Alerts for high-quality Futures setups (A/A+). No auto-trade.';

  Future<void> init() async {
    if (_ready) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        onSelect?.call(details.payload);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  Future<void> showOpportunity({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!enabled) return;
    if (!_ready) {
      try {
        await init();
      } catch (_) {
        return;
      }
    }
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'SignalYab',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: payload);
  }

  static String payloadFor({required String symbol, required String side}) =>
      '${symbol.toUpperCase()}|${side.toUpperCase()}';

  static NotificationPayload? parsePayload(String? payload) {
    if (payload == null || !payload.contains('|')) return null;
    final parts = payload.split('|');
    if (parts.length < 2) return null;
    return NotificationPayload(symbol: parts[0], side: parts[1]);
  }
}
