import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/ai_analyst.dart';

void main() {
  test('parses and clamps AI confidence', () {
    final analysis = AiAnalysis.fromJson({
      'symbol': 'BTCUSDT',
      'side': 'LONG',
      'summary': 'Trend is constructive.',
      'trend': 'BULLISH',
      'momentum': 'POSITIVE',
      'risk_level': 'MEDIUM',
      'signal_quality': 'GOOD',
      'recommendation': 'LONG_BIAS',
      'confidence': 127,
      'reasons': ['EMA alignment', 'RSI confirmation'],
    });

    expect(analysis.symbol, 'BTCUSDT');
    expect(analysis.recommendation, 'LONG_BIAS');
    expect(analysis.confidence, 100);
    expect(analysis.reasons.length, 2);
  });

  test('uses safe defaults for missing AI fields', () {
    final analysis = AiAnalysis.fromJson(const {});

    expect(analysis.recommendation, 'WATCH');
    expect(analysis.confidence, 0);
    expect(analysis.reasons, isEmpty);
  });
}
