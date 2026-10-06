import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the platform's share sheet.
///
/// Behind an interface so an export can be tested without a share sheet, and
/// so the screens never import a plugin.
abstract interface class ShareAdapter {
  /// Shares [bytes] as a file called [filename]. Returns false when the
  /// platform has no share sheet or the person dismissed it.
  Future<bool> shareFile({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  });
}

final class DeviceShareAdapter implements ShareAdapter {
  const DeviceShareAdapter();

  @override
  Future<bool> shareFile({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
          fileNameOverrides: [filename],
        ),
      );
      return result.status != ShareResultStatus.unavailable &&
          result.status != ShareResultStatus.dismissed;
    } on Object {
      return false;
    }
  }
}

final shareAdapterProvider = Provider<ShareAdapter>(
  (ref) => const DeviceShareAdapter(),
);
