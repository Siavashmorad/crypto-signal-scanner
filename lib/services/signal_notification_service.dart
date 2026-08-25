/// Dedup + cooldown for realtime opportunity alerts.
/// Does not place orders. Does not log secrets.
class SignalFingerprint {
  final String symbol;
  final String side;
  final String quality;
  final int scoreBand;
  final int entryBand;

  const SignalFingerprint({
    required this.symbol,
    required this.side,
    required this.quality,
    required this.scoreBand,
    required this.entryBand,
  });

  /// Coarse entry band so tiny price noise does not re-notify.
  factory SignalFingerprint.fromOpportunity({
    required String symbol,
    required String side,
    required String quality,
    required double score,
    required double entry,
  }) {
    final band = entry <= 0
        ? 0
        : (entry >= 1000
            ? (entry / 10).round()
            : entry >= 1
                ? (entry * 100).round()
                : (entry * 1e6).round());
    return SignalFingerprint(
      symbol: symbol.toUpperCase(),
      side: side.toUpperCase(),
      quality: quality.toUpperCase(),
      scoreBand: (score / 5).floor() * 5,
      entryBand: band,
    );
  }

  String get key => '$symbol:$side:$quality:$scoreBand:$entryBand';

  @override
  bool operator ==(Object other) =>
      other is SignalFingerprint && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class SignalNotificationService {
  SignalNotificationService({
    this.cooldown = const Duration(minutes: 15),
    this.minQualityForNotify = 'A',
  });

  final Duration cooldown;
  String minQualityForNotify;

  final Map<String, DateTime> _lastNotified = {};
  final Set<String> _activeFingerprints = {};

  static const _qualityRank = {'A+': 4, 'A': 3, 'B': 2, 'C': 1, 'NO TRADE': 0};

  bool qualityAllowsNotify(String quality) {
    final q = _qualityRank[quality.toUpperCase()] ?? 0;
    final min = _qualityRank[minQualityForNotify.toUpperCase()] ?? 3;
    return q >= min;
  }

  /// Returns true if a user-visible notification should be shown.
  bool shouldNotify({
    required SignalFingerprint fp,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    if (!qualityAllowsNotify(fp.quality)) return false;

    final last = _lastNotified[fp.symbol];
    if (last != null && t.difference(last) < cooldown) {
      if (_activeFingerprints.contains(fp.key)) return false;
    }

    if (_activeFingerprints.contains(fp.key)) return false;

    _activeFingerprints.add(fp.key);
    _lastNotified[fp.symbol] = t;
    if (_activeFingerprints.length > 200) {
      _activeFingerprints.clear();
      _activeFingerprints.add(fp.key);
    }
    return true;
  }

  void invalidate(String symbol) {
    _activeFingerprints
        .removeWhere((k) => k.startsWith('${symbol.toUpperCase()}:'));
  }

  void clear() {
    _lastNotified.clear();
    _activeFingerprints.clear();
  }

  /// Safe payload for system tray — never include secrets.
  String buildBody({
    required String symbol,
    required String side,
    required String quality,
    required double score,
    required double entry,
    required double stopLoss,
    required double tp1,
    required double riskReward,
    required String regime,
  }) {
    return '$symbol FUTURES $side\n'
        'Quality: $quality  Score: ${score.toStringAsFixed(0)}  '
        'Conf: ${score.toStringAsFixed(0)}%\n'
        'Entry: $entry  SL: $stopLoss  TP1: $tp1\n'
        'R/R: 1:${riskReward.toStringAsFixed(1)}  Regime: $regime\n'
        'No guaranteed profit.';
  }
}
