import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/order_sizing.dart';

void main() {
  final engine = OrderSizingEngine();

  test('quantity below minQty is raised to min', () {
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
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThanOrEqualTo(0.02));
    expect(r.usedExchangeMin, isTrue);
  });

  test('notional below minNotional raises qty', () {
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
    );
    expect(r.finalQty * r.price, greaterThanOrEqualTo(50 - 1e-6));
  });

  test('stepSize rounding', () {
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
    );
    expect((r.finalQty / 0.001).roundToDouble(), r.finalQty / 0.001);
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
    );
    expect(r.canSubmit, isFalse);
    expect(r.status, OrderSizeStatus.insufficientBalance);
  });

  test('max risk blocks oversized min order', () {
    final f = SymbolFilters(
      symbol: 'BCHUSDT',
      minQty: 1,
      stepSize: 0.1,
      minNotional: 200,
    );
    final r = engine.compute(
      filters: f,
      configuredQty: 0.01,
      currentPrice: 270,
      maxRiskQuote: 50,
    );
    expect(r.canSubmit, isFalse);
    expect(r.status, OrderSizeStatus.exceedsMaxRisk);
  });

  test('valid BTC order', () {
    final f = SymbolFilters.fallback('BTCUSDT');
    final r = engine.compute(
      filters: f,
      configuredQty: 0.001,
      currentPrice: 60000,
      availableQuote: 1000,
      maxRiskQuote: 500,
    );
    expect(r.canSubmit, isTrue);
    expect(r.finalQty, greaterThanOrEqualTo(f.minQty));
  });

  test('final qty never below minQty when ok', () {
    for (final sym in ['BCHUSDT', 'BTCUSDT', 'ETHUSDT']) {
      final f = SymbolFilters.fallback(sym);
      final price = sym.startsWith('BTC')
          ? 60000.0
          : (sym.startsWith('ETH') ? 3000.0 : 270.0);
      final r = engine.compute(
        filters: f,
        configuredQty: 0.00001,
        currentPrice: price,
        availableQuote: 1e9,
        maxRiskQuote: 1e9,
      );
      if (r.canSubmit) {
        expect(r.finalQty + 1e-12, greaterThanOrEqualTo(f.minQty));
      }
    }
  });
}
