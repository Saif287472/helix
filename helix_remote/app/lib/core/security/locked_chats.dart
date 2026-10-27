import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/security/device_auth.dart';

/// Whether locked chats may be shown right now.
///
/// The answer is yes only after the phone's own unlock (fingerprint, face,
/// PIN) was passed, and it is taken back when the app leaves the screen
/// ([lock]) and when the last screen that shows a locked chat closes
/// ([release]). Screens that show locked content [hold] it while they live.
final class LockedChatAccess extends Notifier<bool> {
  int _holders = 0;

  @override
  bool build() => false;

  /// Asks for the phone's unlock; true when locked chats may be shown.
  Future<bool> unlock([
    String reason = 'Unlock to see your locked chats',
  ]) async {
    if (state) return true;
    final ok = await ref.read(deviceAuthenticatorProvider).confirm(reason);
    if (ok) state = true;
    return ok;
  }

  /// Takes the access back (the app left the screen).
  void lock() => state = false;

  /// A screen showing locked content opened.
  void hold() => _holders++;

  /// It closed; with none left, the access is taken back.
  void release() {
    if (_holders > 0) _holders--;
    // The whole app may be going (a closing scope): nothing left to tell.
    if (_holders == 0 && ref.mounted) state = false;
  }
}

final lockedChatAccessProvider = NotifierProvider<LockedChatAccess, bool>(
  LockedChatAccess.new,
);

/// Why a chat cannot be locked on this phone, or null when it can: locking
/// rests on the phone's own screen lock, so without one a lock would be only
/// a cover.
Future<String?> whyNotLock(DeviceAuthenticator auth) async =>
    await auth.isAvailable()
    ? null
    : 'Set a screen lock (PIN, pattern or fingerprint) on your phone to lock '
          'chats.';
