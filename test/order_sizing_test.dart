import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/order_sizing.dart';

void main() {
  final engine = OrderSizingEngine();

  test('raises qty to minQty when balance and risk allow', () {
    final f = SymbolFilters(
      symbol: 'BCHUSDT',
      minQty: 0.02,
      stepSize: 0.01,
      minNotional: 5,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.001,
      currentPrice: 270,
      availableQuote: 10000,
      riskPercent: 0.05,
      entry: 270,
      stopLoss: 250,
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThanOrEqualTo(0.02));
  });

  test('NO TRADE when exchange min exceeds risk budget', () {
    // riskAmount = 100 * 0.01 = 1 USDT
    // stopDist = 1 → riskBased qty = 1
    // minQty = 10 → min risk = 10 > 1 → NO TRADE
    final f = SymbolFilters(
      symbol: 'BCHUSDT',
      minQty: 10,
      stepSize: 1,
      minNotional: 1,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.01,
      currentPrice: 270,
      availableQuote: 100,
      riskPercent: 0.01,
      entry: 270,
      stopLoss: 269,
    );
    expect(r.canSubmit, isFalse);
  });

  test('insufficient balance blocks buy', () {
    final f = SymbolFilters(
      symbol: 'BCHUSDT',
      minQty: 0.02,
      stepSize: 0.01,
      minNotional: 10,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.001,
      currentPrice: 270,
      availableQuote: 1,
      isBuy: true,
    );
    expect(r.canSubmit, isFalse);
    expect(r.status, OrderSizeStatus.insufficientBalance);
  });

  test('stepSize rounding is at least step', () {
    final f = SymbolFilters(
      symbol: 'ETHUSDT',
      minQty: 0.001,
      stepSize: 0.001,
      minNotional: 1,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.0014,
      currentPrice: 3000,
      availableQuote: 10000,
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThanOrEqualTo(0.002 - 1e-12));
  });

  test('valid BTC risk-based', () {
    final f = SymbolFilters.fallback('BTCUSDT');
    final r = engine.compute(
      filters: f,
      configuredQty: 0.0001,
      currentPrice: 60000,
      availableQuote: 5000,
      riskPercent: 0.01,
      entry: 60000,
      stopLoss: 59000,
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThan(0));
  });

  test('notional floor when no stop', () {
    final f = SymbolFilters(
      symbol: 'BTCUSDT',
      minQty: 0.0001,
      stepSize: 0.0001,
      minNotional: 50,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.0001,
      currentPrice: 100000,
      availableQuote: 10000,
    );
    expect(r.canSubmit, isTrue);
    expect(r.approxNotional, greaterThanOrEqualTo(50 - 1e-6));
  });
}
