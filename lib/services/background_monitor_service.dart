import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'android_notification_service.dart';
import 'focus_coin_service_v2.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

const String kBackgroundMonitorEnabled = 'background_monitor_enabled';
const String kBackgroundMonitorTask = 'signalyab_market_monitor';
const String kBackgroundLastRun = 'background_monitor_last_run';
const String kBackgroundLastResult = 'background_monitor_last_result';

/// Android background market monitor.
/// Read-only: no SpotAutoTrader/Futures/FCM/cloud order path is called here.
@pragma('vm:entry-point')
void signalyabBackgroundCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kBackgroundMonitorTask) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kBackgroundMonitorEnabled) ?? true)) return true;

      final api = TabdealApi();
      final scanner = ScannerService(api);
      final focus = FocusCoinServiceV2(api: api, scanner: scanner);
      final snapshot = await focus.tick(
        timeframe: const Duration(minutes: 15),
        maxSymbols: 40,
      );

      final now = DateTime.now();
      await prefs.setString(kBackgroundLastRun, now.toIso8601String());
      await prefs.setString(
        kBackgroundLastResult,
        snapshot.symbol == null ? 'no_qualified_setup' : 'ok',
      );

      if (snapshot.symbol != null && snapshot.score >= 80) {
        final notifications = AndroidNotificationService();
        await notifications.init();

        final String title;
        final String status;
        if (snapshot.score >= 95) {
          title = '🔥 سیگنال‌یاب · فرصت بسیار قوی';
          status = 'شرایط بررسی خودکار را دارد';
        } else if (snapshot.score >= 93) {
          title = '🟢 سیگنال‌یاب · فرصت قوی';
          status = 'هشدار فرصت قوی؛ بررسی ورود';
        } else if (snapshot.score >= 90) {
          title = '🟡 سیگنال‌یاب · فرصت قابل بررسی';
          status = 'هنوز تأیید نهایی لازم است';
        } else {
          title = '🔵 سیگنال‌یاب · زیر آستانه ورود';
          status = 'فعلاً فقط تحت نظر';
        }

        final body = '${snapshot.symbol} · LONG · امتیاز ${snapshot.score.toStringAsFixed(0)}/100\n'
            '$status · اطمینان ${snapshot.confidence}%\n'
            'R/R: 1:${snapshot.riskReward.toStringAsFixed(1)}';
        await notifications.showOpportunity(
          id: snapshot.symbol.hashCode & 0x7fffffff,
          title: title,
          body: body,
          payload: AndroidNotificationService.payloadFor(
            symbol: snapshot.symbol!,
            side: snapshot.side,
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

  static Future<void> syncFromSettings() async => _register();

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
