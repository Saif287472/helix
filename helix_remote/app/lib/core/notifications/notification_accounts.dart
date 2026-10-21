import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';

/// Presses on any notification while the app runs. Overridden in tests.
final notificationResponsesProvider = Provider<Stream<NotificationResponse>>(
  (ref) => LocalNotifications.responses,
);

/// The account whose notification started the app, if one did.
final notificationLaunchAccountProvider = Provider<Future<String?>>(
  (ref) async =>
      NotificationPayload.accountOf(await LocalNotifications.launchPayload()),
);

/// A press on a notification of an account that is not on screen opens that
/// account: its chats, or (for a call) its engine, which rings the call and
/// applies the Answer or Decline pressed (`CallNotificationHandler`).
///
/// Read once, by the app root, and kept for the whole run. The press that
/// started the app is applied by `AccountsNotifier.restore` instead, so the
/// account last on screen is never opened only to be closed again.
final notificationAccountSwitchProvider = Provider<void>((ref) {
  final presses = ref.watch(notificationResponsesProvider).listen((response) {
    final account = NotificationPayload.accountOf(response.payload);
    if (account == null) return;
    if (ref.read(activeAccountProvider)?.id == account) return;
    unawaited(ref.read(accountsProvider.notifier).switchTo(account));
  });
  ref.onDispose(presses.cancel);
});
