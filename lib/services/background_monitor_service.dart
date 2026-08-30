import 'package:shared_preferences/shared_preferences.dart';

const String kBackgroundMonitorEnabled = 'background_monitor_enabled';

/// Preference flag for opportunity monitoring while the app process is alive.
///
/// Actual polling is performed by [RealtimeFuturesScannerService] in Home
/// (slower interval when backgrounded). This service never places orders.
///
/// When the OS force-stops the process, monitoring stops — we do not claim 24/7.
class BackgroundMonitorService {
  const BackgroundMonitorService._();

  static Future<void> initialize() async {
    // No native scheduler dependency (WorkManager requires newer Flutter).
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackgroundMonitorEnabled, enabled);
    // Keep realtime background polling preference in sync.
    await prefs.setBool('realtime_background_polling', enabled);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kBackgroundMonitorEnabled) ?? true;
  }

  static Future<void> syncFromSettings() async {
    final enabled = await isEnabled();
    await setEnabled(enabled);
  }
}
