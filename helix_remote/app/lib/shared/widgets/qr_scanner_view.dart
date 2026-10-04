import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Builds the camera preview that reads QR codes and reports each text it
/// finds. The one place the camera plugin is used for scanning; everything
/// else asks for this through [qrScannerBuilderProvider], so a widget test
/// can swap the camera for a button.
typedef QrScannerBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onText);

/// The scanner. Overridden in tests; the default is the device camera.
final qrScannerBuilderProvider = Provider<QrScannerBuilder>(
  (ref) =>
      (context, onText) => CameraQrScanner(onText: onText),
);

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
          'The camera is not available. Allow camera access in your phone '
          'settings to scan a code.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
