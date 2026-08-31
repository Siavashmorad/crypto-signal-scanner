import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import 'coin_analysis_service.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

/// Conservative single-symbol focus layer.
/// Re-evaluates real market data and never creates orders.
class FocusCoinServiceV2 {
  FocusCoinServiceV2({TabdealApi? api, ScannerService? scanner})
      : api = api ?? TabdealApi(),
        scanner = scanner ?? ScannerService(api ?? TabdealApi()),
        analysis = CoinAnalysisService(api: api ?? TabdealApi());

  final TabdealApi api;
  final ScannerService scanner;
  final CoinAnalysisService analysis;

  static const int candidateCount = 6;
  static const double keepScore = 80;
  static const double startScore = 93;
  static const int startConfidence = 75;
  static const double startRiskReward = 1.8;
  static const double switchAdvantage = 4;
  static const String _focusKey = 'signalyab_focus_symbol';

  String? _focusSymbol;
  String? get focusSymbol => _focusSymbol;

  Future<void> _restoreFocus() async {
    if (_focusSymbol != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _focusSymbol = prefs.getString(_focusKey);
    } catch (_) {}
  }

  Future<void> _saveFocus(String? symbol) async {
    _focusSymbol = symbol;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (symbol == null) {
        await prefs.remove(_focusKey);
      } else {
        await prefs.setString(_focusKey, symbol);
      }
    } catch (_) {}
  }

  Future<FocusSnapshotV2> tick({
    Duration timeframe = const Duration(minutes: 15),
    int maxSymbols = 40,
  }) async {
    await _restoreFocus();
    final previousFocus = _focusSymbol;
    final now = DateTime.now();
    final scanned = await scanner.scanAll(
      timeframe: timeframe,
      maxSymbols: maxSymbols,
      maxSignals: 15,
      preferSpot: true,
    );

    final longs = scanned
        .where((s) => s.side.toUpperCase() == 'LONG')
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (longs.isEmpty) {
      await _saveFocus(null);
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    final pool = <MarketSignal>[];
    if (previousFocus != null) {
      pool.addAll(longs.where((s) => s.symbol == previousFocus));
    }
    for (final s in longs) {
      if (pool.any((x) => x.symbol == s.symbol)) continue;
      pool.add(s);
      if (pool.length >= candidateCount) break;
    }

    final evaluated = <_FocusCandidate>[];
    for (final signal in pool) {
      try {
        final r = await analysis.analyze(signal.symbol, preferSpot: true);
        final usable = !r.dataStale &&
            !r.dataInsufficient &&
            r.decision == CoinDecision.buy &&
            r.hasTradePlan &&
            (r.riskReward ?? 0) >= 1.4;
        if (usable) {
          evaluated.add(
            _FocusCandidate(
              signal,
              r,
              r.score * 0.65 + r.confidence * 0.35,
            ),
          );
        }
      } catch (_) {}
    }

    evaluated.sort((a, b) => b.composite.compareTo(a.composite));
    if (evaluated.isEmpty) {
      await _saveFocus(null);
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    _FocusCandidate? current;
    for (final c in evaluated) {
      if (c.signal.symbol == previousFocus) {
        current = c;
        break;
      }
    }

    final best = evaluated.first;
    final keepCurrent = current != null &&
        current.result.score >= keepScore &&
        current.result.confidence >= startConfidence &&
        current.composite >= best.composite - switchAdvantage;
    final chosen = keepCurrent ? current : best;
    final switched = previousFocus != null &&
        chosen.signal.symbol != previousFocus;
    await _saveFocus(chosen.signal.symbol);

    final start = chosen.result.score >= startScore &&
        chosen.result.confidence >= startConfidence &&
        (chosen.result.riskReward ?? 0) >= startRiskReward;
    final action = switched
        ? FocusActionV2.switchFocus
        : (start ? FocusActionV2.startNow : FocusActionV2.wait);

    final reasons = <String>[
      if (switched)
        'فوکوس قبلی ضعیف‌تر شد → تعویض به ${chosen.signal.symbol}',
      'امتیاز عمیق تحلیل: ${chosen.result.score.toStringAsFixed(0)} / ۱۰۰',
      'اطمینان: ${chosen.result.confidence}٪',
      'رژیم: ${chosen.result.regimeFa}',
      'روند اصلی: ${chosen.result.trendMainFa}',
      ...chosen.result.reasonsFa.take(5),
      'کندل و چندتایم‌فریم بررسی شد؛ بدون افزایش مصنوعی امتیاز',
      if (!start) 'آستانه محافظه‌کارانه شروع کامل نشده؛ فعلاً تحت نظر',
    ];

    return FocusSnapshotV2(
      symbol: chosen.signal.symbol,
      action: action,
      score: chosen.result.score,
      confidence: chosen.result.confidence,
      side: 'LONG',
      entry: chosen.result.entry ?? chosen.signal.entry,
      stopLoss: chosen.result.stopLoss ?? chosen.signal.stopLoss,
      tp1: chosen.result.tp1 ?? chosen.signal.tp1,
      tp2: chosen.result.tp2 ?? chosen.signal.tp2,
      tp3: chosen.result.tp3 ?? chosen.signal.tp3,
      riskReward: chosen.result.riskReward ?? chosen.signal.riskReward,
      timeframe: chosen.signal.timeframe,
      reasonsFa: reasons,
      at: now,
      dataSource: chosen.result.dataSource,
      signal: chosen.signal,
    );
  }
}

class _FocusCandidate {
  const _FocusCandidate(this.signal, this.result, this.composite);
  final MarketSignal signal;
  final CoinAnalysisResult result;
  final double composite;
}

enum FocusActionV2 { startNow, wait, switchFocus, noSetup }

class FocusSnapshotV2 {
  const FocusSnapshotV2({
    required this.symbol,
    required this.action,
    required this.score,
    required this.confidence,
    required this.side,
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    required this.tp3,
    required this.riskReward,
    required this.timeframe,
    required this.reasonsFa,
    required this.at,
    required this.dataSource,
    required this.signal,
  });

  final String? symbol;
  final FocusActionV2 action;
  final double score;
  final int confidence;
  final String side;
  final double? entry, stopLoss, tp1, tp2, tp3;
  final double riskReward;
  final String timeframe;
  final List<String> reasonsFa;
  final DateTime at;
  final String dataSource;
  final MarketSignal? signal;

  factory FocusSnapshotV2.empty(DateTime now, String source) =>
      FocusSnapshotV2(
        symbol: null,
        action: FocusActionV2.noSetup,
        score: 0,
        confidence: 0,
        side: 'NONE',
        entry: null,
        stopLoss: null,
        tp1: null,
        tp2: null,
        tp3: null,
        riskReward: 0,
        timeframe: '15m',
        reasonsFa: const [
          'هیچ موقعیت LONG پس از تحلیل عمیق چندتایم‌فریم تأیید نشد',
          'امتیاز مصنوعی اضافه نشد؛ فعلاً انتظار',
        ],
        at: now,
        dataSource: source,
        signal: null,
      );
}
