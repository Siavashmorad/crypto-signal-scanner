import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/live_trading_gate.dart';
import 'package:crypto_signal_scanner/services/paper_forward.dart';
import 'package:crypto_signal_scanner/services/performance_analytics.dart';
import 'package:crypto_signal_scanner/services/signal_journal.dart';

void main() {
  test('pending resolves to closed and analytics counts closed', () {
    final entry = JournalEntry(
      id: 'paper-1',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
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
    );
    expect(entry.outcome, JournalOutcome.pending);

    final candles = [
      const Candle(
          timestampMs: 0, open: 100, high: 101, low: 99, close: 100, volume: 1),
      const Candle(
          timestampMs: 1, open: 100, high: 105, low: 99, close: 104, volume: 1),
      const Candle(
          timestampMs: 2,
          open: 104,
          high: 111,
          low: 103,
          close: 110,
          volume: 1),
    ];
    final resolved = PaperForwardResolver().resolve(entry, candles);
    expect(resolved.outcome, JournalOutcome.win);

    final closed = <JournalEntry>[
      resolved,
      ...List.generate(
        19,
        (i) => JournalEntry(
          id: 'paper-${i + 2}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(i + 1),
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
          outcome: JournalOutcome.loss,
          rMultiple: -1,
        ),
      ),
    ];
    final report = PerformanceAnalytics(minSample: 20).build(closed);
    expect(report.overallPaper.insufficientSample, isFalse);
    expect(report.overallPaper.sample, 20);
    expect(report.overallPaper.pending, 0);

    final gate = LiveTradingGate(minSample: 20).evaluate(
      journal: closed,
      quality: 'A',
      regime: 'TRENDING BULL',
      userLiveEnabled: true,
      dataHealthy: true,
    );
    expect(gate.reason.contains('INSUFFICIENT SAMPLE'), isFalse);
  });

  test('unresolved pending alone keeps insufficient sample', () {
    final pending = List.generate(
      19,
      (i) => JournalEntry(
        id: 'p$i',
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 1000),
        symbol: 'ETHUSDT',
        timeframe: '15m',
        side: 'LONG',
        regime: 'UNKNOWN',
        quality: 'B',
        score: 60,
        confidence: 60,
        entry: 100,
        stopLoss: 95,
        tp1: 110,
        tp2: 115,
        tp3: 120,
        riskReward: 2,
        mode: JournalMode.paper,
      ),
    );
    final report = PerformanceAnalytics(minSample: 20).build(pending);
    expect(report.overallPaper.insufficientSample, isTrue);
    expect(report.overallPaper.pending, 19);
    expect(report.overallPaper.sample, 0);
  });
}
