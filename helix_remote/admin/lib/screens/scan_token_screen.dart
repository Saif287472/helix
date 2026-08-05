import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen scanner for the admin token QR code the backend prints to
/// its own terminal on first boot (or after bin/reset_admin_token.dart).
/// Pops with the scanned token string once a barcode is detected, or with
/// nothing if the user backs out.
class ScanTokenScreen extends StatefulWidget {
  const ScanTokenScreen({super.key});

  @override
  State<ScanTokenScreen> createState() => _ScanTokenScreenState();
}

class _ScanTokenScreenState extends State<ScanTokenScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SCAN SERVER TOKEN')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: const Text(
                'Point the camera at the QR code your server printed when '
                'it first started (or after running '
                'bin/reset_admin_token.dart).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
