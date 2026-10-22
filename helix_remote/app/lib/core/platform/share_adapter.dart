import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file or a link to the platform's share sheet.
///
/// Behind an interface so a share can be tested without a share sheet, and so
/// the screens never import a plugin.
abstract interface class ShareAdapter {
  /// Shares [bytes] as a file called [filename]. Returns false when the
  /// platform has no share sheet or the person dismissed it.
  Future<bool> shareFile({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  });

  /// Shares [text] - a link, with no file attached. Returns false when the
  /// platform has no share sheet or the person dismissed it.
  Future<bool> shareText({required String text, String? subject});
}

final class DeviceShareAdapter implements ShareAdapter {
  const DeviceShareAdapter();

  @override
  Future<bool> shareFile({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async => _send(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
      fileNameOverrides: [filename],
    ),
  );

  @override
  Future<bool> shareText({required String text, String? subject}) =>
      _send(ShareParams(text: text, subject: subject));

  Future<bool> _send(ShareParams params) async {
    try {
      final result = await SharePlus.instance.share(params);
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
