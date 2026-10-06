import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The temporary copies the system file picker leaves behind.
///
/// On Android a picked photo, video or document is first copied into the app's
/// cache so a plain path can be handed back; nothing deletes it afterwards.
/// Those copies are plaintext, outside the encrypted database and outside the
/// attachment store (which the engine owns), so they are cleared as soon as the
/// engine has made its own copy (after a send) and at sign-out.
abstract final class PickerTemporaryFiles {
  /// What actually clears them. Replaced in tests.
  @visibleForTesting
  static Future<void> Function() clearer = FilePicker.clearTemporaryFiles;

  /// Clears them, quietly: a platform without the plugin has nothing to clear,
  /// and a failure here must never fail a send or a sign-out.
  static Future<void> clear() async {
    try {
      await clearer();
    } on Object {
      // Nothing to do about it; the next send or sign-out tries again.
    }
  }
}
