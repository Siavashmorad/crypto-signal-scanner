import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';

enum JournalMode { paper, live }

enum JournalOutcome {
  pending,
  win,
  loss,
  breakeven,
  expired,
  invalidated,
  skipped,
}

/// One recorded signal — paper or live. No fabricated fields.
class JournalEntry {
  final String id;
  final DateTime timestamp;
  final String symbol;
  final String timeframe;
  final String side;
  final String regime;
  final String quality;
  final double score;
  final double confidence;
  final double entry;
  final double stopLoss;
  final double tp1;
  final double tp2;
  final double tp3;
  final double riskReward;
  final JournalMode mode;
  final JournalOutcome outcome;
  final double rMultiple;
  final int durationBars;
  final String reasons;
  final bool isLive;

  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.symbol,
    required this.timeframe,
    required this.side,
    required this.regime,
    required this.quality,
    required this.score,
    required this.confidence,
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    required this.tp3,
    required this.riskReward,
    required this.mode,
    this.outcome = JournalOutcome.pending,
    this.rMultiple = 0,
    this.durationBars = 0,
    this.reasons = '',
    this.isLive = false,
  });

  JournalEntry copyWith({
    JournalOutcome? outcome,
    double? rMultiple,
    int? durationBars,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        symbol: symbol,
        timeframe: timeframe,
        side: side,
        regime: regime,
        quality: quality,
        score: score,
        confidence: confidence,
        entry: entry,
        stopLoss: stopLoss,
        tp1: tp1,
        tp2: tp2,
        tp3: tp3,
        riskReward: riskReward,
        mode: mode,
        outcome: outcome ?? this.outcome,
        rMultiple: rMultiple ?? this.rMultiple,
        durationBars: durationBars ?? this.durationBars,
        reasons: reasons,
        isLive: isLive,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': timestamp.toIso8601String(),
        'symbol': symbol,
        'tf': timeframe,
        'side': side,
        'regime': regime,
        'quality': quality,
        'score': score,
        'confidence': confidence,
        'entry': entry,
        'sl': stopLoss,
        'tp1': tp1,
        'tp2': tp2,
        'tp3': tp3,
        'rr': riskReward,
        'mode': mode.name,
        'outcome': outcome.name,
        'r': rMultiple,
        'bars': durationBars,
        'reasons': reasons,
        'live': isLive,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: '${j['id']}',
        timestamp: DateTime.tryParse('${j['ts']}') ?? DateTime.now(),
        symbol: '${j['symbol']}',
        timeframe: '${j['tf'] ?? ''}',
        side: '${j['side']}',
        regime: '${j['regime'] ?? 'UNKNOWN'}',
        quality: '${j['quality'] ?? 'C'}',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        entry: (j['entry'] as num?)?.toDouble() ?? 0,
        stopLoss: (j['sl'] as num?)?.toDouble() ?? 0,
        tp1: (j['tp1'] as num?)?.toDouble() ?? 0,
        tp2: (j['tp2'] as num?)?.toDouble() ?? 0,
        tp3: (j['tp3'] as num?)?.toDouble() ?? 0,
        riskReward: (j['rr'] as num?)?.toDouble() ?? 0,
        mode: JournalMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => JournalMode.paper,
        ),
        outcome: JournalOutcome.values.firstWhere(
          (o) => o.name == j['outcome'],
          orElse: () => JournalOutcome.pending,
        ),
        rMultiple: (j['r'] as num?)?.toDouble() ?? 0,
        durationBars: (j['bars'] as num?)?.toInt() ?? 0,
        reasons: '${j['reasons'] ?? ''}',
        isLive: j['live'] == true,
      );

  static String makeId(MarketSignal s) =>
      '${s.symbol}_${s.side}_${s.timeframe}_${s.timestamp.millisecondsSinceEpoch}';

  static JournalEntry fromSignal(
    MarketSignal s, {
    String regime = 'UNKNOWN',
    String quality = 'C',
    double score = 0,
    double confidence = 0,
    String reasons = '',
    JournalMode mode = JournalMode.paper,
    bool isLive = false,
  }) =>
      JournalEntry(
        id: makeId(s),
        timestamp: s.timestamp,
        symbol: s.symbol,
        timeframe: s.timeframe,
        side: s.side,
        regime: regime,
        quality: quality,
        score: score > 0 ? score : s.confidence,
        confidence: confidence > 0 ? confidence : s.confidence,
        entry: s.entry,
        stopLoss: s.stopLoss,
        tp1: s.tp1,
        tp2: s.tp2,
        tp3: s.tp3,
        riskReward: s.riskReward,
        mode: mode,
        reasons: reasons,
        isLive: isLive,
      );
}

/// Local-only signal journal (SharedPreferences). Never sends to exchange.
class SignalJournal {
  static const _key = 'signalyab_signal_journal_v1';
  static const maxEntries = 500;

  Future<List<JournalEntry>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => JournalEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<JournalEntry> entries) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = entries.length > maxEntries
        ? entries.sublist(0, maxEntries)
        : entries;
    await p.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  /// Insert if not duplicate id; returns true if added.
  Future<bool> record(JournalEntry entry) async {
    final all = await load();
    if (all.any((e) => e.id == entry.id)) return false;
    all.insert(0, entry);
    await _save(all);
    return true;
  }

  Future<void> updateOutcome(
    String id, {
    required JournalOutcome outcome,
    required double rMultiple,
    int durationBars = 0,
  }) async {
    final all = await load();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    all[i] = all[i].copyWith(
      outcome: outcome,
      rMultiple: rMultiple,
      durationBars: durationBars,
    );
    await _save(all);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
