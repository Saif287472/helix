import 'package:share_plus/share_plus.dart';

/// What a person can do with a file that is already on the phone: send it to
/// another app (which is how a document is "opened" and shared on a phone).
abstract interface class FileActions {
  /// Hands [path] to the system share sheet, so the person can open it in an
  /// app that understands it or send it on.
  Future<void> shareFile({
    required String path,
    required String name,
    required String mime,
  });
}

/// The real thing, over `share_plus`.
final class DeviceFileActions implements FileActions {
  const DeviceFileActions();

  @override
  Future<void> shareFile({
    required String path,
    required String name,
    required String mime,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, name: name, mimeType: mime)],
        ),
      );
    } on Object {
      // No share target (a desktop without one): nothing more to do.
    }
  }
}
