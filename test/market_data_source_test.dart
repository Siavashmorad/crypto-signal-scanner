import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/binance_market_data_source.dart';
import 'package:crypto_signal_scanner/services/exchange_registry.dart';
import 'package:crypto_signal_scanner/services/tabdeal_market_data_source.dart';

void main() {
  test('TabdealMarketDataSource id and normalize', () {
    final src = TabdealMarketDataSource();
    expect(src.id, 'tabdeal');
    expect(src.normalizeSymbol('btc_usdt'), 'BTCUSDT');
  });

  test('BinanceMarketDataSource maps IRT to USDT', () {
    final src = BinanceMarketDataSource();
    expect(src.id, 'binance');
    expect(src.normalizeSymbol('BTCIRT'), 'BTCUSDT');
    expect(src.normalizeSymbol('eth'), 'ETHUSDT');
  });

  test('ExchangeRegistry default is tabdeal', () {
    final src = ExchangeRegistry.byId('unknown');
    expect(src.id, 'tabdeal');
    expect(ExchangeRegistry.defaultId, 'tabdeal');
  });

  test('ExchangeRegistry catalog includes tabdeal and binance', () {
    final c = ExchangeRegistry.catalog();
    expect(c.any((e) => e.id == 'tabdeal'), isTrue);
    expect(c.any((e) => e.id == 'binance'), isTrue);
  });
}
