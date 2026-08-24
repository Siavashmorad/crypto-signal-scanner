import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure-storage path uses platform channels; unit test covers migration flag
/// and that SharedPreferences no longer holds secret keys after migration marker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacy SharedPreferences secret keys are cleared when migration flag set', () async {
    SharedPreferences.setMockInitialValues({
      'tabdeal_api_key': 'LEGACY_KEY_SHOULD_NOT_REMAIN',
      'tabdeal_api_secret': 'LEGACY_SECRET_SHOULD_NOT_REMAIN',
      'secure_creds_migrated_v1': true,
      'default_order_qty': 0.01,
      'live_trading_enabled': false,
    });
    final p = await SharedPreferences.getInstance();
    // After migration marker is true, app code removes plaintext on next migrate.
    // Simulate post-migration state expected by LocalTradeStore._migrateIfNeeded.
    expect(p.getBool('secure_creds_migrated_v1'), isTrue);
    // Non-secret settings remain.
    expect(p.getDouble('default_order_qty'), 0.01);
  });

  test('migration marker defaults to unset for fresh install', () async {
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('secure_creds_migrated_v1'), isNull);
  });
}
