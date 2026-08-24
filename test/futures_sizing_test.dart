import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/futures_sizing.dart';
import 'package:crypto_signal_scanner/services/order_sizing.dart';

void main() {
  const engine = FuturesSizingEngine();

  test('allows reasonable size within risk', () {
    final r = engine.size(
      equity: 1000,
      availableBalance: 1000,
      riskPercent: 1,
      entry: 100,
      stopLoss: 95,
      leverage: 5,
      filters: const SymbolFilters(
        symbol: 'TESTUSDT',
        minQty: 0.01,
        stepSize: 0.01,
        minNotional: 5,
      ),
    );
    expect(r.allow, isTrue);
    expect(r.quantity, greaterThan(0));
    expect(r.requiredMargin, greaterThan(0));
  });

  test('NO TRADE when minQty forces excess risk', () {
    final r = engine.size(
      equity: 50,
      availableBalance: 50,
      riskPercent: 0.1,
      entry: 60000,
      stopLoss: 59000,
      leverage: 2,
      filters: const SymbolFilters(
        symbol: 'BTCUSDT',
        minQty: 1,
        stepSize: 0.1,
        minNotional: 10,
      ),
    );
    expect(r.allow, isFalse);
    expect(r.reason, contains('NO TRADE'));
  });

  test('exact transfer never full wallet', () {
    expect(exactTransferAmount(requiredMargin: 2.1, spotFree: 5), closeTo(2.1, 1e-9));
    expect(exactTransferAmount(requiredMargin: 10, spotFree: 5), 0);
    expect(exactTransferAmount(requiredMargin: 0, spotFree: 5), 0);
  });

  test('zero equity NO TRADE', () {
    final r = engine.size(
      equity: 0,
      availableBalance: 0,
      riskPercent: 1,
      entry: 100,
      stopLoss: 95,
      leverage: 5,
      filters: const SymbolFilters(symbol: 'X'),
    );
    expect(r.allow, isFalse);
  });
}
