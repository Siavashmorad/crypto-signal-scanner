import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/live_trading_gate.dart';
import 'package:crypto_signal_scanner/services/signal_journal.dart';

JournalEntry pe(double r, JournalOutcome o) => JournalEntry(
      id: 't_${r}_$o',
      timestamp: DateTime.now(),
      symbol: 'BTCUSDT',
      timeframe: '15m',
      side: 'LONG',
      regime: 'TRENDING BULL',
      quality: 'A',
      score: 80,
      confidence: 80,
      entry: 100,
      stopLoss: 95,
      tp1: 110,
      tp2: 115,
      tp3: 120,
      riskReward: 2,
      mode: JournalMode.paper,
      outcome: o,
      rMultiple: r,
    );

void main() {
  test('disables live when sample insufficient', () {
    final g = LiveTradingGate(minSample: 20);
    final d = g.evaluate(
      journal: [pe(1, JournalOutcome.win)],
      quality: 'A',
      regime: 'TRENDING BULL',
      userLiveEnabled: true,
      dataHealthy: true,
    );
    expect(d.allowLive, isFalse);
    expect(d.reason.contains('DISABLED') || d.reason.contains('INSUFFICIENT'),
        isTrue);
  });

  test('user live off → paper only', () {
    final g = LiveTradingGate();
    final d = g.evaluate(
      journal: [],
      quality: 'A+',
      regime: 'TRENDING BULL',
      userLiveEnabled: false,
      dataHealthy: true,
    );
    expect(d.allowLive, isFalse);
    expect(d.paperOnly, isTrue);
  });
}
