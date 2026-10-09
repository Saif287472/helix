import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote/core/push/push_registration.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show Setting;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Push registration and message notifications, the platform glue the review
/// of 2026-10-09 found untested (E-01, E-02, F-01).
void main() {
  group('PushRegistration (E-02)', () {
    test('an engine that starts running gets the current token', () async {
      final tokens = _FakeTokens(token: 'token-1');
      final sent = <String>[];
      final registration = PushRegistration(
        tokens,
        current: () =>
            (token) async => sent.add(token),
      );
      await registration.engineRunning();
      expect(sent, ['token-1']);
      await registration.dispose();
    });

    test(
      'with no engine running nothing is sent; the next start sends it',
      () async {
        final tokens = _FakeTokens(token: 'token-1');
        final sent = <String>[];
        PushRegistrar? running;
        final registration = PushRegistration(tokens, current: () => running);
        await registration.engineRunning();
        expect(sent, isEmpty);
        running = (token) async => sent.add(token);
        await registration.engineRunning();
        expect(sent, ['token-1']);
        await registration.dispose();
      },
    );

    test(
      'a rotated token goes to the engine running then, never an old one',
      () async {
        final tokens = _FakeTokens(token: 'token-1');
        final first = <String>[];
        final second = <String>[];
        PushRegistrar running = (token) async => first.add(token);
        final registration = PushRegistration(tokens, current: () => running);
        await registration.engineRunning();
        // A new server: a new runtime and engine.
        running = (token) async => second.add(token);
        tokens.rotate('token-2');
        await pumpEventQueue();
        expect(first, ['token-1']);
        expect(second, ['token-2']);
        await registration.engineRunning();
        expect(tokens.listeners, 1, reason: 'one refresh listener for the run');
        await registration.dispose();
      },
    );

    test(
      'a failed registration is swallowed and retried on the next start',
      () async {
        final tokens = _FakeTokens(token: 'token-1');
        var attempts = 0;
        final registration = PushRegistration(
          tokens,
          current: () => (token) async {
            attempts++;
            if (attempts == 1) throw StateError('offline');
          },
        );
        await registration.engineRunning();
        await registration.engineRunning();
        expect(attempts, 2);
        await registration.dispose();
      },
    );

    test('a build without push does nothing', () async {
      final tokens = _FakeTokens(token: 'token-1', available: false);
      var asked = false;
      final registration = PushRegistration(
        tokens,
        current: () {
          asked = true;
          return (token) async {};
        },
      );
      await registration.engineRunning();
      expect(asked, isFalse);
      expect(tokens.listeners, 0);
      await registration.dispose();
    });
  });

  group('pushRegistrationProvider (E-02)', () {
    test(
      'registers when the engine becomes ready: sign-up, and again after a sign-out',
      () async {
        final auth = StreamController<AppAuthState>();
        final tokens = _FakeTokens(token: 'token-1');
        final sent = <String>[];
        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => auth.stream),
            pushTokensProvider.overrideWithValue(tokens),
            currentPushRegistrarProvider.overrideWithValue(
              () =>
                  (token) async => sent.add(token),
            ),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(auth.close);
        container.listen(pushRegistrationProvider, (_, _) {});

        auth.add(AppAuthState.starting);
        auth.add(AppAuthState.signedOut);
        await pumpEventQueue();
        expect(sent, isEmpty, reason: 'a fresh install has nobody to register');

        auth.add(AppAuthState.ready); // signed up
        await pumpEventQueue();
        expect(sent, ['token-1']);

        auth.add(AppAuthState.signedOut);
        auth.add(AppAuthState.ready); // signed in again
        await pumpEventQueue();
        expect(sent, ['token-1', 'token-1']);
      },
    );
  });

  group('RunningAppAlerts (E-01)', () {
    late List<({int count, IncomingNotice? only})> shown;
    late int cleared;
    late bool foreground;
    late RunningAppAlerts alerts;

    setUp(() {
      shown = [];
      cleared = 0;
      foreground = false;
      alerts = RunningAppAlerts(
        inForeground: () => foreground,
        show: (read, {required count, only}) async =>
            shown.add((count: count, only: only)),
        clear: () async => cleared++,
      );
    });

    test(
      'in the background, new messages raise one counting notification',
      () async {
        final first = _notice('m1', preview: 'hello');
        await alerts.onNotice(first, _settings());
        await alerts.onNotice(_notice('m2'), _settings());
        expect(shown, [(count: 1, only: first), (count: 2, only: null)]);
      },
    );

    test('in the foreground nothing is raised', () async {
      foreground = true;
      await alerts.onNotice(_notice('m1'), _settings());
      expect(shown, isEmpty);
    });

    test('muted chats and switched-off kinds stay quiet', () async {
      await alerts.onNotice(_notice('m1', muted: true), _settings());
      await alerts.onNotice(
        _notice('m2', group: true),
        _settings({AppSettings.notifyGroups: false}),
      );
      await alerts.onNotice(
        _notice('m3'),
        _settings({AppSettings.notifyMessages: false}),
      );
      expect(shown, isEmpty);
      await alerts.onNotice(
        _notice('m4', group: true),
        _settings({AppSettings.notifyMessages: false}),
      );
      expect(shown.single.count, 1, reason: 'groups still alert');
    });

    test('resuming clears the notification and the count', () async {
      await alerts.onNotice(_notice('m1'), _settings());
      await alerts.onNotice(_notice('m2'), _settings());
      await alerts.resumed();
      expect(cleared, 1);
      await alerts.onNotice(_notice('m3'), _settings());
      expect(shown.last.count, 1);
    });

    test('a failing notification never escapes', () async {
      final failing = RunningAppAlerts(
        inForeground: () => false,
        show: (read, {required count, only}) async =>
            throw StateError('no plugin'),
        clear: () async => throw StateError('no plugin'),
      );
      await failing.onNotice(_notice('m1'), _settings());
      await failing.resumed();
    });
  });

  group('MessageAlerts.preview', () {
    test('only one message, with previews on, and only its own text', () async {
      final notice = _notice('m1', preview: 'see you at 5');
      final on = _settings({AppSettings.notificationsPreview: true});
      final off = _settings({AppSettings.notificationsPreview: false});
      expect(
        await MessageAlerts.preview(on, count: 1, only: notice),
        'see you at 5',
      );
      expect(await MessageAlerts.preview(off, count: 1, only: notice), isNull);
      expect(await MessageAlerts.preview(on, count: 2, only: notice), isNull);
      expect(
        await MessageAlerts.preview(on, count: 1, only: _notice('m2')),
        isNull,
        reason: 'a photo without a caption has no text',
      );
    });
  });
}

ReadFlag _settings([Map<Setting<bool>, bool> values = const {}]) =>
    (setting) async => values[setting] ?? true;

IncomingNotice _notice(
  String id, {
  String preview = '',
  bool muted = false,
  bool group = false,
}) => IncomingNotice(
  conversationId: group ? 'group:g1' : 'dm:alice',
  messageRowid: 1,
  messageId: id,
  sender: 'alice',
  kind: 'text',
  preview: preview,
  muted: muted,
  sentAt: DateTime.utc(2026, 10, 9),
);

final class _FakeTokens implements PushTokens {
  _FakeTokens({required this.token, this.available = true});

  final String token;
  final bool available;
  final _refreshes = StreamController<String>.broadcast();
  int listeners = 0;

  void rotate(String value) => _refreshes.add(value);

  @override
  Future<bool> prepare() async => available;

  @override
  Future<String?> currentToken() async => available ? token : null;

  @override
  Stream<String> get refreshes {
    listeners++;
    return _refreshes.stream;
  }
}
