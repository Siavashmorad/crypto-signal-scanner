import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'android_notification_service.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

const String kBackgroundMonitorEnabled = 'background_monitor_enabled';
const String kBackgroundMonitorTask = 'signalyab_market_monitor';
const String kBackgroundLastRun = 'background_monitor_last_run';
const String kBackgroundLastResult = 'background_monitor_last_result';

/// Android background market monitor.
///
/// The worker is deliberately read-only: it scans public market data and may
/// emit a local notification. It never calls SpotAutoTrader, Futures execution,
/// or any cloud/FCM order path.
@pragma('vm:entry-point')
void signalyabBackgroundCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kBackgroundMonitorTask) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kBackgroundMonitorEnabled) ?? true)) return true;

      final api = TabdealApi();
      final scanner = ScannerService(api);
      final signals = await scanner.scanAll(
        timeframe: const Duration(minutes: 15),
        maxConcurrency: 4,
        maxSymbols: 12,
        maxSignals: 6,
        preferSpot: true,
      );

      final now = DateTime.now();
      await prefs.setString(kBackgroundLastRun, now.toIso8601String());
      await prefs.setString(
        kBackgroundLastResult,
        signals.isEmpty ? 'no_opportunity' : 'ok',
      );

      if (signals.isNotEmpty) {
        final best = signals.first;
        final notifications = AndroidNotificationService();
        await notifications.init();
        await notifications.showOpportunity(
          id: best.symbol.hashCode & 0x7fffffff,
          title: 'سیگنال‌یاب · فرصت بازار',
          body:
              '${best.symbol} · امتیاز ${best.confidence.toStringAsFixed(0)} · ${best.side == 'LONG' ? 'تمایل صعودی' : 'تمایل نزولی'}',
          payload: AndroidNotificationService.payloadFor(
            symbol: best.symbol,
            side: best.side,
          ),
        );
      }
      return true;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kBackgroundLastResult, 'error');
      } catch (_) {}
      return false;
    }
  });
}

class BackgroundMonitorService {
  const BackgroundMonitorService._();

  static Future<void> initialize() async {
    await Workmanager().initialize(signalyabBackgroundCallback);
    await _register();
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackgroundMonitorEnabled, enabled);
    await prefs.setBool('realtime_background_polling', enabled);
    await _register();
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kBackgroundMonitorEnabled) ?? true;
  }

  static Future<DateTime?> lastRun() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kBackgroundLastRun);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<String> lastResult() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kBackgroundLastResult) ?? 'never';
  }

  static Future<void> syncFromSettings() async {
    await _register();
  }

  static Future<void> _register() async {
    await Workmanager().registerPeriodicTask(
      kBackgroundMonitorTask,
      kBackgroundMonitorTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
  }
}
