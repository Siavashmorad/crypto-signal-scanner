import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/account_balance.dart';

void main() {
  test('parses free vs locked correctly', () {
    final snap = AccountSnapshot.fromApi({
      'balances': [
        {'asset': 'USDT', 'free': '100.5', 'locked': '20'},
        {'asset': 'BCH', 'free': '0.5', 'locked': '0'},
      ],
    });
    expect(snap.available, isTrue);
    expect(snap.of('USDT')!.free, closeTo(100.5, 1e-9));
    expect(snap.of('USDT')!.locked, closeTo(20, 1e-9));
    expect(snap.of('USDT')!.total, closeTo(120.5, 1e-9));
    expect(snap.freeQuote('BCHUSDT'), closeTo(100.5, 1e-9));
    expect(snap.freeBase('BCHUSDT'), closeTo(0.5, 1e-9));
  });

  test('unknown structure is unavailable not fake zero list success', () {
    final snap = AccountSnapshot.fromApi({'foo': 1});
    expect(snap.available, isFalse);
    expect(snap.error, isNotNull);
  });

  test('quote asset detection', () {
    expect(AccountSnapshot.quoteAsset('BCHUSDT'), 'USDT');
    expect(AccountSnapshot.quoteAsset('BTC_IRT'), 'IRT');
    expect(AccountSnapshot.baseAsset('ETHUSDT'), 'ETH');
  });
}
