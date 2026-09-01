import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import 'coin_analysis_service.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

/// Multi-timeframe focus layer.
/// Uses real scanner/indicator evidence, ranks candidates, and never creates orders.
class FocusCoinServiceV2 {
  FocusCoinServiceV2({TabdealApi? api, ScannerService? scanner})
      : api = api ?? TabdealApi(),
        scanner = scanner ?? ScannerService(api ?? TabdealApi()),
        analysis = CoinAnalysisService(api: api ?? TabdealApi());

  final TabdealApi api;
  final ScannerService scanner;
  final CoinAnalysisService analysis;

  static const int candidateCount = 8;
  static const double keepScore = 82;
  static const double startScore = 93;
  static const int startConfidence = 78;
  static const double startRiskReward = 1.8;
  static const double switchAdvantage = 3.0;
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

  Future<List<MarketSignal>> _multiTimeframeScan({int maxSymbols = 40}) async {
    final timeframes = <Duration>[
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(hours: 1),
      const Duration(hours: 4),
    ];
    final bySymbol = <String, MarketSignal>{};
    for (final tf in timeframes) {
      try {
        final signals = await scanner.scanAll(
          timeframe: tf,
          maxSymbols: maxSymbols,
          maxSignals: 12,
          preferSpot: true,
        );
        for (final signal in signals) {
          if (signal.side.toUpperCase() != 'LONG') continue;
          final old = bySymbol[signal.symbol];
          if (old == null || signal.confidence > old.confidence) {
            bySymbol[signal.symbol] = signal;
          }
        }
      } catch (_) {}
    }
    final result = bySymbol.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return result.take(candidateCount + 4).toList();
  }

  double _timeframeAlignment(CoinAnalysisResult r) {
    final available = r.timeframes.where((t) => t.available).toList();
    if (available.isEmpty) return 0;
    var points = 0.0;
    var maxPoints = 0.0;
    for (final tf in available) {
      final weight = switch (tf.key.toLowerCase()) {
        '4h' => 1.5,
        '1h' => 1.35,
        '15m' => 1.0,
        '5m' => 0.8,
        _ => 1.0,
      };
      maxPoints += weight;
      if (tf.bias.toUpperCase() == 'LONG') points += weight;
      if (tf.bias.toUpperCase() == 'SHORT') points -= weight * 0.8;
    }
    return ((points / maxPoints) * 100).clamp(0, 100);
  }

  double _momentumQuality(CoinAnalysisResult r) {
    final available = r.timeframes.where((t) => t.available).toList();
    if (available.isEmpty) return 0;
    var score = 0.0;
    var count = 0.0;
    for (final tf in available) {
      if (tf.adx != null) {
        score += (tf.adx! >= 25 ? 100 : tf.adx! >= 20 ? 75 : 45);
        count += 1;
      }
      if (tf.rsi != null) {
        final rsi = tf.rsi!;
        score += rsi >= 52 && rsi <= 72
            ? 100
            : rsi >= 48 && rsi <= 76
                ? 70
                : rsi > 76
                    ? 25
                    : 40;
        count += 1;
      }
    }
    return count == 0 ? 0 : (score / count).clamp(0, 100);
  }

  double _freshnessQuality(CoinAnalysisResult r) {
    if (r.dataInsufficient || r.dataStale) return 0;
    final age = r.dataAgeSeconds;
    if (age <= 30) return 100;
    if (age <= 120) return 92;
    if (age <= 300) return 80;
    if (age <= 600) return 55;
    return 20;
  }

  double _riskQuality(CoinAnalysisResult r) {
    final rr = r.riskReward ?? 0;
    if (rr < 1.4) return 0;
    if (rr >= 2.5) return 100;
    if (rr >= 2.0) return 92;
    if (rr >= 1.8) return 84;
    return 70;
  }

  double _composite(CoinAnalysisResult r) {
    final alignment = _timeframeAlignment(r);
    final momentum = _momentumQuality(r);
    final freshness = _freshnessQuality(r);
    final risk = _riskQuality(r);
    final raw = r.score * 0.45 +
        r.confidence * 0.20 +
        alignment * 0.18 +
        momentum * 0.08 +
        freshness * 0.04 +
        risk * 0.05;
    return raw.clamp(0, 100);
  }

  Future<FocusSnapshotV2> tick({
    Duration timeframe = const Duration(minutes: 15),
    int maxSymbols = 40,
  }) async {
    await _restoreFocus();
    final previousFocus = _focusSymbol;
    final now = DateTime.now();

    final scanned = await _multiTimeframeScan(maxSymbols: maxSymbols);
    if (scanned.isEmpty) {
      await _saveFocus(null);
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    final pool = <MarketSignal>[];
    if (previousFocus != null) {
      final current = scanned.where((s) => s.symbol == previousFocus);
      pool.addAll(current);
    }
    for (final signal in scanned) {
      if (pool.any((x) => x.symbol == signal.symbol)) continue;
      pool.add(signal);
      if (pool.length >= candidateCount) break;
    }

    final evaluated = <_FocusCandidate>[];
    for (final signal in pool) {
      try {
        final r = await analysis.analyze(signal.symbol, preferSpot: true);
        final alignment = _timeframeAlignment(r);
        final usable = !r.dataStale &&
            !r.dataInsufficient &&
            r.decision == CoinDecision.buy &&
            r.hasTradePlan &&
            (r.riskReward ?? 0) >= 1.4 &&
            alignment >= 55 &&
            _freshnessQuality(r) >= 55;
        if (usable) {
          evaluated.add(_FocusCandidate(signal, r, _composite(r)));
        }
      } catch (_) {}
    }

    evaluated.sort((a, b) => b.composite.compareTo(a.composite));
    if (evaluated.isEmpty) {
      await _saveFocus(null);
      return FocusSnapshotV2.empty(now, scanner.dataSource);
    }

    _FocusCandidate? current;
    for (final candidate in evaluated) {
      if (candidate.signal.symbol == previousFocus) {
        current = candidate;
        break;
      }
    }

    final best = evaluated.first;
    final keepCurrent = current != null &&
        current.result.score >= keepScore &&
        current.result.confidence >= startConfidence &&
        current.composite >= best.composite - switchAdvantage;
    final chosen = keepCurrent ? current : best;
    final switched = previousFocus != null && chosen.signal.symbol != previousFocus;
    await _saveFocus(chosen.signal.symbol);

    final alignment = _timeframeAlignment(chosen.result);
    final momentum = _momentumQuality(chosen.result);
    final start = chosen.result.score >= startScore &&
        chosen.result.confidence >= startConfidence &&
        (chosen.result.riskReward ?? 0) >= startRiskReward &&
        alignment >= 70 &&
        momentum >= 60 &&
        _freshnessQuality(chosen.result) >= 80;

    final action = switched
        ? FocusActionV2.switchFocus
        : (start ? FocusActionV2.startNow : FocusActionV2.wait);

    final reasons = <String>[
      if (switched)
        'فوکوس قبلی ضعیف‌تر شد → تعویض به ${chosen.signal.symbol}',
      'امتیاز ترکیبی: ${chosen.composite.toStringAsFixed(0)} / ۱۰۰',
      'امتیاز موتور تحلیل: ${chosen.result.score.toStringAsFixed(0)} / ۱۰۰',
      'اطمینان: ${chosen.result.confidence}٪',
      'هم‌جهتی چندتایم‌فریم: ${alignment.toStringAsFixed(0)}٪',
      'کیفیت مومنتوم/قدرت روند: ${momentum.toStringAsFixed(0)}٪',
      'رژیم: ${chosen.result.regimeFa}',
      'روند اصلی: ${chosen.result.trendMainFa}',
      'نسبت سود به زیان: ۱:${(chosen.result.riskReward ?? 0).toStringAsFixed(1)}',
      ...chosen.result.reasonsFa.take(4),
      'تأیید ۵دقیقه، ۱۵دقیقه، ۱ساعت و ۴ساعت؛ امتیاز مصنوعی اضافه نمی‌شود',
      if (!start) 'تأیید کامل برای شروع هنوز برقرار نیست؛ فقط هشدار/تحت نظر',
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
          'هیچ موقعیت LONG پس از تأیید چندتایم‌فریم تأیید نشد',
          'امتیاز مصنوعی اضافه نشد؛ فعلاً انتظار',
        ],
        at: now,
        dataSource: source,
        signal: null,
      );
}
