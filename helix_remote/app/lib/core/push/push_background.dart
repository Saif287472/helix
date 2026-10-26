import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/app_blob_store.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote/core/push/account_badges.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/core/sounds/orbit_ringtones.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show IncomingNotice;

/// The FirebaseMessaging background handler.
///
/// Firebase runs this in its own isolate when a data-only message arrives with
/// the app closed. It builds its **own** engine - nothing is shared with the UI
/// isolate - and, for every account signed in on this device in turn, opens
/// its encrypted database with its key from the keystore, reads the mailbox
/// once over REST, applies everything, sends whatever that queued, leaves the
/// unread count for the account lists, and raises a local notification for what
/// arrived - but only for the account this phone was last on. The others are
/// quiet numbers until they are opened.
///
/// The wake-up does not say which account it is for (the payload carries no
/// account, by design), and one FCM token serves every account here. That is
/// why the alert is chosen here, from the accounts this device keeps, and not
/// by anything the payload could have said.
///
/// It never reads content from the payload. The payload is only a wake-up
/// (`{t: message}`); the engine decrypts the real message, so nothing that
/// crossed a push provider can end up on the lock screen.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The plugin registrant has to run before any plugin is touched in this
  // isolate; without it the keystore and the database are unreachable.
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await wakeSignedInAccounts();
  } on Object catch (error) {
    // A background isolate must never crash the app, and must never log
    // anything that could name content, a key or a number.
    debugPrint('[push] background wake failed: ${error.runtimeType}');
  }
}

/// Opens every account signed in on this device except [except]. A wake-up
/// reads its mailbox and leaves its unread count where the account lists can
/// read it; only the account this phone was last on raises a notification for
/// what arrived, and a call rings whoever it came for. [pushToken], when
/// present, is registered first. The running app uses [syncMailbox] false for
/// a token-only pass.
///
/// [unregister] is the opposite of [pushToken]: it tells each account's server
/// to forget this device's token (the person turned wake-ups off) and does
/// nothing else.
Future<void> wakeSignedInAccounts({
  String? except,
  String? pushToken,
  bool syncMailbox = true,
  bool unregister = false,
}) async {
  final accounts = await AccountSlotStore().load();
  final keys = SecureKeyStore();
  // Signed out everywhere: nothing to wake for.
  for (final account in accounts.signedIn) {
    if (account.id == except) continue;
    final uri = Uri.tryParse(account.server);
    if (uri == null || !uri.hasScheme) continue;
    try {
      await _wakeAccount(
        account.id,
        uri,
        keys,
        label: accounts.notificationLabel(account.id),
        // Only the account this phone was last on may raise a notification;
        // the others are read and counted the same way and stay a number on
        // their row (see AccountSlots.notifies). A call still rings whoever it
        // came for.
        alerts: accounts.notifies(account.id),
        pushToken: pushToken,
        syncMailbox: syncMailbox,
        unregister: unregister,
      );
    } on EngineAlreadyRunning {
      // The running app owns this account's database and fetches the
      // mailbox itself; a second engine here would race it over the same
      // ratchets.
    } on Object catch (error) {
      // One account that cannot be read does not stop the others.
      debugPrint('[push] wake failed: ${error.runtimeType}');
      AnomalyLog.state(
        'push.wake',
        'account failed',
        fields: {'error': error.runtimeType.toString()},
      );
    }
  }
}

Future<void> _wakeAccount(
  String account,
  Uri uri,
  SecureKeyStore keys, {
  String? label,
  String? pushToken,
  bool alerts = true,
  required bool syncMailbox,
  bool unregister = false,
}) async {
  final file = await AppPaths.databaseFile(account);
  final key = await keys.keyFor(account, file);
  final runtime = await HelixRuntime.open(
    account: account,
    dbFile: file,
    key: key,
    serverUrl: uri,
    phoneBook: const DevicePhoneBook(),
    blobs: AppBlobStore(await AppPaths.attachmentCache(account)),
    config: engineConfigFor(
      deviceName: 'Orbit device',
      platform: pushDevicePlatform,
    ),
    // No socket and no timers: this isolate lives for one pass.
    headless: true,
    keys: keys,
  );
  // A phone that did not wake leaves no log an operator can read: this
  // isolate is gone before the app's own diagnostics ever run. The wake gives
  // the anomaly log this account's route - only when no sender exists, which
  // is every background pass and never the running app, whose provider installs
  // one at start and would otherwise be left sending through a runtime this
  // pass closes. What the wake counted rides out on it, including what an
  // earlier account failed with.
  final ownsLog = !AnomalyLog.hasSender;
  if (ownsLog) {
    AnomalyLog.install(
      (report) => runtime.api.ops.anomalies(report),
      server: () => AnomalyLog.serverKey(runtime.serverUrl),
    );
  }
  try {
    if (unregister) {
      try {
        await runtime.engine.push.unregister();
      } on Object catch (error) {
        debugPrint('[push] token removal failed: ${error.runtimeType}');
      }
      return;
    }
    if (pushToken != null) {
      try {
        await runtime.engine.push.register(pushToken);
      } on Object catch (error) {
        debugPrint('[push] token update failed: ${error.runtimeType}');
      }
    }
    if (!syncMailbox) return;
    final summary = await runtime.engine.syncOnce();
    // What is waiting here, for the account lists: they cannot open this
    // database (the app holds one engine at a time), so this pass - the only
    // one that reads it while the account is not on screen - leaves the
    // number behind for them.
    await const AccountBadgeStore().write(
      account,
      (await runtime.engine.chats.watchUnread().first).messages,
    );
    // Alerts are settings (Settings > Notifications), applied the same way
    // as by the running app (MessageAlerts), per account.
    final settings = runtime.engine.settings;
    final audible = <IncomingNotice>[];
    for (final notice in summary.notices) {
      if (await MessageAlerts.alerts(notice, settings.get)) {
        audible.add(notice);
      }
    }
    // Counts, never names, numbers or content: what the server woke the phone
    // for, and what this pass found to say about it.
    AnomalyLog.state(
      'push.wake',
      'woken',
      fields: {
        'notices': '${summary.notices.length}',
        'alerted': '${audible.length}',
        'calls': '${summary.pendingCalls.length}',
      },
    );
    if (audible.isNotEmpty && alerts) {
      await LocalNotifications.init();
      // The newest of the run names the notification and gives it its text, so
      // a second message replaces the first instead of blanking the line.
      final latest = audible.reduce(
        (a, b) => a.sentAt.isAfter(b.sentAt) ? a : b,
      );
      final person = await runtime.engine.people.person(latest.sender);
      await MessageAlerts.show(
        settings.get,
        account: account,
        count: audible.length,
        latest: latest,
        // The same name the app shows (phone book, nickname, number, `~Helix
        // name`): this isolate has no providers, so it asks the naming helper
        // for the one row.
        senderName: person == null
            ? PersonName.unknown(latest.sender).display
            : PersonName.fromRow(person).display,
        accountLabel: label,
      );
    }
    if (summary.pendingCalls.isNotEmpty) {
      // The call channel lives on the plugin, which a fresh isolate has not
      // started unless a message was shown first.
      await LocalNotifications.init();
      await CallNotifications.init();
    }
    // One read for this pass: every call it rings rings with the same sound
    // (the device's choice), and this isolate has no providers.
    final ringtone = summary.pendingCalls.isEmpty
        ? null
        : await Ringtones.chosen();
    // A call that rang while the app was closed: the offer waits on the
    // server and is opened by the running app, so all this knows is who is
    // calling. The notification takes the screen over a locked phone and
    // its buttons open the app, which rings the call.
    for (final call in summary.pendingCalls) {
      final person = await runtime.engine.people.person(call.caller);
      await CallNotifications.showIncoming(
        callId: call.callId,
        // The caller's name is content: only when the person turned
        // previews on, like a message's text.
        showCaller: await settings.get(AppSettings.notificationsPreview),
        // The same name the app shows (phone book, nickname, number,
        // `~Helix name`): this isolate has no providers, so it asks the
        // naming helper for the one row.
        callerName: person == null
            ? PersonName.unknown(call.caller).display
            : PersonName.fromRow(person).display,
        fullScreen: true,
        // Its buttons open this account before the call rings.
        account: account,
        ringtone: ringtone,
      );
    }
  } finally {
    if (ownsLog) {
      // Out before the runtime closes: afterwards there is no session to send
      // on, and this isolate will not live to see the next flush tick.
      await AnomalyLog.flush();
      AnomalyLog.install(null);
    }
    await runtime.close();
  }
}

/// Registers the background handler with Firebase.
///
/// Before `runApp`, and Android only: on other platforms Firebase is not
/// wired, which is why a checkout without `google-services.json` still runs.
void registerPushBackgroundHandler() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}
