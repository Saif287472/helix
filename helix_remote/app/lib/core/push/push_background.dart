import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show IncomingNotice;

/// The FirebaseMessaging background handler.
///
/// Firebase runs this in its own isolate when a data-only message arrives with
/// the app closed. It builds its **own** engine - nothing is shared with the UI
/// isolate - and, for every account signed in on this device in turn, opens
/// its encrypted database with its key from the keystore, reads the mailbox
/// once over REST, applies everything, sends whatever that queued, and raises
/// a local notification for what arrived.
///
/// The wake-up does not say which account it is for (the payload carries no
/// account, by design), and one FCM token serves every account here.
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
    final accounts = await AccountSlotStore().load();
    final keys = SecureKeyStore();
    // Signed out everywhere: nothing to wake for.
    for (final account in accounts.signedIn) {
      final uri = Uri.tryParse(account.server);
      if (uri == null || !uri.hasScheme) continue;
      try {
        await _wakeAccount(account.id, uri, keys);
      } on EngineAlreadyRunning {
        // The running app owns this account's database and fetches the
        // mailbox itself; a second engine here would race it over the same
        // ratchets.
      } on Object catch (error) {
        // One account that cannot be read does not stop the others.
        debugPrint('[push] background wake failed: ${error.runtimeType}');
      }
    }
  } on Object catch (error) {
    // A background isolate must never crash the app, and must never log
    // anything that could name content, a key or a number.
    debugPrint('[push] background wake failed: ${error.runtimeType}');
  }
}

Future<void> _wakeAccount(String account, Uri uri, SecureKeyStore keys) async {
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
      deviceName: 'Helix device',
      platform: pushDevicePlatform,
    ),
    // No socket and no timers: this isolate lives for one pass.
    headless: true,
    keys: keys,
  );
  try {
    final summary = await runtime.engine.syncOnce();
    // Alerts are settings (Settings > Notifications), applied the same way
    // as by the running app (MessageAlerts), per account.
    final settings = runtime.engine.settings;
    final audible = <IncomingNotice>[];
    for (final notice in summary.notices) {
      if (await MessageAlerts.alerts(notice, settings.get)) {
        audible.add(notice);
      }
    }
    if (audible.isNotEmpty) {
      await LocalNotifications.init();
      await MessageAlerts.show(
        settings.get,
        count: audible.length,
        only: audible.length == 1 ? audible.first : null,
      );
    }
    if (summary.pendingCalls.isNotEmpty) {
      await CallNotifications.init();
    }
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
      );
    }
  } finally {
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
