import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/order_sizing.dart';

void main() {
  final engine = OrderSizingEngine();

  test('quantity below minQty is raised when risk allows', () {
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
      stopLoss: 260,
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThanOrEqualTo(0.02));
  });

  test('min order that exceeds risk → NO TRADE', () {
    final f = SymbolFilters(
      symbol: 'BCHUSDT',
      minQty: 1.0,
      stepSize: 0.1,
      minNotional: 200,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.01,
      currentPrice: 270,
      availableQuote: 500,
      riskPercent: 0.01,
      entry: 270,
      stopLoss: 265,
    );
    expect(r.canSubmit, isFalse);
  });

  test('insufficient balance blocks order', () {
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

  test('stepSize produces valid multiple', () {
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
    expect(r.finalQty % 0.001, closeTo(0, 1e-9));
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
    expect(r.finalQty * r.price, greaterThanOrEqualTo(50 - 1e-6));
  });
}
