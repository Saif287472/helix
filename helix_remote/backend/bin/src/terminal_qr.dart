import 'package:qr/qr.dart';

/// Renders [data] as a QR code drawn with Unicode half-block characters, so
/// a server operator can point the Helix Admin app's camera straight at
/// their terminal instead of hand-typing a long token. Two QR module rows
/// are packed into each terminal line (a terminal character cell is roughly
/// twice as tall as it is wide), which keeps the printed code close to
/// square and easy to scan.
String renderTerminalQr(String data) {
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  final moduleCount = qrImage.moduleCount;

  bool isDark(int row, int col) {
    if (row < 0 || row >= moduleCount || col < 0 || col >= moduleCount) {
      return false; // quiet zone around the code
    }
    return qrImage.isDark(row, col);
  }

  const quietZone = 2;
  final buffer = StringBuffer();
  for (var row = -quietZone; row < moduleCount + quietZone; row += 2) {
    for (var col = -quietZone; col < moduleCount + quietZone; col++) {
      final top = isDark(row, col);
      final bottom = isDark(row + 1, col);
      if (top && bottom) {
        buffer.write('█'); // full block
      } else if (top) {
        buffer.write('▀'); // upper half block
      } else if (bottom) {
        buffer.write('▄'); // lower half block
      } else {
        buffer.write(' ');
      }
    }
    buffer.writeln();
  }
  return buffer.toString();
}
