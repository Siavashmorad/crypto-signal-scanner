import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../services/android_notification_service.dart';
import '../services/tabdeal_api.dart';
import '../services/scanner_service.dart';

const String kBackgroundMonitorTask = 'signalyab.market.monitor';
const String kBackgroundMonitorEnabled = 'background_monitor_enabled';

/// Registers a periodic Android background monitor.
///
/// This task only reads public market data and sends a local notification.
/// It never calls SpotAutoTrader, FuturesExecutionService, or any order API.
class BackgroundMonitorService {
  const BackgroundMonitorService._();

  static Future<void> initialize() async {
    await Workmanager().initialize(
      backgroundMonitorCallback,
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackgroundMonitorEnabled, enabled);
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        kBackgroundMonitorTask,
        kBackgroundMonitorTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } else {
      await Workmanager().cancelByUniqueName(kBackgroundMonitorTask);
    }
  }

  static Future<void> syncFromSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await setEnabled(prefs.getBool(kBackgroundMonitorEnabled) ?? true);
  }
}

@pragma('vm:entry-point')
void backgroundMonitorCallback() {
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
        maxSymbols: 24,
        maxSignals: 5,
        preferSpot: true,
      );
      if (signals.isEmpty) return true;

      final ranked = [...signals]
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final best = ranked.first;
      if (best.confidence < 72) return true;

      final fingerprint =
          '${best.symbol.toUpperCase()}|${best.side.toUpperCase()}|${best.entry.toStringAsFixed(8)}';
      final previous = prefs.getString('background_last_fingerprint');
      if (previous == fingerprint) return true;
      await prefs.setString('background_last_fingerprint', fingerprint);

      final notification = AndroidNotificationService();
      await notification.init();
      final body = 'فرصت ${best.symbol} · امتیاز ${best.confidence.toStringAsFixed(0)} · '
          '${best.side.toUpperCase() == 'LONG' ? 'خرید' : 'هشدار نزولی'} · '
          'ورود ${best.entry.toStringAsFixed(6)} · حدضرر ${best.stopLoss.toStringAsFixed(6)}';
      await notification.showOpportunity(
        id: best.symbol.hashCode & 0x7fffffff,
        title: 'فرصت جدید سیگنال‌یاب',
        body: body,
        payload: AndroidNotificationService.payloadFor(
          symbol: best.symbol,
          side: best.side,
        ),
      );
      return true;
    } catch (_) {
      // Background monitoring must fail silently and never become an order path.
      return false;
    }
  });
}
