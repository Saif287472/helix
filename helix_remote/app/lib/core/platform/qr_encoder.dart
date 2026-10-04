import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Encodes [data] as a QR module matrix for `HelixQrDisplay`.
///
/// The UI package never encodes (it only draws a matrix), so the encoder lives
/// here with the `qr_flutter` dependency. Error correction is medium: a link
/// code is about 150 characters and is scanned off a phone screen, where
/// reflections matter more than capacity.
HelixQrMatrix encodeQr(String data) {
  final code = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(code);
  final size = image.moduleCount;
  return HelixQrMatrix(size, [
    for (var y = 0; y < size; y++)
      for (var x = 0; x < size; x++) image.isDark(y, x),
  ]);
}
