import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/platform/app_blob_store.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show PersonNaming;

/// The FirebaseMessaging background handler.
///
/// Firebase runs this in its own isolate when a data-only message arrives with
/// the app closed. It builds its **own** engine - nothing is shared with the UI
/// isolate - opens the same encrypted database with the key from the keystore,
/// reads the mailbox once over REST, applies everything, sends whatever that
/// queued, and raises a local notification for what arrived.
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
    final serverUrl = await ServerUrlStore().load();
    if (serverUrl == null) return; // Signed out: nothing to wake for.
    final uri = Uri.tryParse(serverUrl);
    if (uri == null || !uri.hasScheme) return;

    final file = await AppPaths.databaseFile();
    final key = await SecureKeyStore().keyFor(file);
    final runtime = await HelixRuntime.open(
      dbFile: file,
      key: key,
      serverUrl: uri,
      phoneBook: const DevicePhoneBook(),
      blobs: AppBlobStore(await AppPaths.attachmentCache()),
      config: engineConfigFor(
        deviceName: 'Helix device',
        platform: pushDevicePlatform,
      ),
      // No socket and no timers: this isolate lives for one pass.
      headless: true,
    );
    try {
      final summary = await runtime.engine.syncOnce();
      // Alerts are settings (Settings > Notifications): off still records the
      // message, it only stays quiet. A muted chat never alerts.
      final settings = runtime.engine.settings;
      final direct = await settings.get(AppSettings.notifyMessages);
      final groups = await settings.get(AppSettings.notifyGroups);
      final audible = [
        for (final notice in summary.notices)
          if (!notice.muted &&
              (notice.conversationId.startsWith('group:') ? groups : direct))
            notice,
      ];
      if (audible.isNotEmpty) {
        await LocalNotifications.init();
        await LocalNotifications.showMessages(
          count: audible.length,
          sound: await settings.get(AppSettings.notifySound),
          vibrate: await settings.get(AppSettings.notifyVibrate),
          // Only when the person opted in, and only for one message: the text
          // comes from this phone's own decrypted copy, never from the push.
          preview:
              audible.length == 1 &&
                  await settings.get(AppSettings.notificationsPreview) &&
                  audible.first.preview.isNotEmpty
              ? audible.first.preview
              : null,
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
          callerName: person == null
              ? 'Helix user'
              : PersonNaming.displayName(person),
          fullScreen: true,
        );
      }
    } finally {
      await runtime.close();
    }
  } on Object catch (error) {
    // A background isolate must never crash the app, and must never log
    // anything that could name content, a key or a number.
    debugPrint('[push] background wake failed: ${error.runtimeType}');
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
