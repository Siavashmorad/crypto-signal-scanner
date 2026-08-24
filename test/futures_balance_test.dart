import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/account_balance.dart';

void main() {
  test('spot balances parse free+locked', () {
    final s = AccountSnapshot.fromApi({
      'balances': [
        {'asset': 'USDT', 'free': '5', 'freeze': '1'},
      ],
    });
    expect(s.available, isTrue);
    expect(s.of('USDT')!.total, 6);
    expect(s.of('USDT')!.free, 5);
  });

  test('futures short position parse', () {
    final p = FuturesPositionsSnapshot.fromApi([
      {
        'symbol': 'BTCUSDT',
        'positionAmt': '-0.01',
        'entryPrice': '60000',
        'markPrice': '60100',
        'unRealizedProfit': '-1',
        'liquidationPrice': '65000',
        'leverage': '5',
        'marginType': 'cross',
        'positionSide': 'BOTH',
      },
    ]);
    expect(p.positions, hasLength(1));
    expect(p.positions.first.isShort, isTrue);
    expect(p.positions.first.isLong, isFalse);
  });

  test('futures not active factory', () {
    expect(FuturesBalanceSnapshot.notActive().futuresActive, isFalse);
    expect(FuturesPositionsSnapshot.notActive().futuresActive, isFalse);
  });

  test('unavailable does not invent zero balances', () {
    final s = AccountSnapshot.unavailable('offline');
    expect(s.available, isFalse);
    expect(s.balances, isEmpty);
  });
}
