import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/push/push_token_source.dart';

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
      config: engineConfigFor(
        deviceName: 'Helix device',
        platform: pushDevicePlatform,
      ),
      // No socket and no timers: this isolate lives for one pass.
      headless: true,
    );
    try {
      final summary = await runtime.engine.syncOnce();
      await LocalNotifications.init();
      await LocalNotifications.showMessages(count: summary.notices.length);
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
