/// Market-data freshness for UI and trade gating.
enum DataHealth {
  live,
  degraded,
  stale,
  offline,
}

extension DataHealthLabel on DataHealth {
  String get label => switch (this) {
        DataHealth.live => 'LIVE',
        DataHealth.degraded => 'DEGRADED',
        DataHealth.stale => 'STALE',
        DataHealth.offline => 'OFFLINE',
      };

  bool get allowsTrade => this == DataHealth.live || this == DataHealth.degraded;
}

/// Tracks last successful market-data touch (trades / depth / WS).
class DataHealthMonitor {
  DataHealthMonitor({
    this.liveWindow = const Duration(seconds: 45),
    this.staleWindow = const Duration(seconds: 120),
  });

  final Duration liveWindow;
  final Duration staleWindow;

  DateTime? lastTradesOk;
  DateTime? lastDepthOk;
  DateTime? lastWsOk;
  String wsStatus = 'idle';
  bool lastRestFailed = false;

  void markTradesOk() {
    lastTradesOk = DateTime.now();
    lastRestFailed = false;
  }

  void markDepthOk({bool fromWs = false}) {
    lastDepthOk = DateTime.now();
    if (fromWs) lastWsOk = DateTime.now();
    lastRestFailed = false;
  }

  void markRestFailed() => lastRestFailed = true;

  void setWsStatus(String s) {
    wsStatus = s;
    if (s == 'connected') lastWsOk = DateTime.now();
  }

  DataHealth evaluate({DateTime? now}) {
    final t = now ?? DateTime.now();
    final latest = _latestOk();
    if (latest == null) {
      return lastRestFailed ? DataHealth.offline : DataHealth.offline;
    }
    final age = t.difference(latest);
    if (age <= liveWindow) {
      if (wsStatus == 'error' || wsStatus == 'stale' || wsStatus == 'failed') {
        return DataHealth.degraded;
      }
      return DataHealth.live;
    }
    if (age <= staleWindow) return DataHealth.degraded;
    return DataHealth.stale;
  }

  DateTime? _latestOk() {
    DateTime? best;
    for (final d in [lastTradesOk, lastDepthOk, lastWsOk]) {
      if (d == null) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }
}
