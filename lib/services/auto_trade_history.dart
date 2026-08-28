import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent history of automatic SPOT trades (open + closed).
class AutoTradeRecord {
  final String id;
  final String symbol;
  final String side;
  final double score;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final double qty;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double? exitPrice;
  final double? pnlQuote;
  final String? exitReason;
  final String status; // open | closed
  final int? orderId;

  const AutoTradeRecord({
    required this.id,
    required this.symbol,
    required this.side,
    required this.score,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.qty,
    required this.openedAt,
    this.closedAt,
    this.exitPrice,
    this.pnlQuote,
    this.exitReason,
    this.status = 'open',
    this.orderId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'side': side,
        'score': score,
        'entry': entry,
        'stopLoss': stopLoss,
        'takeProfit': takeProfit,
        'qty': qty,
        'openedAt': openedAt.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
        'exitPrice': exitPrice,
        'pnlQuote': pnlQuote,
        'exitReason': exitReason,
        'status': status,
        'orderId': orderId,
      };

  factory AutoTradeRecord.fromJson(Map<String, dynamic> j) => AutoTradeRecord(
        id: '${j['id']}',
        symbol: '${j['symbol']}'.toUpperCase(),
        side: '${j['side']}',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        entry: (j['entry'] as num?)?.toDouble() ?? 0,
        stopLoss: (j['stopLoss'] as num?)?.toDouble() ?? 0,
        takeProfit: (j['takeProfit'] as num?)?.toDouble() ?? 0,
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        openedAt: DateTime.tryParse('${j['openedAt']}') ?? DateTime.now(),
        closedAt: j['closedAt'] != null
            ? DateTime.tryParse('${j['closedAt']}')
            : null,
        exitPrice: (j['exitPrice'] as num?)?.toDouble(),
        pnlQuote: (j['pnlQuote'] as num?)?.toDouble(),
        exitReason: j['exitReason']?.toString(),
        status: '${j['status'] ?? 'open'}',
        orderId: int.tryParse('${j['orderId'] ?? ''}'),
      );

  AutoTradeRecord copyWith({
    DateTime? closedAt,
    double? exitPrice,
    double? pnlQuote,
    String? exitReason,
    String? status,
  }) =>
      AutoTradeRecord(
        id: id,
        symbol: symbol,
        side: side,
        score: score,
        entry: entry,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        qty: qty,
        openedAt: openedAt,
        closedAt: closedAt ?? this.closedAt,
        exitPrice: exitPrice ?? this.exitPrice,
        pnlQuote: pnlQuote ?? this.pnlQuote,
        exitReason: exitReason ?? this.exitReason,
        status: status ?? this.status,
        orderId: orderId,
      );
}

class AutoTradeHistory {
  static const _key = 'auto_trade_history_v1';
  static const _openKey = 'auto_trade_open_symbols_v1';
  static const _fpKey = 'auto_trade_fingerprints_v1';

  Future<List<AutoTradeRecord>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => AutoTradeRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<AutoTradeRecord> all) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = all.length > 200 ? all.sublist(all.length - 200) : all;
    await p.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  Future<void> add(AutoTradeRecord r) async {
    final all = await load();
    all.add(r);
    await _save(all);
    final p = await SharedPreferences.getInstance();
    final open = p.getStringList(_openKey) ?? [];
    if (!open.contains(r.symbol.toUpperCase())) {
      open.add(r.symbol.toUpperCase());
      await p.setStringList(_openKey, open);
    }
  }

  Future<void> close(
    String id, {
    required double exitPrice,
    required double pnlQuote,
    required String exitReason,
  }) async {
    final all = await load();
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final updated = all[i].copyWith(
      closedAt: DateTime.now(),
      exitPrice: exitPrice,
      pnlQuote: pnlQuote,
      exitReason: exitReason,
      status: 'closed',
    );
    all[i] = updated;
    await _save(all);
    final p = await SharedPreferences.getInstance();
    final open = p.getStringList(_openKey) ?? [];
    open.remove(updated.symbol.toUpperCase());
    await p.setStringList(_openKey, open);
  }

  Future<List<AutoTradeRecord>> openTrades() async {
    final all = await load();
    return all.where((e) => e.status == 'open').toList();
  }

  Future<bool> hasOpenSymbol(String symbol) async {
    final p = await SharedPreferences.getInstance();
    final open = p.getStringList(_openKey) ?? [];
    return open.contains(symbol.toUpperCase().replaceAll('_', ''));
  }

  Future<bool> wasTradedFingerprint(String fp) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_fpKey) ?? [];
    return list.contains(fp);
  }

  Future<void> rememberFingerprint(String fp) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_fpKey) ?? [];
    if (list.contains(fp)) return;
    list.add(fp);
    if (list.length > 300) list.removeRange(0, list.length - 300);
    await p.setStringList(_fpKey, list);
  }
}
