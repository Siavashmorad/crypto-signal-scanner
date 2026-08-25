import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'android_notification_service.dart';
import 'fcm_opportunity_payload.dart';

/// Top-level background handler (required by firebase_messaging).
/// Does NOT place orders. Only surfaces OS notification via local channel.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Credential / google-services missing — ignore.
  }
  // Background: OS shows notification payload from FCM "notification" key.
  // Data-only messages can be logged; no order path exists here.
}

/// FCM client for SignalYab.
///
/// - Registers device token with backend `/devices/register`
/// - Handles foreground messages via existing AndroidNotificationService
/// - Tap / open → [onOpportunityOpened] (revalidate + confirm elsewhere)
/// - Never places orders. Never embeds FCM server keys.
///
/// Live push requires:
///   1) google-services.json (Android) / Firebase options
///   2) FCM_SERVER_KEY on backend ENV
///   3) always-on cloud worker
class FirebasePushService {
  FirebasePushService({
    this.onOpportunityOpened,
    AndroidNotificationService? localNotifications,
  }) : _local = localNotifications ?? AndroidNotificationService();

  void Function(FcmOpportunityPayload payload)? onOpportunityOpened;
  final AndroidNotificationService _local;

  final _openedController =
      StreamController<FcmOpportunityPayload>.broadcast();
  Stream<FcmOpportunityPayload> get opportunityOpened =>
      _openedController.stream;

  bool _ready = false;
  bool _firebaseOk = false;
  String? lastToken;
  String? lastError;
  String deviceId = 'android-unknown';

  bool get isFirebaseReady => _firebaseOk;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _local.init();
    } catch (_) {}

    try {
      await Firebase.initializeApp();
      _firebaseOk = true;
    } catch (e) {
      lastError = 'Firebase init failed (CREDENTIAL REQUIRED): $e';
      _firebaseOk = false;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        lastError = 'notification permission denied';
      }
    } catch (e) {
      lastError = 'permission: $e';
    }

    // Foreground
    FirebaseMessaging.onMessage.listen(_onForeground);
    // Tap when app in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    // Cold start from notification
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _onOpened(initial);
      }
    } catch (_) {}

    messaging.onTokenRefresh.listen((t) async {
      lastToken = t;
      // Caller should re-register with backend credentials.
    });

    try {
      lastToken = await messaging.getToken();
    } catch (e) {
      lastError = 'getToken: $e';
    }

    deviceId = await _stableDeviceId();
  }

  Future<String> _stableDeviceId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('fcm_device_id');
    if (id == null || id.length < 8) {
      id =
          'android-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
      await p.setString('fcm_device_id', id);
    }
    return id;
  }

  void _onForeground(RemoteMessage message) {
    final parsed = FcmOpportunityPayload.fromData(
      message.data.map((k, v) => MapEntry(k, v)),
    );
    final title = message.notification?.title ??
        (parsed != null
            ? 'SignalYab ${parsed.symbol} ${parsed.side}'
            : 'SignalYab');
    final body = message.notification?.body ??
        (parsed != null
            ? 'Score ${parsed.score ?? "-"} | confirm required'
            : 'Opportunity');
    final localPayload = parsed?.toLocalPayload() ??
        AndroidNotificationService.payloadFor(
          symbol: parsed?.symbol ?? 'UNK',
          side: parsed?.side ?? 'LONG',
        );
    final id = (parsed?.opportunityId.hashCode ??
            DateTime.now().millisecondsSinceEpoch) &
        0x7fffffff;
    _local.showOpportunity(
      id: id,
      title: title,
      body: body,
      payload: localPayload,
    );
  }

  void _onOpened(RemoteMessage message) {
    final parsed = FcmOpportunityPayload.fromData(
      message.data.map((k, v) => MapEntry(k, v)),
    );
    if (parsed == null) return;
    onOpportunityOpened?.call(parsed);
    if (!_openedController.isClosed) {
      _openedController.add(parsed);
    }
  }

  /// Handle local notification tap (same channel).
  void handleLocalTap(String? payload) {
    final parsed = FcmOpportunityPayload.fromLocalPayload(payload);
    if (parsed == null) return;
    onOpportunityOpened?.call(parsed);
    if (!_openedController.isClosed) {
      _openedController.add(parsed);
    }
  }

  /// POST token to backend. Requires owner Basic auth (username/password).
  Future<bool> registerWithBackend({
    required String backendBaseUrl,
    required String username,
    required String password,
    String appVersion = '0.2.1',
    bool force = false,
    bool enabled = true,
  }) async {
    if (!_firebaseOk) return false;
    final token = lastToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null || token.length < 20) {
      lastError = 'no FCM token';
      return false;
    }
    lastToken = token;
    final base = backendBaseUrl.replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || !base.startsWith('http')) {
      lastError = 'invalid backend URL';
      return false;
    }
    final uri = Uri.parse('$base/devices/register');
    final body = jsonEncode({
      'device_id': deviceId,
      'fcm_token': token,
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'enabled': enabled,
      'app_version': appVersion,
    });
    final cred = base64Encode(utf8.encode('$username:$password'));
    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Basic $cred',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final p = await SharedPreferences.getInstance();
        await p.setString('fcm_last_registered_token', token);
        return true;
      }
      lastError = 'register HTTP ${resp.statusCode}';
      return false;
    } catch (e) {
      lastError = 'register: $e';
      return false;
    }
  }

  Future<bool> disableOnBackend({
    required String backendBaseUrl,
    required String username,
    required String password,
  }) async {
    final base = backendBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/devices/disable');
    final cred = base64Encode(utf8.encode('$username:$password'));
    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Basic $cred',
            },
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 12));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _openedController.close();
  }
}
