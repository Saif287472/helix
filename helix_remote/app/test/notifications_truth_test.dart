import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/notifications/alert_count.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show Setting;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// B23: the notification says what arrived, and an account that goes takes its
/// notifications with it (AUD-14g-1 to 14g-7). The press routing is in
/// `account_slots_test.dart`, the ringtone cleanup in
/// `settings/ringtone_channel_test.dart`.
void main() {
  late Directory tmp;
  late AlertCountStore counts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_alert_count');
    counts = AlertCountStore(
      fileOf: (account) async => File('${tmp.path}/$account.json'),
    );
  });

  tearDown(() {
    LocalNotifications.shadeOverride = null;
    debugDefaultTargetPlatformOverride = null;
    tmp.deleteSync(recursive: true);
  });

  ReadFlag settings() =>
      (Setting<bool> setting) async => true;

  group('the count on the notification (AUD-14g-1)', () {
    test('two wake-ups of two messages, then one, say three more', () async {
      final posted = <int>[];
      Future<void> show(int arrived, {String account = 'a'}) =>
          MessageAlerts.show(
            settings(),
            account: account,
            count: arrived,
            counts: counts,
            post:
                ({
                  required account,
                  required count,
                  sound = true,
                  vibrate = true,
                  sender,
                  preview,
                  accountLabel,
                }) async => posted.add(count),
          );

      await show(2);
      await show(2);
      await show(1);
      expect(posted, [2, 4, 5], reason: 'each pass adds to what was shown');

      // Another account counts on its own.
      await show(1, account: 'b');
      expect(posted.last, 1);

      // The chats came on screen: the next run starts again.
      await counts.reset('a');
      await show(1);
      expect(posted.last, 1);
    });

    test('a count that cannot be stored is the pass alone', () async {
      final broken = AlertCountStore(
        fileOf: (account) async => throw const FileSystemException('no'),
      );
      expect(await broken.add('a', 3), 3);
      await broken.reset('a');
    });

    test('a damaged count starts from nothing', () async {
      File('${tmp.path}/a.json').writeAsStringSync('not json');
      expect(await counts.add('a', 2), 2);
      expect(await counts.add('a', 1), 3);
    });
  });

  test('each message alerts again, quietly rewriting nothing (AUD-14g-2)', () {
    const channel = AndroidNotificationChannel('c', 'C');
    final details = LocalNotifications.messageDetails(channel, revealed: true);
    expect(details.onlyAlertOnce, isFalse);
  });

  group('removing an account (AUD-14g-3)', () {
    test('takes its message and call entries out of the shade', () async {
      final shade = _Shade([
        (id: 11, payload: 'account=gone;call_id=c1'),
        (id: 12, payload: 'account=other;call_id=c2'),
        (id: 13, payload: 'call_id=c3'),
        (id: 14, payload: 'account=gone'),
      ]);
      LocalNotifications.shadeOverride = shade;
      await counts.add('gone', 4);

      await LocalNotifications.forgetAccount('gone');

      expect(
        shade.cancelled,
        contains(LocalNotifications.messagesIdFor('gone')),
      );
      expect(shade.cancelled, containsAll([11, 14]));
      expect(shade.cancelled, isNot(contains(12)), reason: 'not its');
      expect(shade.cancelled, isNot(contains(13)), reason: 'not its');
    });

    test('a shade that cannot be read does not stop the removal', () async {
      LocalNotifications.shadeOverride = _Shade(const [], failing: true);
      await LocalNotifications.forgetAccount('gone');
    });
  });

  group('a missed call (AUD-14g-5, AUD-14g-6)', () {
    MissedCallEvent missed({bool muted = false}) => MissedCallEvent(
      IncomingNotice(
        conversationId: 'dm:alice',
        messageRowid: 1,
        messageId: 'c1',
        sender: 'alice',
        kind: 'call',
        preview: '',
        muted: muted,
        sentAt: DateTime.utc(2026, 10, 26),
      ),
    );

    test('is raised away from the app, in a chat that is not muted', () {
      expect(
        missedCallNeedsNotification(missed(), inForeground: false),
        isTrue,
      );
    });

    test('a muted chat posts nothing', () {
      expect(
        missedCallNeedsNotification(missed(muted: true), inForeground: false),
        isFalse,
      );
    });

    test('a person looking at the app needs no notification', () {
      expect(
        missedCallNeedsNotification(missed(), inForeground: true),
        isFalse,
      );
    });

    test('`inactive` (the shade over the app) is on screen', () {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      expect(appInForeground(), isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(appInForeground(), isFalse);
    });
  });

  group('the push token source (AUD-14g-7)', () {
    test('a failed start is asked again, not remembered', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var starts = 0;
      final source = PushTokenSource(
        start: () async {
          starts++;
          if (starts == 1) throw StateError('no Play services yet');
          return _Messaging();
        },
      );
      expect(await source.prepare(), isFalse);
      expect(await source.prepare(), isTrue);
      expect(starts, 2);
      // A start that worked is kept.
      expect(await source.prepare(), isTrue);
      expect(starts, 2);
    });

    test('concurrent callers share one attempt', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var starts = 0;
      final source = PushTokenSource(
        start: () async {
          starts++;
          return _Messaging();
        },
      );
      expect(await Future.wait([source.prepare(), source.prepare()]), [
        true,
        true,
      ]);
      expect(starts, 1);
    });
  });
}

final class _Shade implements NotificationShade {
  _Shade(this.entries, {this.failing = false});

  final List<ShadeEntry> entries;
  final bool failing;
  final cancelled = <int>[];

  @override
  Future<List<ShadeEntry>> active() async {
    if (failing) throw StateError('no shade');
    return entries;
  }

  @override
  Future<void> cancel(int id) async {
    if (failing) throw StateError('no shade');
    cancelled.add(id);
  }
}

final class _Messaging extends Fake implements FirebaseMessaging {}
