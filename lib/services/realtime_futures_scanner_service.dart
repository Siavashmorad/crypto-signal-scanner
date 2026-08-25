import 'dart:async';

import '../models/market_data.dart';
import 'scanner_service.dart';
import 'signal_journal.dart';
import 'signal_notification_service.dart';

enum RealtimeScannerState {
  offline,
  monitoring,
  live,
  degraded,
  stale,
}

String realtimeScannerStateLabel(RealtimeScannerState s,
    {bool english = false}) {
  if (english) {
    return switch (s) {
      RealtimeScannerState.live => 'LIVE',
      RealtimeScannerState.monitoring => 'MONITORING',
      RealtimeScannerState.degraded => 'DEGRADED',
      RealtimeScannerState.stale => 'STALE',
      RealtimeScannerState.offline => 'OFFLINE',
    };
  }
  return switch (s) {
    RealtimeScannerState.live => 'زنده',
    RealtimeScannerState.monitoring => 'پایش',
    RealtimeScannerState.degraded => 'ضعیف',
    RealtimeScannerState.stale => 'کهنه',
    RealtimeScannerState.offline => 'قطع',
  };
}

class RealtimeOpportunity {
  final MarketSignal signal;
  final String quality;
  final String regime;
  final String dataHealth;
  final String fingerprint;

  const RealtimeOpportunity({
    required this.signal,
    required this.quality,
    required this.regime,
    required this.dataHealth,
    required this.fingerprint,
  });
}

/// Periodic market monitor built on existing [ScannerService].
/// Does NOT rewrite quant/gate/execution. Uses real Tabdeal trades+depth via scanner.
///
/// Background = slower Timer while the Dart isolate is still alive.
/// Does NOT claim 24/7 when the OS kills the process.
class RealtimeFuturesScannerService {
  RealtimeFuturesScannerService({
    required this.scanner,
    SignalJournal? journal,
    SignalNotificationService? notifications,
    this.onOpportunities,
    this.onNotify,
    this.onState,
  })  : journal = journal ?? SignalJournal(),
        notifications = notifications ?? SignalNotificationService();

  final ScannerService scanner;
  final SignalJournal journal;
  final SignalNotificationService notifications;

  final void Function(List<RealtimeOpportunity> list)? onOpportunities;
  final void Function(RealtimeOpportunity opp, String body)? onNotify;
  final void Function(RealtimeScannerState state, String detail)? onState;

  Timer? _timer;
  bool _running = false;
  bool _tickBusy = false;
  RealtimeScannerState state = RealtimeScannerState.offline;
  DateTime? lastSuccess;
  String lastDetail = '';
  List<RealtimeOpportunity> lastOpps = const [];
  int lastScannedCount = 0;
  int lastOpportunityCount = 0;

  /// Foreground: faster. Background (app not visible, process alive): slower.
  Duration intervalForeground = const Duration(seconds: 90);
  Duration intervalBackground = const Duration(minutes: 5);
  bool foreground = true;
  bool allowBackgroundPolling = true;
  int maxSymbols = 16;
  int maxSignals = 10;
  Duration timeframe = const Duration(minutes: 15);

  /// Optional external side hints (e.g. TradingView) — never invents scores.
  /// Map symbol → LONG/SHORT. Used only to prefer matching scanner results.
  Map<String, String> externalHints = const {};
  bool enabled = false;

  bool get isRunning => _running;

  static String qualityOf(double confidence) {
    if (confidence >= 85) return 'A+';
    if (confidence >= 72) return 'A';
    if (confidence >= 58) return 'B';
    if (confidence >= 45) return 'C';
    return 'NO TRADE';
  }

  void _setState(RealtimeScannerState s, String detail) {
    state = s;
    lastDetail = detail;
    onState?.call(s, detail);
  }

  Future<void> start() async {
    enabled = true;
    _running = true;
    _timer?.cancel();
    _setState(RealtimeScannerState.monitoring, 'starting');
    await tick();
    _schedule();
  }

  void stop() {
    enabled = false;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _setState(RealtimeScannerState.offline, 'stopped');
  }

  void setForeground(bool value) {
    foreground = value;
    if (_running) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;
    if (!foreground && !allowBackgroundPolling) {
      _setState(RealtimeScannerState.monitoring, 'background polling OFF');
      return;
    }
    final d = foreground ? intervalForeground : intervalBackground;
    _timer = Timer.periodic(d, (_) {
      // ignore: discarded_futures
      tick();
    });
  }

  Future<void> tick() async {
    if (!_running || _tickBusy) return;
    if (!foreground && !allowBackgroundPolling) return;
    _tickBusy = true;
    try {
      final list = await scanner.scanAll(
        timeframe: timeframe,
        maxConcurrency: 6,
        maxSymbols: maxSymbols,
        maxSignals: maxSignals,
      );
      lastSuccess = DateTime.now();
      lastScannedCount = maxSymbols;
      final src = scanner.dataSource;
      final health = src == 'tabdeal'
          ? 'LIVE'
          : src == 'binance'
              ? 'DEGRADED'
              : 'STALE';

      final opps = <RealtimeOpportunity>[];
      for (final s in list) {
        final q = qualityOf(s.confidence);
        if (q == 'NO TRADE') continue;
        final fp = SignalFingerprint.fromOpportunity(
          symbol: s.symbol,
          side: s.side,
          quality: q,
          score: s.confidence,
          entry: s.entry,
        );
        final opp = RealtimeOpportunity(
          signal: s,
          quality: q,
          regime: 'UNKNOWN',
          dataHealth: health,
          fingerprint: fp.key,
        );
        opps.add(opp);

        await journal.record(JournalEntry.fromSignal(
          s,
          regime: 'UNKNOWN',
          quality: q,
          score: s.confidence,
          confidence: s.confidence,
          reasons: 'realtime scanner ($src)',
          mode: JournalMode.paper,
        ));

        if (health == 'STALE') continue;
        if (notifications.shouldNotify(fp: fp)) {
          final body = notifications.buildBody(
            symbol: s.symbol,
            side: s.side,
            quality: q,
            score: s.confidence,
            entry: s.entry,
            stopLoss: s.stopLoss,
            tp1: s.tp1,
            riskReward: s.riskReward,
            regime: 'UNKNOWN',
          );
          onNotify?.call(opp, body);
        }
      }

      if (externalHints.isNotEmpty && opps.isNotEmpty) {
        opps.sort((a, b) {
          int rank(RealtimeOpportunity o) {
            final h = externalHints[o.signal.symbol.toUpperCase()];
            if (h == null) return 0;
            if (h.toUpperCase() == o.signal.side.toUpperCase()) return 2;
            return 1;
          }

          return rank(b).compareTo(rank(a));
        });
      }

      lastOpps = opps;
      lastOpportunityCount = opps.length;
      onOpportunities?.call(opps);

      if (src == 'tabdeal') {
        _setState(
          opps.isEmpty
              ? RealtimeScannerState.monitoring
              : RealtimeScannerState.live,
          opps.isEmpty
              ? 'NO VALID OPPORTUNITY'
              : '${opps.length} opportunities',
        );
      } else if (src == 'binance') {
        _setState(RealtimeScannerState.degraded, 'fallback data source');
      } else {
        _setState(RealtimeScannerState.stale, 'no market data');
      }
    } catch (e) {
      _setState(RealtimeScannerState.degraded, '$e');
    } finally {
      _tickBusy = false;
    }
  }

  void dispose() {
    stop();
  }
}
