import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/services/admin_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the admin token round-trips through secure storage, never plaintext '
      'SharedPreferences', () async {
    final prefs = await AdminPreferences.load();

    expect(await prefs.loadAdminToken(), isNull);

    await prefs.saveAdminToken('super-secret-token');
    expect(await prefs.loadAdminToken(), equals('super-secret-token'));

    final rawPrefs = await SharedPreferences.getInstance();
    expect(
      rawPrefs.getKeys().any((key) => key.toLowerCase().contains('token')),
      isFalse,
      reason: 'the token must never land in plaintext SharedPreferences',
    );

    await prefs.clearAdminToken();
    expect(await prefs.loadAdminToken(), isNull);
  });

  test(
    'app lock preference defaults to off and persists when changed',
    () async {
      final prefs = await AdminPreferences.load();

      expect(prefs.appLockEnabled, isFalse);

      await prefs.setAppLockEnabled(true);
      expect(prefs.appLockEnabled, isTrue);

      final reloaded = await AdminPreferences.load();
      expect(reloaded.appLockEnabled, isTrue);
    },
  );
}
