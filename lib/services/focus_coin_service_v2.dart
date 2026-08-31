import '../models/market_data.dart';
import 'coin_analysis_service.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

/// Higher-quality single-symbol focus layer.
/// It does not invent scores or prices: candidates are re-evaluated from real
/// multi-timeframe candles through CoinAnalysisService/QuantSignalEngine.
/// No order path exists here.
class FocusCoinServiceV2 {
  FocusCoinServiceV2({TabdealApi? api, ScannerService? scanner})
      : api = api ?? TabdealApi(),
        scanner = scanner ?? ScannerService(api ?? TabdealApi()),
        analysis = CoinAnalysisService(api: api ?? TabdealApi());

  final TabdealApi api;
  final ScannerService scanner;
  final CoinAnalysisService analysis;

  static const int candidateCount = 6;
  static const double keepScore = 60;
  static const double startScore = 72;

  String? _focusSymbol;
  String? get focusSymbol => _focusSymbol;

  Future<FocusSnapshotV2> tick({
    Duration timeframe = const Duration(minutes: 15),
    int maxSymbols = 40,
  }) async {
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
      _focusSymbol = null;
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    // Deep-check only the strongest few instead of trusting the scanner score alone.
    final pool = <MarketSignal>[];
    if (_focusSymbol != null) {
      final current = longs.where((s) => s.symbol == _focusSymbol);
      pool.addAll(current);
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
          final composite = r.score * 0.65 + r.confidence * 0.35;
          evaluated.add(_FocusCandidate(signal, r, composite));
        }
      } catch (_) {}
    }

    evaluated.sort((a, b) => b.composite.compareTo(a.composite));

    _FocusCandidate? current;
    if (_focusSymbol != null) {
      for (final c in evaluated) {
        if (c.signal.symbol == _focusSymbol) {
          current = c;
          break;
        }
      }
    }

    final chosen = current ?? (evaluated.isNotEmpty ? evaluated.first : null);
    if (chosen == null) {
      _focusSymbol = null;
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    final switched = _focusSymbol != null && _focusSymbol != chosen.signal.symbol;
    _focusSymbol = chosen.signal.symbol;
    final start = chosen.result.score >= startScore &&
        chosen.result.confidence >= 65;
    final action = switched
        ? FocusActionV2.switchFocus
        : (start ? FocusActionV2.startNow : FocusActionV2.wait);

    final reasons = <String>[
      if (switched) 'فوکوس قبلی ضعیف شد → تعویض به ${chosen.signal.symbol}',
      'امتیاز عمیق تحلیل: ${chosen.result.score.toStringAsFixed(0)} / ۱۰۰',
      'اطمینان: ${chosen.result.confidence}٪',
      'رژیم: ${chosen.result.regimeFa}',
      'روند اصلی: ${chosen.result.trendMainFa}',
      ...chosen.result.reasonsFa.take(5),
      'کندل و چندتایم‌فریم بررسی شد؛ بدون افزایش مصنوعی امتیاز',
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

  factory FocusSnapshotV2.empty(DateTime now, String source) => FocusSnapshotV2(
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
