import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/push/push_registration.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart'
    show FileDeviceSettingsStore;

/// The "wake this phone" switch (Q8, AUD-12j-1): off, no token goes to any
/// account and the server is told to forget the ones it has; on, they go up
/// again.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_wakeups');
    AppPaths.localDataDirectory = () async => tmp;
    AppPaths.privateDataDirectory = () async => tmp;
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.privateDataDirectory = () async => throw StateError('unset');
    tmp.deleteSync(recursive: true);
  });

  group('the device\'s choice', () {
    test('is on until it is turned off, and survives', () async {
      const store = FileDeviceSettingsStore();
      expect(await store.readPushWakeups(), isTrue);
      await store.writePushWakeups(false);
      expect(await store.readPushWakeups(), isFalse);
      await store.writeRingtone('chime');
      expect(await store.readPushWakeups(), isFalse, reason: 'others kept');
      await store.writePushWakeups(true);
      expect(await store.readPushWakeups(), isTrue);
      expect(await store.readRingtone(), 'chime');
    });
  });

  group('the registration', () {
    test('sends nothing while wake-ups are off, rotations included', () async {
      final tokens = _Tokens('token-1');
      final sent = <String>[];
      final others = <String>[];
      var on = false;
      final registration = PushRegistration(
        tokens,
        current: () =>
            (token) async => sent.add(token),
        onToken: (token) async => others.add(token),
        enabled: () async => on,
      );
      addTearDown(registration.dispose);

      await registration.engineRunning();
      expect(sent, isEmpty);
      expect(others, isEmpty);

      on = true;
      await registration.engineRunning();
      expect(sent, ['token-1']);
      expect(others, ['token-1']);

      on = false;
      tokens.rotate('token-2');
      await pumpEventQueue();
      expect(sent, ['token-1'], reason: 'a rotation while off is not sent');
    });
  });

  group('the switch', () {
    ProviderContainer container({
      required List<String> sent,
      required List<String> unregistered,
    }) {
      final tokens = _Tokens('token-1');
      final c = ProviderContainer(
        overrides: [
          pushRegistrationProvider.overrideWith((ref) {
            final registration = PushRegistration(
              tokens,
              current: () =>
                  (token) async => sent.add(token),
              enabled: ref.read(pushWakeupsReaderProvider),
            );
            ref.onDispose(registration.dispose);
            return registration;
          }),
          otherAccountsUnregisterProvider.overrideWithValue(
            () async => unregistered.add('others'),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('off tells every other account\'s server and is remembered', () async {
      final sent = <String>[];
      final unregistered = <String>[];
      final c = container(sent: sent, unregistered: unregistered);
      expect(await c.read(pushWakeupsProvider.future), isTrue);

      await c.read(pushWakeupsProvider.notifier).set(false);

      expect(c.read(pushWakeupsProvider).value, isFalse);
      expect(unregistered, ['others']);
      expect(await const FileDeviceSettingsStore().readPushWakeups(), isFalse);
      expect(sent, isEmpty);
    });

    test('on registers the token again, for the account on screen', () async {
      final sent = <String>[];
      final unregistered = <String>[];
      final c = container(sent: sent, unregistered: unregistered);
      await c.read(pushWakeupsProvider.future);
      await c.read(pushWakeupsProvider.notifier).set(false);

      await c.read(pushWakeupsProvider.notifier).set(true);

      expect(c.read(pushWakeupsProvider).value, isTrue);
      expect(sent, ['token-1']);
      expect(await const FileDeviceSettingsStore().readPushWakeups(), isTrue);
      expect(unregistered, ['others'], reason: 'only turning it off');
    });

    test('a server that cannot be reached does not undo the choice', () async {
      final c = ProviderContainer(
        overrides: [
          otherAccountsUnregisterProvider.overrideWithValue(
            () async => throw StateError('offline'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(pushWakeupsProvider.future);
      await c.read(pushWakeupsProvider.notifier).set(false);
      expect(c.read(pushWakeupsProvider).value, isFalse);
      expect(await const FileDeviceSettingsStore().readPushWakeups(), isFalse);
    });
  });
}

final class _Tokens implements PushTokens {
  _Tokens(this.token);

  final String token;
  final _refreshes = StreamController<String>.broadcast();
  final _wakeUps = StreamController<void>.broadcast();

  void rotate(String value) => _refreshes.add(value);

  @override
  Future<bool> prepare() async => true;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get refreshes => _refreshes.stream;

  @override
  Stream<void> get wakeUps => _wakeUps.stream;
}
