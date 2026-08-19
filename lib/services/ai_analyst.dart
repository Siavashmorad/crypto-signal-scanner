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
        confidence: (json['confidence'] as num?)?.round().clamp(0, 100) ?? 0,
        reasons: (json['reasons'] as List?)
                ?.map((e) => '$e')
                .where((e) => e.trim().isNotEmpty)
                .toList() ??
            const [],
      );
}

class AiAnalystService {
  static const backendUrl = String.fromEnvironment('AI_BACKEND_URL');
  final http.Client client;

  AiAnalystService({http.Client? client}) : client = client ?? http.Client();

  bool get configured => backendUrl.trim().isNotEmpty;

  Future<AiAnalysis> analyze({
    required MarketSignal signal,
    required String username,
    required String password,
  }) async {
    if (!configured) {
      throw StateError('AI backend is not configured for this build.');
    }

    final uri = Uri.parse('${backendUrl.replaceAll(RegExp(r'/+$'), '')}/ai/analyze');
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
        .timeout(const Duration(seconds: 35));

    if (response.statusCode != 200) {
      throw StateError('AI analysis failed (${response.statusCode}).');
    }

    return AiAnalysis.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
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
