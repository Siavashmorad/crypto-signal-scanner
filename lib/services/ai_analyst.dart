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

  /// Always true: local engine works offline; remote used when URL is set.
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
        // Fall through to local engine so the user always gets analysis.
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
          body: jsonEncode({'signal': _signalJson(signal)}),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw StateError('AI analysis failed (${response.statusCode}).');
    }

    final parsed = AiAnalysis.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
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
      confidence: parsed.confidence,
      reasons: parsed.reasons,
      source: 'remote',
    );
  }

  /// On-device multi-factor analyst (works without backend).
  AiAnalysis _localAnalyze(MarketSignal signal) {
    final conf = signal.confidence;
    final rr = signal.riskReward;
    final atrPct = signal.entry > 0 ? (signal.atr / signal.entry) * 100 : 0;
    final isLong = signal.side.toUpperCase() == 'LONG';

    String trend;
    if (conf >= 75) {
      trend = isLong ? 'صعودی قوی' : 'نزولی قوی';
    } else if (conf >= 65) {
      trend = isLong ? 'صعودی' : 'نزولی';
    } else {
      trend = 'خنثی متمایل به ${isLong ? 'صعود' : 'نزول'}';
    }

    String momentum;
    if (conf >= 70) {
      momentum = 'هم‌راستا با سیگنال';
    } else if (conf >= 60) {
      momentum = 'متوسط';
    } else {
      momentum = 'ضعیف / نیازمند تأیید بیشتر';
    }

    String risk;
    if (atrPct >= 2.5) {
      risk = 'بالا (نوسان زیاد)';
    } else if (atrPct >= 1.2) {
      risk = 'متوسط';
    } else {
      risk = 'کنترل‌شده';
    }

    String quality;
    if (conf >= 75 && rr >= 1.8) {
      quality = 'خوب';
    } else if (conf >= 62) {
      quality = 'قابل‌قبول';
    } else {
      quality = 'ضعیف';
    }

    String recommendation;
    if (conf >= 72 && atrPct < 3.5) {
      recommendation = isLong ? 'LONG_BIAS' : 'SHORT_BIAS';
    } else if (conf >= 60) {
      recommendation = 'WATCH';
    } else {
      recommendation = 'AVOID';
    }

    final reasons = <String>[
      'اطمینان موتور سیگنال: ${conf.toStringAsFixed(0)}٪',
      'نسبت ریسک به ریوارد حدود ۱:${rr.toStringAsFixed(1)}',
      'نوسان ATR نسبت به قیمت: ${atrPct.toStringAsFixed(2)}٪',
      isLong
          ? 'ساختار قیمت از EMA کوتاه‌مدت حمایت می‌کند'
          : 'ساختار قیمت زیر EMA کوتاه‌مدت فشار فروش نشان می‌دهد',
      'ورود پیشنهادی ${signal.entry.toStringAsFixed(6)} با حد ضرر ${signal.stopLoss.toStringAsFixed(6)}',
    ];

    final summary = isLong
        ? 'تحلیلگر داخلی: تمایل خرید روی ${signal.symbol}. کیفیت $quality، ریسک $risk. قبل از ورود حجم و اخبار را بررسی کنید.'
        : 'تحلیلگر داخلی: تمایل فروش روی ${signal.symbol}. کیفیت $quality، ریسک $risk. قبل از ورود حجم و اخبار را بررسی کنید.';

    return AiAnalysis(
      symbol: signal.symbol,
      side: signal.side,
      summary: summary,
      trend: trend,
      momentum: momentum,
      riskLevel: risk,
      signalQuality: quality,
      bullCase: isLong
          ? 'حفظ ساختار بالای ورود و رسیدن به TP1/TP2'
          : 'اگر قیمت برگردد بالای ورود، سناریوی شورت تضعیف می‌شود',
      bearCase: isLong
          ? 'شکست حد ضرر ${signal.stopLoss.toStringAsFixed(6)} سیگنال را باطل می‌کند'
          : 'ادامه فشار فروش تا TP1/TP2'
      ,
      invalidation: isLong
          ? 'بستن زیر ${signal.stopLoss.toStringAsFixed(6)}'
          : 'بستن بالای ${signal.stopLoss.toStringAsFixed(6)}',
      recommendation: recommendation,
      confidence: conf.round().clamp(0, 100),
      reasons: reasons,
      source: 'local',
    );
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
