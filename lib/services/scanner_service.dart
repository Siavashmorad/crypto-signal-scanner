import 'dart:developer' as developer;

import '../models/market_data.dart';
import 'tabdeal_api.dart';

class ScannerService {
  final TabdealApi api;
  const ScannerService(this.api);

  List<Candle> buildCandles(List<TradePoint> trades, Duration timeframe) {
    if (trades.isEmpty) return const [];
    final sorted = [...trades]
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final bucketMs = timeframe.inMilliseconds;
    final map = <int, Candle>{};
    for (final trade in sorted) {
      final bucket = trade.timestampMs - (trade.timestampMs % bucketMs);
      final current = map[bucket];
      if (current == null) {
        map[bucket] = Candle(
          timestampMs: bucket,
          open: trade.price,
          high: trade.price,
          low: trade.price,
          close: trade.price,
          volume: trade.quantity,
        );
      } else {
        map[bucket] = Candle(
          timestampMs: bucket,
          open: current.open,
          high: trade.price > current.high ? trade.price : current.high,
          low: trade.price < current.low ? trade.price : current.low,
          close: trade.price,
          volume: current.volume + trade.quantity,
        );
      }
    }
    return map.values.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  double _ema(List<double> values, int period) {
    if (values.length < period) return values.isEmpty ? 0 : values.last;
    var ema = values.take(period).reduce((a, b) => a + b) / period;
    final multiplier = 2 / (period + 1);
    for (final value in values.skip(period)) {
      ema = (value - ema) * multiplier + ema;
    }
    return ema;
  }

  double _rsi(List<double> closes, int period) {
    if (closes.length <= period) return 50;
    var gain = 0.0;
    var loss = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      final delta = closes[i] - closes[i - 1];
      if (delta >= 0) {
        gain += delta;
      } else {
        loss -= delta;
      }
    }
    if (loss == 0) return 100;
    final rs = gain / loss;
    return 100 - (100 / (1 + rs));
  }

  double _atr(List<Candle> candles, int period) {
    if (candles.length < period + 1) return 0;
    final trs = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final c = candles[i];
      final prev = candles[i - 1];
      trs.add([
        c.high - c.low,
        (c.high - prev.close).abs(),
        (c.low - prev.close).abs(),
      ].reduce((a, b) => a > b ? a : b));
    }
    return trs.skip(trs.length - period).reduce((a, b) => a + b) / period;
  }

  Future<MarketSignal?> scanSymbol(String symbol, Duration timeframe) async {
    final trades = await api.trades(symbol, limit: 200);
    if (trades.length < 40) return null;
    final candles = buildCandles(trades, timeframe);
    if (candles.length < 15) return null;
    final closes = candles.map((e) => e.close).toList();
    final last = closes.last;
    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final rsi = _rsi(closes, 14);
    final atr = _atr(candles, 14);
    if (atr <= 0 || last <= 0) return null;

    final depth = await api.depth(symbol);
    double bid = 0;
    double ask = 0;
    for (final row in (depth['bids'] is List ? depth['bids'] : const [])) {
      if (row is List && row.length >= 2) {
        bid += double.tryParse('${row[1]}') ?? 0;
      }
    }
    for (final row in (depth['asks'] is List ? depth['asks'] : const [])) {
      if (row is List && row.length >= 2) {
        ask += double.tryParse('${row[1]}') ?? 0;
      }
    }
    final imbalance = bid + ask == 0 ? 0 : (bid - ask) / (bid + ask);
    final long = ema9 > ema21 && rsi >= 48 && rsi <= 72 && imbalance >= -0.12;
    final short = ema9 < ema21 && rsi <= 52 && rsi >= 28 && imbalance <= 0.12;
    if (!long && !short) return null;

    var score = 50.0;
    score += (ema9 - ema21).abs() / last * 1000;
    score += (rsi - 50).abs() * 0.35;
    score += imbalance.abs() * 15;
    score = score.clamp(0, 100);
    if (score < 58) return null;

    final side = long ? 'LONG' : 'SHORT';
    final stopDistance = atr * 1.5;
    final reward = stopDistance * 2.0;
    final stop = long ? last - stopDistance : last + stopDistance;
    final tp1 = long ? last + reward * 0.5 : last - reward * 0.5;
    final tp2 = long ? last + reward : last - reward;
    final tp3 = long ? last + reward * 1.5 : last - reward * 1.5;
    final timeframeLabel =
        timeframe.inMinutes >= 60 ? '1h' : '${timeframe.inMinutes}m';
    return MarketSignal(
      symbol: symbol,
      side: side,
      timeframe: timeframeLabel,
      entry: last,
      stopLoss: stop,
      tp1: tp1,
      tp2: tp2,
      tp3: tp3,
      atr: atr,
      confidence: score,
      riskReward: 2,
      timestamp: DateTime.now(),
    );
  }

  double _rankScore(MarketSignal signal) {
    final confidence = signal.confidence.clamp(0, 100).toDouble();
    final rrQuality = (signal.riskReward.clamp(1, 4) - 1) / 3 * 10;
    final volatilityPenalty = signal.entry <= 0
        ? 0.0
        : ((signal.atr / signal.entry) * 100).clamp(0, 3) * 2;
    return confidence + rrQuality - volatilityPenalty;
  }

  /// Fast scan: priority USDT markets, high concurrency, early stop.
  Future<List<MarketSignal>> scanAll({
    Duration timeframe = const Duration(minutes: 15),
    int maxConcurrency = 10,
    int maxSymbols = 30,
    int maxSignals = 12,
  }) async {
    final symbols = await api.activeUsdtSymbols(maxSymbols: maxSymbols);
    final signals = <MarketSignal>[];
    for (var start = 0; start < symbols.length; start += maxConcurrency) {
      final batch = symbols.skip(start).take(maxConcurrency).toList();
      final results = await Future.wait(batch.map((s) async {
        try {
          return await scanSymbol(s, timeframe);
        } catch (error, stackTrace) {
          developer.log(
            'Failed to scan market $s',
            name: 'ScannerService',
            error: error,
            stackTrace: stackTrace,
          );
          return null;
        }
      }));
      signals.addAll(results.whereType<MarketSignal>());
      if (signals.length >= maxSignals) break;
    }
    signals.sort((a, b) {
      final rank = _rankScore(b).compareTo(_rankScore(a));
      if (rank != 0) return rank;
      return b.confidence.compareTo(a.confidence);
    });
    return signals.take(maxSignals).toList();
  }
}
