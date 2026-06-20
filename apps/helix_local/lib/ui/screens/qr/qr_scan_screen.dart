// lib/ui/screens/qr/qr_scan_screen.dart
//
// Camera QR scanner for Android.
// On Windows a static info screen is shown instead.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/app_router.dart';
import 'package:helix/ui/screens/home/home_screen.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {

  final _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    final payload = ref.read(qrCodeServiceProvider).decode(raw);
    if (payload == null) return; // not a Helix QR

    setState(() => _processing = true);
    await _controller.stop();

    if (!mounted) return;

    final sessionSvc = ref.read(sessionServiceProvider);
    final peers = ref.read(qrCodeServiceProvider).payloadToPeers(payload);
    if (peers.isEmpty) {
      _showError('QR code has no usable address.');
      setState(() => _processing = false);
      await _controller.start();
      return;
    }

    if (!mounted) return;

    if (await handleExistingActiveThread(context, ref, peers.first)) return;
    if (!mounted) return;

    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) {
      _showError('Profile is not ready yet.');
      setState(() => _processing = false);
      await _controller.start();
      return;
    }
    final displayName = profileSvc.profile?.displayName ?? '';

    Object? lastError;
    try {
      for (final peer in peers) {
        try {
          final result = await ref
              .read(requestServiceProvider)
              .sendRequest(
                peer,
                RequestSourceMethod.directIp,
                identity,
                sessionSvc.sessionId,
                displayName,
                localTcpPort: ref.read(activeTcpPortProvider),
                connectTimeout: const Duration(seconds: 3),
                responseTimeout: const Duration(seconds: 20),
              );

          if (!mounted) return;

          if (result.request.status == RequestStatus.accepted &&
              result.channel != null) {
            ref
                .read(messagingServiceProvider)
                .attachChannel(
                  result.channel!.threadId,
                  result.request.peerDisplayName,
                  result.request.peerDeviceSuffix,
                  result.channel!,
                  result.request.peerSessionId,
                  result.request.peerHost,
                  result.request.peerPort,
                );
            Navigator.of(context)
              ..pop()
              ..pushNamed('${AppRoutes.chat}/${result.channel!.threadId}');
            return;
          }
          lastError = 'Request ${result.request.status.name}.';
        } catch (e) {
          lastError = e;
        }
      }
      _showError('QR connection failed: $lastError');
      setState(() => _processing = false);
      await _controller.start();
    } catch (e) {
      if (mounted) {
        _showError('Connection failed: $e');
        setState(() => _processing = false);
        await _controller.start();
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) return const _DesktopInfo();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_outlined),
            tooltip: 'Toggle torch',
            onPressed: _controller.toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            tooltip: 'Switch camera',
            onPressed: _controller.switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withAlpha(200),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Point the camera at a Helix QR code',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopInfo extends StatelessWidget {
  const _DesktopInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code_scanner,
                size: 64,
                color: theme.colorScheme.onSurface.withAlpha(100),
              ),
              const SizedBox(height: 16),
              Text(
                'Camera scanning is not available on desktop.',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use "Connect by IP" or have a mobile device scan '
                'this device\'s QR code instead.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
