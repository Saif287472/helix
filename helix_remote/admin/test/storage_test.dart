import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/services/admin_settings.dart';
import 'package:helix_admin/src/services/token_vault.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final stored = StoredSession(
    serverUrl: 'https://helix.example.com',
    session: AdminSession(
      token: 'super-secret-admin-token',
      expiresAt: DateTime.utc(2026, 10, 3, 6),
    ),
  );

  group('the token vault', () {
    test('keeps the session in secure storage, not in preferences', () async {
      final vault = SecureTokenVault();
      expect(await vault.read(), isNull);

      await vault.write(stored);
      final read = await vault.read();
      expect(read!.serverUrl, 'https://helix.example.com');
      expect(read.session.token, 'super-secret-admin-token');
      expect(read.session.expiresAt, DateTime.utc(2026, 10, 3, 6));

      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(
          '${prefs.get(key)}',
          isNot(contains('super-secret-admin-token')),
          reason: 'the token must never reach plain preferences',
        );
      }
    });

    test('clear forgets it', () async {
      final vault = SecureTokenVault();
      await vault.write(stored);
      await vault.clear();

      expect(await vault.read(), isNull);
    });

    test('an unreadable value counts as signed out and is dropped', () async {
      FlutterSecureStorage.setMockInitialValues({
        'admin_session': jsonEncode({'server_url': 'x'}),
      });
      final vault = SecureTokenVault();

      expect(await vault.read(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'admin_session'),
        isNull,
      );
    });

    test('printing a stored session never shows the token', () {
      expect('$stored', isNot(contains('super-secret-admin-token')));
    });
  });

  group('settings', () {
    test('remember the server and default App lock to off', () async {
      final settings = await PrefsAdminSettings.load();
      expect(settings.serverUrl, isNull);
      expect(settings.appLockEnabled, isFalse);

      await settings.setServerUrl('https://helix.example.com');
      await settings.setAppLockEnabled(true);

      final again = await PrefsAdminSettings.load();
      expect(again.serverUrl, 'https://helix.example.com');
      expect(again.appLockEnabled, isTrue);
    });
  });
}
