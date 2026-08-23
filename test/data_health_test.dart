import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_signal_scanner/services/data_health.dart';

void main() {
  test('no data → offline', () {
    final m = DataHealthMonitor();
    expect(m.evaluate(), DataHealth.offline);
    expect(m.evaluate().allowsTrade, isFalse);
  });

  test('recent trades → live', () {
    final m = DataHealthMonitor();
    m.markTradesOk();
    expect(m.evaluate(), DataHealth.live);
    expect(m.evaluate().allowsTrade, isTrue);
  });

  test('old data → stale', () {
    final m = DataHealthMonitor(
      liveWindow: const Duration(seconds: 1),
      staleWindow: const Duration(seconds: 2),
    );
    m.lastTradesOk = DateTime.now().subtract(const Duration(seconds: 5));
    expect(m.evaluate(), DataHealth.stale);
    expect(m.evaluate().allowsTrade, isFalse);
  });

  test('ws error with fresh rest → degraded', () {
    final m = DataHealthMonitor();
    m.markTradesOk();
    m.setWsStatus('error');
    expect(m.evaluate(), DataHealth.degraded);
  });
}
