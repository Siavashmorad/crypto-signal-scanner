import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_signal_scanner/models/market_data.dart';
import 'package:crypto_signal_scanner/services/scanner_service.dart';

void main() {
  test('buildCandles aggregates OHLCV into timeframe buckets', () {
    final scanner = ScannerService(
      // buildCandles does not access the API, so a real client is not used.
      // The service is disposed immediately after the pure aggregation check.
      throw UnimplementedError('API is not used by this test'),
    );

    final candles = scanner.buildCandles(
      const [
        TradePoint(price: 100, quantity: 1, timestampMs: 0),
        TradePoint(price: 105, quantity: 2, timestampMs: 10 * 1000),
        TradePoint(price: 98, quantity: 3, timestampMs: 20 * 1000),
        TradePoint(price: 102, quantity: 4, timestampMs: 60 * 1000),
      ],
      const Duration(minutes: 1),
    );

    expect(candles, hasLength(2));
    expect(candles[0].open, 100);
    expect(candles[0].high, 105);
    expect(candles[0].low, 98);
    expect(candles[0].close, 98);
    expect(candles[0].volume, 6);
    expect(candles[1].open, 102);
    expect(candles[1].close, 102);
    expect(candles[1].volume, 4);
  });
}
