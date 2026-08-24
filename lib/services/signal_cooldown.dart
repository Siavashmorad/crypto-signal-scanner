import '../models/market_data.dart';

/// Prevents duplicate same-symbol same-side spam within [window].
class SignalCooldown {
  SignalCooldown({this.window = const Duration(minutes: 30)});

  final Duration window;
  final Map<String, DateTime> _last = {};

  String _key(MarketSignal s) =>
      '${s.symbol}|${s.side.toUpperCase()}|${s.timeframe}';

  bool allow(MarketSignal s, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final k = _key(s);
    final prev = _last[k];
    if (prev != null && t.difference(prev) < window) return false;
    _last[k] = t;
    return true;
  }

  /// Filter list; first occurrence of each key wins.
  List<MarketSignal> filter(List<MarketSignal> signals, {DateTime? now}) {
    final out = <MarketSignal>[];
    for (final s in signals) {
      if (allow(s, now: now)) out.add(s);
    }
    return out;
  }

  void clear() => _last.clear();
}
