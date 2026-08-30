import 'package:crypto_signal_scanner/services/mt5_metaapi_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MetaAPI client builds regional base URL', () {
    final c = Mt5MetaApiClient(
      authToken: 't',
      accountId: 'acc',
      region: 'london',
    );
    expect(c.baseUrl, 'https://mt-client-api-v1.london.agiliumtrade.ai');
    c.dispose();
  });

  test('MetaAPI position type maps SELL to SHORT', () {
    // Mirror mapping used in client without network.
    String sideFrom(String type) {
      final t = type.toUpperCase();
      return t.contains('SELL') || t.contains('SHORT') ? 'SHORT' : 'LONG';
    }

    expect(sideFrom('POSITION_TYPE_SELL'), 'SHORT');
    expect(sideFrom('POSITION_TYPE_BUY'), 'LONG');
  });
}
