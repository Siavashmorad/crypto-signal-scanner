import 'package:flutter_test/flutter_test.dart';

import '../lib/services/mt5_bridge_client.dart';

void main() {
  test('parses MT5 position snapshot without order fields', () {
    final p = Mt5PositionSnapshot.fromJson({
      'symbol': 'EURUSD',
      'side': 'BUY',
      'volume': 0.10,
      'openPrice': 1.1234,
      'sl': 1.1200,
      'tp': 1.1300,
    });

    expect(p.symbol, 'EURUSD');
    expect(p.side, 'BUY');
    expect(p.volume, 0.10);
    expect(p.openPrice, 1.1234);
    expect(p.stopLoss, 1.12);
    expect(p.takeProfit, 1.13);
  });

  test('parses numeric strings from bridge account safely', () {
    expect(Mt5AccountSnapshot(balance: 1000, equity: 990, margin: 100).balance, 1000);
  });

  test('bridge exception is readable', () {
    expect(const Mt5BridgeException('خطا').toString(), 'خطا');
  });
}
