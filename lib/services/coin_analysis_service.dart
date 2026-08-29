import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import 'binance_public.dart';
import 'chart_indicators.dart';
import 'fa_labels.dart';
import 'quant_signal_engine.dart';
import 'scanner_service.dart';
import 'tabdeal_api.dart';

/// Final decision shown to the user (Persian labels via [decisionLabel]).
enum CoinDecision {
  buy,
  sell,
  wait,
  noTrade,
}

extension CoinDecisionFa on CoinDecision {
  /// User-facing decision. SPOT never presents sell as actionable short.
  String get label => switch (this) {
        CoinDecision.buy => 'خرید / صعودی',
        CoinDecision.sell => 'عدم خرید / انتظار',
        CoinDecision.wait => 'انتظار',
        CoinDecision.noTrade => 'بدون معامله',
      };

  /// Explicit SPOT action line for UI.
  String get spotActionFa => switch (this) {
        CoinDecision.buy => '✅ امکان بررسی ورود اسپات',
        CoinDecision.sell => '⛔ عدم خرید / انتظار (شورت اسپات نیست)',
        CoinDecision.wait => '🟡 انتظار',
        CoinDecision.noTrade => '⛔ بدون معامله',
      };

  String get emoji => switch (this) {
        CoinDecision.buy => '🟢',
        CoinDecision.sell => '🔴',
        CoinDecision.wait => '🟡',
        CoinDecision.noTrade => '⚪',
      };
}

/// One timeframe bias snapshot for multi-TF panel.
class TfBias {
  final String labelFa;
  final String key;
  final String bias; // LONG / SHORT / NEUTRAL / INSUFFICIENT
  final double? rsi;
  final double? adx;
  final bool available;

  const TfBias({
    required this.labelFa,
    required this.key,
    required this.bias,
    this.rsi,
    this.adx,
    this.available = true,
  });

  String get biasFa {
    switch (bias.toUpperCase()) {
      case 'LONG':
      case 'BUY':
        return 'صعودی';
      case 'SHORT':
      case 'SELL':
        return 'نزولی';
      case 'INSUFFICIENT':
        return 'داده ناکافی';
      default:
        return 'خنثی';
    }
  }
}

/// Immutable result of a single-coin multi-TF analysis.
class CoinAnalysisResult {
  final String symbol;
  final CoinDecision decision;
  final double score;
  final int confidence;
  final String tierFa;
  final String regimeFa;
  final String trendShortFa;
  final String trendMidFa;
  final String trendMainFa;
  final double? lastPrice;
  final DateTime analyzedAt;
  final int dataAgeSeconds;
  final bool dataStale;
  final bool dataInsufficient;
  final List<String> reasonsFa;
  final List<String> noTradeReasonsFa;
  final List<TfBias> timeframes;
  final List<double> supports;
  final List<double> resistances;
  final double? entry;
  final double? stopLoss;
  final double? tp1;
  final double? tp2;
  final double? tp3;
  final double? riskReward;
  final bool conflictAcrossTf;
  final String dataSource;
  final QuantDecision? quant;
  final bool spotContext;

  const CoinAnalysisResult({
    required this.symbol,
    required this.decision,
    required this.score,
    required this.confidence,
    required this.tierFa,
    required this.regimeFa,
    required this.trendShortFa,
    required this.trendMidFa,
    required this.trendMainFa,
    required this.lastPrice,
    required this.analyzedAt,
    required this.dataAgeSeconds,
    required this.dataStale,
    required this.dataInsufficient,
    required this.reasonsFa,
    required this.noTradeReasonsFa,
    required this.timeframes,
    required this.supports,
    required this.resistances,
    this.entry,
    this.stopLoss,
    this.tp1,
    this.tp2,
    this.tp3,
    this.riskReward,
    required this.conflictAcrossTf,
    required this.dataSource,
    this.quant,
    this.spotContext = true,
  });

  bool get hasTradePlan =>
      entry != null &&
      stopLoss != null &&
      tp1 != null &&
      (riskReward ?? 0) >= 1.2 &&
      decision != CoinDecision.noTrade &&
      decision != CoinDecision.wait;

  Map<String, dynamic> toHistoryJson() => {
        'symbol': symbol,
        'score': score,
        'decision': decision.name,
        'price': lastPrice,
        'at': analyzedAt.toIso8601String(),
      };

  static CoinAnalysisResult? fromHistoryJson(Map<String, dynamic> j) {
    final sym = '${j['symbol'] ?? ''}';
    if (sym.isEmpty) return null;
    final decName = '${j['decision'] ?? 'noTrade'}';
    final dec = CoinDecision.values.firstWhere(
      (e) => e.name == decName,
      orElse: () => CoinDecision.noTrade,
    );
    final score = (j['score'] as num?)?.toDouble() ?? 0;
    return CoinAnalysisResult(
      symbol: sym,
      decision: dec,
      score: score,
      confidence: score.round(),
      tierFa: FaLabels.scoreTier(score),
      regimeFa: '—',
      trendShortFa: '—',
      trendMidFa: '—',
      trendMainFa: '—',
      lastPrice: (j['price'] as num?)?.toDouble(),
      analyzedAt: DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now(),
      dataAgeSeconds: 0,
      dataStale: false,
      dataInsufficient: false,
      reasonsFa: const [],
      noTradeReasonsFa: const [],
      timeframes: const [],
      supports: const [],
      resistances: const [],
      conflictAcrossTf: false,
      dataSource: 'history',
    );
  }
}

/// Decision / analysis layer for the «تحلیل ارز» tab.
/// Reuses ScannerService trades, ChartIndicators, MarketRegime, QuantSignalEngine.
/// Does NOT place orders. Does NOT change api1.tabdeal.org.
class CoinAnalysisService {
  CoinAnalysisService({
    required this.api,
    ScannerService? scanner,
    QuantSignalEngine? quant,
    MarketRegimeDetector? regime,
    BinancePublic? binance,
  })  : scanner = scanner ?? ScannerService(api),
        quant = quant ?? QuantSignalEngine(),
        regime = regime ?? MarketRegimeDetector(),
        binance = binance ?? BinancePublic();

  final TabdealApi api;
  final ScannerService scanner;
  final QuantSignalEngine quant;
  final MarketRegimeDetector regime;
  final BinancePublic binance;

  static const _historyKey = 'coin_analysis_history_v1';
  static const _watchlistKey = 'coin_analysis_watchlist_v1';
  static const int maxHistory = 30;
  static const int staleSeconds = 120;

  /// Normalize user input: BTC / btc / BTCUSDT → BTCUSDT
  String normalizeInput(String raw) {
    var s = api.normalizeSymbol(raw.trim());
    if (s.isEmpty) return '';
    if (!s.endsWith('USDT') && !s.endsWith('IRT') && !s.endsWith('TMN')) {
      s = '${s}USDT';
    }
    return s;
  }

  Future<List<TradePoint>> _trades(String symbol) async {
    try {
      final t = await api.trades(symbol, limit: 500);
      if (t.isNotEmpty) return t;
    } catch (_) {}
    try {
      return await binance.trades(symbol, limit: 500);
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> _depth(String symbol) async {
    try {
      final d = await api.depth(symbol);
      if ((d['bids'] as List?)?.isNotEmpty == true) return d;
    } catch (_) {}
    try {
      final d = await api.futuresDepth(symbol);
      if ((d['bids'] as List?)?.isNotEmpty == true) return d;
    } catch (_) {}
    try {
      return await binance.depth(symbol);
    } catch (_) {
      return {'bids': [], 'asks': []};
    }
  }

  TfBias _tfBias(String key, String labelFa, List<Candle> candles) {
    if (candles.length < 20) {
      return TfBias(
        labelFa: labelFa,
        key: key,
        bias: 'INSUFFICIENT',
        available: false,
      );
    }
    final closes = candles.map((c) => c.close).toList();
    final e9 = _lastEma(closes, 9);
    final e21 = _lastEma(closes, 21);
    final rsi = ChartIndicators.lastRsi(candles) ?? 50;
    final adxPack = ChartIndicators.adx(candles);
    String bias = 'NEUTRAL';
    if (e9 != null && e21 != null) {
      if (e9 > e21 && rsi >= 45) {
        bias = 'LONG';
      } else if (e9 < e21 && rsi <= 55) {
        bias = 'SHORT';
      }
    }
    return TfBias(
      labelFa: labelFa,
      key: key,
      bias: bias,
      rsi: rsi,
      adx: adxPack.adx,
      available: true,
    );
  }

  double? _lastEma(List<double> closes, int period) {
    if (closes.length < period) return null;
    var ema = closes.take(period).reduce((a, b) => a + b) / period;
    final k = 2 / (period + 1);
    for (final v in closes.skip(period)) {
      ema = (v - ema) * k + ema;
    }
    return ema;
  }

  String _regimeFa(MarketRegime r) {
    switch (r) {
      case MarketRegime.trendingBull:
        return 'روند صعودی';
      case MarketRegime.trendingBear:
        return 'روند نزولی';
      case MarketRegime.ranging:
        return 'رنج';
      case MarketRegime.highVolatility:
        return 'نوسان شدید';
      case MarketRegime.lowVolatility:
        return 'نوسان کم';
      case MarketRegime.breakout:
        return 'شکست مقاومت';
      case MarketRegime.breakdown:
        return 'شکست حمایت';
      case MarketRegime.choppy:
        return 'بازار نامنظم';
      case MarketRegime.unknown:
        return 'نامشخص';
    }
  }

  String _trendFa(String bias) {
    switch (bias.toUpperCase()) {
      case 'LONG':
      case 'BUY':
        return 'صعودی';
      case 'SHORT':
      case 'SELL':
        return 'نزولی';
      case 'INSUFFICIENT':
        return 'داده ناکافی';
      default:
        return 'خنثی';
    }
  }

  List<double> _supportLevels(List<Candle> c, {int max = 3}) {
    if (c.length < 20) return const [];
    final lows = <double>[];
    for (var i = 2; i < c.length - 2; i++) {
      final l = c[i].low;
      if (l <= c[i - 1].low &&
          l <= c[i - 2].low &&
          l <= c[i + 1].low &&
          l <= c[i + 2].low) {
        lows.add(l);
      }
    }
    if (lows.isEmpty) return const [];
    lows.sort();
    final last = c.last.close;
    final below = lows.where((x) => x < last).toList();
    if (below.isEmpty) return [lows.last];
    return below.reversed.take(max).toList();
  }

  List<double> _resistanceLevels(List<Candle> c, {int max = 3}) {
    if (c.length < 20) return const [];
    final highs = <double>[];
    for (var i = 2; i < c.length - 2; i++) {
      final h = c[i].high;
      if (h >= c[i - 1].high &&
          h >= c[i - 2].high &&
          h >= c[i + 1].high &&
          h >= c[i + 2].high) {
        highs.add(h);
      }
    }
    if (highs.isEmpty) return const [];
    highs.sort();
    final last = c.last.close;
    final above = highs.where((x) => x > last).toList();
    if (above.isEmpty) return [highs.first];
    return above.take(max).toList();
  }

  /// Full multi-TF analysis for one symbol. Spot-first context.
  Future<CoinAnalysisResult> analyze(
    String rawSymbol, {
    bool preferSpot = true,
  }) async {
    final symbol = normalizeInput(rawSymbol);
    final now = DateTime.now();
    if (symbol.isEmpty) {
      return CoinAnalysisResult(
        symbol: rawSymbol,
        decision: CoinDecision.noTrade,
        score: 0,
        confidence: 0,
        tierFa: FaLabels.scoreTier(0),
        regimeFa: 'نامشخص',
        trendShortFa: '—',
        trendMidFa: '—',
        trendMainFa: '—',
        lastPrice: null,
        analyzedAt: now,
        dataAgeSeconds: 0,
        dataStale: false,
        dataInsufficient: true,
        reasonsFa: const [],
        noTradeReasonsFa: const ['نماد نامعتبر'],
        timeframes: const [],
        supports: const [],
        resistances: const [],
        conflictAcrossTf: false,
        dataSource: 'none',
        spotContext: preferSpot,
      );
    }

    final trades = await _trades(symbol);
    final dataSource = scanner.dataSource == 'none'
        ? (trades.isNotEmpty ? 'tabdeal/binance' : 'none')
        : scanner.dataSource;

    if (trades.length < 30) {
      return CoinAnalysisResult(
        symbol: symbol,
        decision: CoinDecision.noTrade,
        score: 0,
        confidence: 0,
        tierFa: FaLabels.scoreTier(0),
        regimeFa: 'نامشخص',
        trendShortFa: 'داده ناکافی',
        trendMidFa: 'داده ناکافی',
        trendMainFa: 'داده ناکافی',
        lastPrice: trades.isEmpty ? null : trades.last.price,
        analyzedAt: now,
        dataAgeSeconds: 0,
        dataStale: false,
        dataInsufficient: true,
        reasonsFa: const [],
        noTradeReasonsFa: const ['داده ناکافی', '⛔ فعلاً معامله نکن'],
        timeframes: const [],
        supports: const [],
        resistances: const [],
        conflictAcrossTf: false,
        dataSource: dataSource,
        spotContext: preferSpot,
      );
    }

    final lastTradeMs =
        trades.map((t) => t.timestampMs).reduce((a, b) => a > b ? a : b);
    final ageSec = ((now.millisecondsSinceEpoch - lastTradeMs) / 1000)
        .round()
        .clamp(0, 99999);
    final stale = ageSec > staleSeconds;

    final c5 = scanner.buildCandles(trades, const Duration(minutes: 5));
    final c15 = scanner.buildCandles(trades, const Duration(minutes: 15));
    final c1h = scanner.buildCandles(trades, const Duration(hours: 1));
    final c4h = scanner.buildCandles(trades, const Duration(hours: 4));
    final c1d = scanner.buildCandles(trades, const Duration(days: 1));

    final tf5 = _tfBias('5m', '۵ دقیقه', c5);
    final tf15 = _tfBias('15m', '۱۵ دقیقه', c15);
    final tf1h = _tfBias('1h', '۱ ساعت', c1h);
    final tf4h = _tfBias('4h', '۴ ساعت', c4h);
    final tf1d = c1d.length >= 15
        ? _tfBias('1d', '۱ روز', c1d)
        : const TfBias(
            labelFa: '۱ روز',
            key: '1d',
            bias: 'INSUFFICIENT',
            available: false,
          );

    final tfs = [tf5, tf15, tf1h, tf4h, if (tf1d.available) tf1d];

    final primary = c1h.length >= 20
        ? c1h
        : (c15.length >= 20 ? c15 : (c5.length >= 15 ? c5 : c1h));
    final lastPrice =
        primary.isNotEmpty ? primary.last.close : trades.last.price;

    final regimeSnap = primary.length >= 40
        ? regime.detect(primary)
        : RegimeSnapshot.unavailable('داده کافی نیست');

    final depth = await _depth(symbol);

    final atr = ChartIndicators.lastAtr(primary) ?? 0;
    final longBiasCount =
        tfs.where((t) => t.available && t.bias == 'LONG').length;
    final shortBiasCount =
        tfs.where((t) => t.available && t.bias == 'SHORT').length;
    String provisionalSide = 'WAIT';
    if (longBiasCount > shortBiasCount && longBiasCount >= 2) {
      provisionalSide = 'LONG';
    } else if (shortBiasCount > longBiasCount && shortBiasCount >= 2) {
      provisionalSide = 'SHORT';
    }

    final stopDist = atr > 0 ? atr * 1.5 : lastPrice * 0.015;
    final provisional = MarketSignal(
      symbol: symbol,
      side: provisionalSide == 'WAIT' ? 'LONG' : provisionalSide,
      timeframe: primary == c1h ? '1h' : (primary == c15 ? '15m' : '5m'),
      entry: lastPrice,
      stopLoss: provisionalSide == 'SHORT'
          ? lastPrice + stopDist
          : lastPrice - stopDist,
      tp1: provisionalSide == 'SHORT'
          ? lastPrice - stopDist
          : lastPrice + stopDist,
      tp2: provisionalSide == 'SHORT'
          ? lastPrice - stopDist * 2
          : lastPrice + stopDist * 2,
      tp3: provisionalSide == 'SHORT'
          ? lastPrice - stopDist * 3
          : lastPrice + stopDist * 3,
      atr: atr,
      confidence: 50,
      riskReward: 2,
      timestamp: now,
    );

    final candlesByTf = <String, List<Candle>>{
      if (c5.isNotEmpty) '5m': c5,
      if (c15.isNotEmpty) '15m': c15,
      if (c1h.isNotEmpty) '1h': c1h,
      if (c4h.isNotEmpty) '4h': c4h,
      if (c1d.isNotEmpty) '1d': c1d,
    };

    QuantDecision? qd;
    try {
      qd = quant.evaluate(
        signal: provisional,
        candlesByTf: candlesByTf,
        depth: depth,
      );
    } catch (_) {
      qd = null;
    }

    final activeBiases = tfs
        .where((t) => t.available && t.bias != 'NEUTRAL')
        .map((t) => t.bias)
        .toSet();
    final conflict =
        activeBiases.contains('LONG') && activeBiases.contains('SHORT');

    double score = qd?.score ?? 40;
    int confidence = qd?.confidence ?? score.round();

    if (conflict) {
      score = (score * 0.65).clamp(0, 100);
      confidence = (confidence * 0.7).round().clamp(0, 100);
    }
    if (stale) {
      score = (score * 0.5).clamp(0, 100);
      confidence = (confidence * 0.5).round().clamp(0, 100);
    }
    if (regimeSnap.regime == MarketRegime.choppy ||
        regimeSnap.regime == MarketRegime.unknown) {
      score = (score * 0.85).clamp(0, 100);
    }

    final noTrade = <String>[];
    if (stale) noTrade.add('داده قدیمی');
    if (trades.length < 40) noTrade.add('داده ناکافی');
    if (conflict) noTrade.add('⚠️ تضاد بین بازه‌های زمانی');
    if (regimeSnap.regime == MarketRegime.choppy) {
      noTrade.add('بازار نامنظم');
    }
    final relVol = ChartIndicators.relativeVolume(primary);
    if (relVol != null && relVol < 0.4) {
      noTrade.add('حجم بسیار پایین');
      score = (score * 0.8).clamp(0, 100);
    }

    CoinDecision decision;
    final dir = (qd?.direction ?? provisionalSide).toUpperCase();
    if (score < 45 || noTrade.length >= 3) {
      decision = CoinDecision.noTrade;
    } else if (dir == 'WAIT' || score < 58) {
      decision = CoinDecision.wait;
    } else if (dir == 'LONG' || dir == 'BUY') {
      decision = CoinDecision.buy;
    } else if (dir == 'SHORT' || dir == 'SELL') {
      if (preferSpot) {
        decision = score >= 70 ? CoinDecision.wait : CoinDecision.noTrade;
        noTrade.add('در بازار نقدی: عدم خرید / انتظار (شورت اسپات ممکن نیست)');
      } else {
        decision = CoinDecision.sell;
      }
    } else {
      decision = CoinDecision.wait;
    }

    if (stale && score >= 70) {
      decision = CoinDecision.wait;
      noTrade.add('⚠️ داده‌ها به‌روز نیستند — تصمیم با اطمینان بالا گرفته نشد');
    }

    if (decision == CoinDecision.noTrade || decision == CoinDecision.wait) {
      if (!noTrade.contains('⛔ فعلاً معامله نکن') && score < 70) {
        noTrade.add('⛔ فعلاً معامله نکن');
      }
    }

    final reasons = <String>[];
    reasons.add('روند کوتاه‌مدت: ${_trendFa(tf5.bias)}');
    reasons.add('روند میان‌مدت: ${_trendFa(tf1h.bias)}');
    reasons
        .add('روند اصلی: ${_trendFa(tf4h.available ? tf4h.bias : tf1h.bias)}');
    reasons.add('وضعیت بازار: ${_regimeFa(regimeSnap.regime)}');
    if (qd != null) {
      for (final r in FaLabels.reasons(qd.reasons.take(6))) {
        if (!reasons.contains(r)) reasons.add(r);
      }
    }
    if (relVol != null && relVol >= 1.2) {
      reasons.add('حجم: تأییدکننده (${relVol.toStringAsFixed(1)} برابر)');
    }

    final supports = _supportLevels(primary);
    final resistances = _resistanceLevels(primary);

    double? entry;
    double? sl;
    double? tp1;
    double? tp2;
    double? tp3;
    double? rr;
    if (qd != null &&
        (decision == CoinDecision.buy ||
            (!preferSpot && decision == CoinDecision.sell))) {
      entry = qd.entryLow ?? lastPrice;
      sl = qd.suggestedSl;
      tp1 = qd.suggestedTp1;
      tp2 = qd.suggestedTp2;
      tp3 = qd.suggestedTp3;
      rr = qd.riskReward;
      if (sl == null && atr > 0) {
        final isLong = decision == CoinDecision.buy;
        sl = isLong ? lastPrice - atr * 1.5 : lastPrice + atr * 1.5;
        tp1 = isLong ? lastPrice + atr * 1.5 : lastPrice - atr * 1.5;
        tp2 = isLong ? lastPrice + atr * 3 : lastPrice - atr * 3;
        tp3 = isLong ? lastPrice + atr * 4.5 : lastPrice - atr * 4.5;
        final risk = (lastPrice - (sl)).abs();
        final reward = (tp2 - lastPrice).abs();
        rr = risk > 0 ? reward / risk : 0;
      }
      if (rr < 1.2) {
        noTrade.add('نسبت سود به زیان ضعیف');
        reasons.add('ورود توصیه نمی‌شود (R/R ضعیف)');
      }
    }

    return CoinAnalysisResult(
      symbol: symbol,
      decision: decision,
      score: score,
      confidence: confidence.clamp(0, 100),
      tierFa: FaLabels.scoreTier(score),
      regimeFa: _regimeFa(regimeSnap.regime),
      trendShortFa: _trendFa(tf5.bias),
      trendMidFa: _trendFa(tf1h.bias),
      trendMainFa: _trendFa(tf4h.available ? tf4h.bias : tf1h.bias),
      lastPrice: lastPrice,
      analyzedAt: now,
      dataAgeSeconds: ageSec,
      dataStale: stale,
      dataInsufficient: false,
      reasonsFa: reasons,
      noTradeReasonsFa: noTrade,
      timeframes: tfs,
      supports: supports,
      resistances: resistances,
      entry: entry,
      stopLoss: sl,
      tp1: tp1,
      tp2: tp2,
      tp3: tp3,
      riskReward: rr,
      conflictAcrossTf: conflict,
      dataSource: dataSource,
      quant: qd,
      spotContext: preferSpot,
    );
  }

  /// Rank top SPOT opportunities via existing scanner (Opportunity Radar).
  Future<List<MarketSignal>> radar({
    int maxSymbols = 24,
    int maxSignals = 10,
  }) async {
    try {
      final list = await scanner.scanAll(
        timeframe: const Duration(minutes: 15),
        maxConcurrency: 8,
        maxSymbols: maxSymbols,
        maxSignals: maxSignals,
        preferSpot: true,
      );
      list.sort((a, b) => b.confidence.compareTo(a.confidence));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<CoinAnalysisResult>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) =>
              CoinAnalysisResult.fromHistoryJson(Map<String, dynamic>.from(e)))
          .whereType<CoinAnalysisResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveToHistory(CoinAnalysisResult r) async {
    final p = await SharedPreferences.getInstance();
    final existing = await loadHistory();
    final next = [
      r,
      ...existing
          .where((e) => e.symbol != r.symbol || e.analyzedAt != r.analyzedAt),
    ].take(maxHistory).toList();
    await p.setString(
      _historyKey,
      jsonEncode(next.map((e) => e.toHistoryJson()).toList()),
    );
  }

  Future<List<String>> loadWatchlist() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_watchlistKey);
    return list ?? ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT'];
  }

  Future<void> saveWatchlist(List<String> symbols) async {
    final p = await SharedPreferences.getInstance();
    final normalized =
        symbols.map(normalizeInput).where((s) => s.isNotEmpty).toSet().toList();
    await p.setStringList(_watchlistKey, normalized);
  }

  Future<void> addToWatchlist(String raw) async {
    final s = normalizeInput(raw);
    if (s.isEmpty) return;
    final list = await loadWatchlist();
    if (!list.contains(s)) {
      list.insert(0, s);
      await saveWatchlist(list);
    }
  }

  Future<void> removeFromWatchlist(String raw) async {
    final s = normalizeInput(raw);
    final list = await loadWatchlist();
    list.remove(s);
    await saveWatchlist(list);
  }
}
