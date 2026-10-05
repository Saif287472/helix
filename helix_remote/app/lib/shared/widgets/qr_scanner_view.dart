import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Builds the camera preview that reads QR codes and reports each text it
/// finds. **The one place the camera plugin is used for scanning** (the people
/// feature's safety number check and the devices feature's link approval both
/// read it); everything else asks for this through [qrScannerBuilderProvider],
/// so a widget test can swap the camera for a button.
typedef QrScannerBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onText);

/// The scanner: the device camera on Android and iOS, null where the platform
/// has none (Windows), and the screens then fall back to a pasted code or the
/// numbers read by eye. Overridden in tests.
final qrScannerBuilderProvider = Provider<QrScannerBuilder?>((ref) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => _camera,
    _ => null,
  };
});

Widget _camera(BuildContext context, ValueChanged<String> onText) =>
    CameraQrScanner(onText: onText);

/// A live camera preview that reports the text of each QR code it sees.
class CameraQrScanner extends StatefulWidget {
  const CameraQrScanner({super.key, required this.onText});

  final ValueChanged<String> onText;

  @override
  State<CameraQrScanner> createState() => _CameraQrScannerState();
}

class _CameraQrScannerState extends State<CameraQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _controller,
    onDetect: (capture) {
      for (final barcode in capture.barcodes) {
        final text = barcode.rawValue;
        if (text != null && text.isNotEmpty) {
          widget.onText(text);
          return;
        }
      }
    },
    errorBuilder: (context, error) => const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The camera is not available. Allow camera access for Helix in your '
          'phone settings to scan a code.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
