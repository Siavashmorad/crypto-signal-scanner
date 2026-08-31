import 'dart:convert';

import 'package:http/http.dart' as http;
import '../models/market_data.dart';

class AiAnalysis {
  final String symbol;
  final String side;
  final String summary;
  final String trend;
  final String momentum;
  final String riskLevel;
  final String signalQuality;
  final String bullCase;
  final String bearCase;
  final String invalidation;
  final String recommendation;
  final int confidence;
  final List<String> reasons;
  final String source; // local | remote

  const AiAnalysis({
    required this.symbol,
    required this.side,
    required this.summary,
    required this.trend,
    required this.momentum,
    required this.riskLevel,
    required this.signalQuality,
    required this.bullCase,
    required this.bearCase,
    required this.invalidation,
    required this.recommendation,
    required this.confidence,
    required this.reasons,
    this.source = 'local',
  });

  factory AiAnalysis.fromJson(Map<String, dynamic> json) => AiAnalysis(
        symbol: '${json['symbol'] ?? ''}',
        side: '${json['side'] ?? ''}',
        summary: '${json['summary'] ?? ''}',
        trend: '${json['trend'] ?? 'UNKNOWN'}',
        momentum: '${json['momentum'] ?? 'UNKNOWN'}',
        riskLevel: '${json['risk_level'] ?? 'UNKNOWN'}',
        signalQuality: '${json['signal_quality'] ?? 'UNKNOWN'}',
        bullCase: '${json['bull_case'] ?? ''}',
        bearCase: '${json['bear_case'] ?? ''}',
        invalidation: '${json['invalidation'] ?? ''}',
        recommendation: '${json['recommendation'] ?? 'WATCH'}',
        confidence:
            ((json['confidence'] as num?)?.round() ?? 0).clamp(0, 100).toInt(),
        reasons: (json['reasons'] as List?)
                ?.map((e) => '$e')
                .where((e) => e.trim().isNotEmpty)
                .toList() ??
            const [],
        source: '${json['source'] ?? 'remote'}',
      );
}

class AiAnalystService {
  static const backendUrl = String.fromEnvironment('AI_BACKEND_URL');
  final http.Client client;

  AiAnalystService({http.Client? client}) : client = client ?? http.Client();

  bool get configured => true;
  bool get remoteConfigured => backendUrl.trim().isNotEmpty;

  Future<AiAnalysis> analyze({
    required MarketSignal signal,
    required String username,
    required String password,
  }) async {
    if (remoteConfigured) {
      try {
        return await _remoteAnalyze(
          signal: signal,
          username: username,
          password: password,
        );
      } catch (_) {
        // Offline/local fallback keeps analysis available without weakening gates.
      }
    }
    return _localAnalyze(signal);
  }

  Future<AiAnalysis> _remoteAnalyze({
    required MarketSignal signal,
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse(
        '${backendUrl.replaceAll(RegExp(r'/+$'), '')}/ai/analyze');
    final basic = base64Encode(utf8.encode('$username:$password'));
    final response = await client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic $basic',
          },
          body: jsonEncode({'signal': _enrichedSignalJson(signal)}),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw StateError('AI analysis failed (${response.statusCode}).');
    }

    final parsed = AiAnalysis.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );

    // The model may explain a setup, but it may not manufacture confidence
    // above the measured scanner evidence supplied to it.
    final cappedConfidence = parsed.confidence.clamp(
      0,
      signal.confidence.round().clamp(0, 100),
    );
    return AiAnalysis(
      symbol: parsed.symbol.isEmpty ? signal.symbol : parsed.symbol,
      side: parsed.side.isEmpty ? signal.side : parsed.side,
      summary: parsed.summary,
      trend: parsed.trend,
      momentum: parsed.momentum,
      riskLevel: parsed.riskLevel,
      signalQuality: parsed.signalQuality,
      bullCase: parsed.bullCase,
      bearCase: parsed.bearCase,
      invalidation: parsed.invalidation,
      recommendation: parsed.recommendation,
      confidence: cappedConfidence,
      reasons: parsed.reasons,
      source: 'remote',
    );
  }

  /// Local multi-factor analyst. It deliberately uses only measured signal
  /// fields and freshness/risk geometry; it does not invent market facts.
  AiAnalysis _localAnalyze(MarketSignal signal) {
    final baseConfidence = signal.confidence.clamp(0, 100).toDouble();
    final rr = signal.riskReward;
    final atrPct = signal.entry > 0 ? (signal.atr / signal.entry) * 100 : 0;
    final isLong = signal.side.toUpperCase() == 'LONG';
    final ageSeconds = DateTime.now().difference(signal.timestamp).inSeconds;
    final freshnessPenalty = ageSeconds <= 60
        ? 0
        : ageSeconds <= 300
            ? 3
            : ageSeconds <= 900
                ? 8
                : 15;
    final rrPenalty = rr < 1.2 ? 12 : rr < 1.5 ? 7 : rr < 1.8 ? 3 : 0;
    final riskPenalty = atrPct >= 4 ? 12 : atrPct >= 2.5 ? 7 : atrPct >= 1.2 ? 2 : 0;
    final evidenceConfidence =
        (baseConfidence - freshnessPenalty - rrPenalty - riskPenalty)
            .clamp(0, 100)
            .round();

    final trend = baseConfidence >= 75
        ? (isLong ? 'صعودی قوی' : 'نزولی قوی')
        : baseConfidence >= 65
            ? (isLong ? 'صعودی' : 'نزولی')
            : 'خنثی متمایل به ${isLong ? 'صعود' : 'نزول'}';

    final momentum = baseConfidence >= 70
        ? 'هم‌راستا با سیگنال'
        : baseConfidence >= 60
            ? 'متوسط'
            : 'ضعیف / نیازمند تأیید بیشتر';

    final risk = atrPct >= 2.5
        ? 'بالا (نوسان زیاد)'
        : atrPct >= 1.2
            ? 'متوسط'
            : 'کنترل‌شده';

    final quality = evidenceConfidence >= 82 && rr >= 1.8
        ? 'عالی'
        : evidenceConfidence >= 72 && rr >= 1.5
            ? 'خوب'
            : evidenceConfidence >= 60
                ? 'قابل‌قبول'
                : 'ضعیف';

    final recommendation = evidenceConfidence >= 78 && rr >= 1.5 && freshnessPenalty < 15
        ? (isLong ? 'LONG_BIAS' : 'SHORT_BIAS')
        : evidenceConfidence >= 62
            ? 'WATCH'
            : 'AVOID';

    final reasons = <String>[
      'امتیاز پایه موتور: ${baseConfidence.toStringAsFixed(0)} از ۱۰۰',
      'اطمینان تعدیل‌شده با تازگی و ریسک: $evidenceConfidence از ۱۰۰',
      'نسبت ریسک به بازده: ۱:${rr.toStringAsFixed(1)}',
      'نوسان ATR نسبت به قیمت: ${atrPct.toStringAsFixed(2)}٪',
      ageSeconds < 0
          ? 'زمان سیگنال غیرعادی است؛ با احتیاط بررسی شود'
          : 'سن سیگنال: ${ageSeconds}s',
      isLong ? 'جهت سیگنال: LONG' : 'جهت سیگنال: SHORT',
    ];

    return AiAnalysis(
      symbol: signal.symbol,
      side: signal.side,
      summary: isLong
          ? 'تحلیل ترکیبی: ساختار فعلی تمایل صعودی دارد؛ کیفیت $quality و ریسک $risk است. قبل از هر تصمیم، وضعیت داده و گیت زنده بررسی شود.'
          : 'تحلیل ترکیبی: ساختار فعلی تمایل نزولی دارد؛ کیفیت $quality و ریسک $risk است. برای اسپات اقدام خرید انجام نشود.',
      trend: trend,
      momentum: momentum,
      riskLevel: risk,
      signalQuality: quality,
      bullCase: isLong
          ? 'حفظ ساختار بالای ورود و رسیدن مرحله‌ای به اهداف'
          : 'ادامه فشار فروش تا اهداف در صورت حفظ ساختار نزولی',
      bearCase: isLong
          ? 'شکست حد ضرر ${signal.stopLoss.toStringAsFixed(6)} سناریوی صعودی را باطل می‌کند'
          : 'بازگشت بالای حد ضرر ${signal.stopLoss.toStringAsFixed(6)} سناریوی نزولی را باطل می‌کند',
      invalidation: isLong
          ? 'بسته‌شدن زیر ${signal.stopLoss.toStringAsFixed(6)}'
          : 'بسته‌شدن بالای ${signal.stopLoss.toStringAsFixed(6)}',
      recommendation: recommendation,
      confidence: evidenceConfidence,
      reasons: reasons,
      source: 'local',
    );
  }

  Map<String, dynamic> _enrichedSignalJson(MarketSignal signal) {
    final age = DateTime.now().difference(signal.timestamp).inSeconds;
    final stopDistancePct = signal.entry > 0
        ? ((signal.entry - signal.stopLoss).abs() / signal.entry) * 100
        : 0.0;
    final targetDistancePct = signal.entry > 0
        ? ((signal.tp1 - signal.entry).abs() / signal.entry) * 100
        : 0.0;
    return {
      ..._signalJson(signal),
      'data_age_seconds': age.clamp(0, 86400),
      'stop_distance_pct': stopDistancePct,
      'tp1_distance_pct': targetDistancePct,
      'evidence': {
        'fresh': age <= 300,
        'risk_reward_ok': signal.riskReward >= 1.5,
        'side': signal.side.toUpperCase(),
      },
    };
  }

  Map<String, dynamic> _signalJson(MarketSignal signal) => {
        'symbol': signal.symbol,
        'side': signal.side,
        'timeframe': signal.timeframe,
        'entry': signal.entry,
        'stop_loss': signal.stopLoss,
        'tp1': signal.tp1,
        'tp2': signal.tp2,
        'tp3': signal.tp3,
        'atr': signal.atr,
        'confidence': signal.confidence,
        'risk_reward': signal.riskReward,
        'timestamp': signal.timestamp.toUtc().toIso8601String(),
      };

  void dispose() => client.close();
}
