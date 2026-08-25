/// Parses FCM / local notification data for SignalYab opportunities.
/// Does NOT place orders. Does NOT invent market data.
class FcmOpportunityPayload {
  final String type;
  final String opportunityId;
  final String symbol;
  final String side;
  final double? entry;
  final double? stopLoss;
  final double? tp1;
  final double? riskReward;
  final double? score;
  final double? confidence;
  final String? regime;
  final int? timestampMs;
  final String? source;
  final String? deepLink;

  const FcmOpportunityPayload({
    required this.type,
    required this.opportunityId,
    required this.symbol,
    required this.side,
    this.entry,
    this.stopLoss,
    this.tp1,
    this.riskReward,
    this.score,
    this.confidence,
    this.regime,
    this.timestampMs,
    this.source,
    this.deepLink,
  });

  bool get isOpportunity =>
      type == 'signal_opportunity' ||
      type == 'opportunity' ||
      opportunityId.isNotEmpty;

  /// Max age before treating as stale on the client (15 min).
  bool isStale({Duration maxAge = const Duration(minutes: 15)}) {
    if (timestampMs == null || timestampMs! <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - timestampMs!;
    return age > maxAge.inMilliseconds;
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _i(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Parse from FCM data map (all values may be strings).
  static FcmOpportunityPayload? fromData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    final symbol = (data['symbol'] ?? '').toString().trim().toUpperCase();
    final side = (data['side'] ?? '').toString().trim().toUpperCase();
    final oid = (data['opportunity_id'] ?? data['opportunityId'] ?? '')
        .toString()
        .trim();
    if (symbol.isEmpty || side.isEmpty) return null;
    if (side != 'LONG' && side != 'SHORT') return null;
    final type = (data['type'] ?? 'signal_opportunity').toString().trim();
    return FcmOpportunityPayload(
      type: type.isEmpty ? 'signal_opportunity' : type,
      opportunityId: oid.isEmpty ? '$symbol|$side' : oid,
      symbol: symbol,
      side: side,
      entry: _d(data['entry']),
      stopLoss: _d(data['stop_loss'] ?? data['stopLoss']),
      tp1: _d(data['tp1']),
      riskReward: _d(data['risk_reward'] ?? data['riskReward']),
      score: _d(data['score']),
      confidence: _d(data['confidence']),
      regime: data['regime']?.toString(),
      timestampMs: _i(data['timestamp_ms'] ?? data['timestamp']),
      source: data['source']?.toString(),
      deepLink: data['deep_link']?.toString(),
    );
  }

  /// Parse compact local payload: SYMBOL|SIDE or SYMBOL|SIDE|opportunityId
  static FcmOpportunityPayload? fromLocalPayload(String? payload) {
    if (payload == null || !payload.contains('|')) return null;
    final parts = payload.split('|');
    if (parts.length < 2) return null;
    final symbol = parts[0].trim().toUpperCase();
    final side = parts[1].trim().toUpperCase();
    if (symbol.isEmpty || (side != 'LONG' && side != 'SHORT')) return null;
    final oid = parts.length >= 3 ? parts[2].trim() : '$symbol|$side';
    return FcmOpportunityPayload(
      type: 'signal_opportunity',
      opportunityId: oid,
      symbol: symbol,
      side: side,
    );
  }

  String toLocalPayload() => '$symbol|$side|$opportunityId';

  Map<String, String> toDataMap() => {
        'type': type,
        'opportunity_id': opportunityId,
        'symbol': symbol,
        'side': side,
        if (entry != null) 'entry': entry.toString(),
        if (stopLoss != null) 'stop_loss': stopLoss.toString(),
        if (tp1 != null) 'tp1': tp1.toString(),
        if (riskReward != null) 'risk_reward': riskReward.toString(),
        if (score != null) 'score': score.toString(),
        if (confidence != null) 'confidence': confidence.toString(),
        if (regime != null) 'regime': regime!,
        if (timestampMs != null) 'timestamp_ms': timestampMs.toString(),
        if (source != null) 'source': source!,
        if (deepLink != null) 'deep_link': deepLink!,
      };
}
