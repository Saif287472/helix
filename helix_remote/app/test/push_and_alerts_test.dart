import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
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
    late List<
      ({String account, int count, IncomingNotice? only, String? label})
    >
    shown;
    late List<String> cleared;
    late bool foreground;
    late String? onScreen;
    late RunningAppAlerts alerts;

    setUp(() {
      shown = [];
      cleared = [];
      foreground = false;
      onScreen = 'primary';
      alerts = RunningAppAlerts(
        inForeground: () => foreground,
        onScreen: () => onScreen,
        label: (account) => account == 'b' ? 'Work' : null,
        show:
            (
              read, {
              required account,
              required count,
              only,
              accountLabel,
            }) async => shown.add((
              account: account,
              count: count,
              only: only,
              label: accountLabel,
            )),
        clear: (account) async => cleared.add(account),
      );
    });

    test(
      'in the background, new messages raise one counting notification',
      () async {
        final first = _notice('m1', preview: 'hello');
        await alerts.onNotice(first, _settings(), account: 'primary');
        await alerts.onNotice(_notice('m2'), _settings(), account: 'primary');
        expect(shown.map((e) => (e.count, e.only)), [(1, first), (2, null)]);
        expect(shown.map((e) => e.account), everyElement('primary'));
      },
    );

    test('in the foreground nothing is raised', () async {
      foreground = true;
      await alerts.onNotice(_notice('m1'), _settings(), account: 'primary');
      expect(shown, isEmpty);
    });

    test('muted chats and switched-off kinds stay quiet', () async {
      await alerts.onNotice(
        _notice('m1', muted: true),
        _settings(),
        account: 'primary',
      );
      await alerts.onNotice(
        _notice('m2', group: true),
        _settings({AppSettings.notifyGroups: false}),
        account: 'primary',
      );
      await alerts.onNotice(
        _notice('m3'),
        _settings({AppSettings.notifyMessages: false}),
        account: 'primary',
      );
      expect(shown, isEmpty);
      await alerts.onNotice(
        _notice('m4', group: true),
        _settings({AppSettings.notifyMessages: false}),
        account: 'primary',
      );
      expect(shown.single.count, 1, reason: 'groups still alert');
    });

    test('resuming clears the notification and the count', () async {
      await alerts.onNotice(_notice('m1'), _settings(), account: 'primary');
      await alerts.onNotice(_notice('m2'), _settings(), account: 'primary');
      await alerts.resumed();
      expect(cleared, ['primary']);
      await alerts.onNotice(_notice('m3'), _settings(), account: 'primary');
      expect(shown.last.count, 1);
    });

    test(
      'each account has its own notification, named on a shared device',
      () async {
        await alerts.onNotice(_notice('m1'), _settings(), account: 'primary');
        await alerts.onNotice(_notice('m2'), _settings(), account: 'primary');
        // A switch while away: the other account's run counts from one.
        await alerts.onNotice(_notice('m3'), _settings(), account: 'b');
        expect(shown.last.account, 'b');
        expect(shown.last.count, 1);
        expect(shown.last.label, 'Work');
        onScreen = 'b';
        await alerts.resumed();
        expect(cleared, ['b'], reason: 'the other account keeps its own');
      },
    );

    test('an account opened in front clears its notification', () async {
      await alerts.opened('b');
      expect(cleared, isEmpty, reason: 'opened in the background');
      foreground = true;
      await alerts.opened('b');
      expect(cleared, ['b']);
    });

    test('a failing notification never escapes', () async {
      final failing = RunningAppAlerts(
        inForeground: () => false,
        onScreen: () => 'primary',
        show:
            (
              read, {
              required account,
              required count,
              only,
              accountLabel,
            }) async => throw StateError('no plugin'),
        clear: (account) async => throw StateError('no plugin'),
      );
      await failing.onNotice(_notice('m1'), _settings(), account: 'primary');
      await failing.resumed();
    });
  });

  group('notification payloads', () {
    test('carry the account and the call, and read old ones', () {
      final payload = CallNotifications.payloadFor('c1', account: 'b');
      expect(CallNotifications.callIdOf(payload), 'c1');
      expect(NotificationPayload.accountOf(payload), 'b');
      expect(CallNotifications.callIdOf('call_id=c2'), 'c2');
      expect(NotificationPayload.accountOf('call_id=c2'), isNull);
      expect(NotificationPayload.accountOf(null), isNull);
      expect(
        NotificationPayload.accountOf(
          NotificationPayload.encode({NotificationPayload.account: 'primary'}),
        ),
        'primary',
      );
    });

    test('each account has its own message notification id', () {
      expect(LocalNotifications.messagesIdFor('primary'), 0);
      final b = LocalNotifications.messagesIdFor('b1');
      expect(b, isNot(0));
      expect(b, LocalNotifications.messagesIdFor('b1'));
      expect(b, isNot(LocalNotifications.messagesIdFor('b2')));
    });
  });

  group('ForegroundWakes', () {
    test('one pass at a time, and one more for a wake-up during it', () async {
      var passes = 0;
      var running = 0;
      var most = 0;
      final gate = Completer<void>();
      final wakes = ForegroundWakes(() async {
        passes++;
        running++;
        most = running > most ? running : most;
        if (passes == 1) await gate.future;
        running--;
      });
      final first = wakes.wake();
      unawaited(wakes.wake());
      unawaited(wakes.wake());
      gate.complete();
      await first;
      expect(passes, 2);
      expect(most, 1);
      await wakes.wake();
      expect(passes, 3);
    });

    test('a failed pass does not stop the next', () async {
      var passes = 0;
      final wakes = ForegroundWakes(() async {
        passes++;
        throw StateError('offline');
      });
      await wakes.wake();
      await wakes.wake();
      expect(passes, 2);
    });
  });

  test('a wake-up while the app is in front reaches onWake', () async {
    final tokens = _FakeTokens(token: 'token-1');
    var woken = 0;
    final registration = PushRegistration(
      tokens,
      current: () => null,
      onWake: () => woken++,
    );
    await registration.engineRunning();
    await registration.engineRunning();
    tokens.wake();
    await pumpEventQueue();
    expect(woken, 1, reason: 'one listener for the run');
    await registration.dispose();
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

  final _wakeUps = StreamController<void>.broadcast();

  void rotate(String value) => _refreshes.add(value);

  void wake() => _wakeUps.add(null);

  @override
  Future<bool> prepare() async => available;

  @override
  Future<String?> currentToken() async => available ? token : null;

  @override
  Stream<String> get refreshes {
    listeners++;
    return _refreshes.stream;
  }

  @override
  Stream<void> get wakeUps => _wakeUps.stream;
}
