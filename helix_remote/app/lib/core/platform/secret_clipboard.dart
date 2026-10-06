import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a secret (the recovery secret) to the clipboard or the share sheet,
/// for the person to put somewhere safe.
///
/// A clipboard is not a safe place to leave a secret, so a copy is taken back:
/// a minute later the clipboard is cleared, if it still holds the same text.
/// Behind an interface so a test can see what was handed over without a
/// platform.
abstract interface class SecretHandoff {
  /// Puts [secret] on the clipboard and clears it again after [clearAfter]
  /// (when it still holds [secret]).
  Future<void> copy(String secret);

  /// Opens the share sheet with [secret]. Returns false when there is none or
  /// it was dismissed.
  Future<bool> share(String secret, {required String subject});
}

final class DeviceSecretHandoff implements SecretHandoff {
  const DeviceSecretHandoff({this.clearAfter = const Duration(minutes: 1)});

  final Duration clearAfter;

  @override
  Future<void> copy(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    // Not tied to a widget: closing the page must not leave the secret there.
    Timer(clearAfter, () async {
      try {
        final held = await Clipboard.getData(Clipboard.kTextPlain);
        if (held?.text == secret) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } on Object {
        // The platform may refuse a background read; the copy simply stays.
      }
    });
  }

  @override
  Future<bool> share(String secret, {required String subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: secret, subject: subject),
      );
      return result.status != ShareResultStatus.unavailable &&
          result.status != ShareResultStatus.dismissed;
    } on Object {
      return false;
    }
  }
}

final secretHandoffProvider = Provider<SecretHandoff>(
  (ref) => const DeviceSecretHandoff(),
);
