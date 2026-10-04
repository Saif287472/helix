import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Builds a live camera preview that reports every code it reads.
///
/// A scanner is a widget, and a feature's presentation may not import a
/// camera plugin, so the plugin sits behind this builder and the screens
/// receive it from [qrScannerBuilderProvider]. Null means "this platform has
/// no scanner" (Windows), and the screens fall back to a pasted code.
typedef QrScannerBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

final qrScannerBuilderProvider = Provider<QrScannerBuilder?>((ref) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => _cameraScanner,
    _ => null,
  };
});

Widget _cameraScanner(BuildContext context, ValueChanged<String> onCode) =>
    _CameraScanner(onCode: onCode);

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
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
        final value = barcode.rawValue;
        if (value != null && value.isNotEmpty) {
          widget.onCode(value);
          return;
        }
      }
    },
    errorBuilder: (context, error) => const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The camera is not available. Allow camera access for Helix, or '
          'paste the code instead.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
