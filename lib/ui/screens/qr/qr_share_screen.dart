// lib/ui/screens/qr/qr_share_screen.dart
//
// Shows the local device's session QR code with a countdown timer.
// The QR is session-scoped: when the session ends or the 5-minute window
// expires the code is marked invalid.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/qr_code_service.dart';
import 'package:helix/ui/app_router.dart';

class QrShareScreen extends ConsumerStatefulWidget {
  const QrShareScreen({super.key});

  @override
  ConsumerState<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends ConsumerState<QrShareScreen> {
  static const _service = QrCodeService();

  String? _qrData;
  String? _error;
  Duration _remaining = kQrValidityDuration;
  Timer? _timer;
  StreamSubscription<ConnectionRequest>? _requestSub;
  bool _loading = false;
  bool _expired = false;
  bool _acceptingRequest = false;

  @override
  void initState() {
    super.initState();
    _requestSub = ref
        .read(requestServiceProvider)
        .incomingRequests
        .listen(_autoAcceptQrRequest);
    _buildQr();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _requestSub?.cancel();
    super.dispose();
  }

  Future<void> _buildQr() async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _qrData = null;
        _expired = false;
      });
    }

    final profileSvc = ref.read(profileServiceProvider);
    final sessionSvc = ref.read(sessionServiceProvider);
    final identity = profileSvc.identity;
    final profile = profileSvc.profile;

    if (identity == null || profile == null) {
      _fail('Profile is not ready yet. Please return Home and try again.');
      return;
    }

    final port = await _activeRequestPort();
    if (port <= 0) {
      _fail('The connection listener is still starting. Please try again.');
      return;
    }

    final localIps = await _localLanIps();
    if (localIps.isEmpty) {
      _fail(
        'No local network address was found. Connect to Wi-Fi and try again.',
      );
      return;
    }

    final payload = QrPayload(
      displayName: profile.displayName,
      deviceSuffix: identity.deviceSuffix,
      localIp: localIps.first,
      localIps: localIps,
      tcpPort: port,
      sessionId: sessionSvc.sessionId,
    );

    final qrData = _service.encode(payload);

    if (!mounted) return;
    setState(() {
      _qrData = qrData;
      _loading = false;
      _error = null;
      _remaining = kQrValidityDuration;
      _expired = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _expired = true;
          _timer?.cancel();
        }
      });
    });
  }

  Future<int> _activeRequestPort() async {
    for (var i = 0; i < 15; i++) {
      final int port = ref.read(activeTcpPortProvider);
      if (port > 0) return port;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return 0;
    }
    final int finalPort = ref.read(activeTcpPortProvider);
    return finalPort;
  }

  Future<List<String>> _localLanIps() async {
    final ips = <String>[];
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (_isUsableLanIp(wifiIp)) ips.add(wifiIp!);
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (_isUsableLanIp(ip)) ips.add(ip);
        }
      }
    } catch (_) {}

    return ips.toSet().toList();
  }

  bool _isUsableLanIp(String? ip) {
    if (ip == null || ip.isEmpty) return false;
    return ip != '127.0.0.1' && !ip.startsWith('169.254.');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
      _qrData = null;
      _expired = false;
    });
  }

  Future<void> _autoAcceptQrRequest(ConnectionRequest request) async {
    if (!mounted ||
        _acceptingRequest ||
        _qrData == null ||
        _expired ||
        request.direction != RequestDirection.incoming ||
        request.status != RequestStatus.pending) {
      return;
    }

    final identity = ref.read(profileServiceProvider).identity;
    if (identity == null) return;
    final sessionId = ref.read(sessionServiceProvider).sessionId;

    _acceptingRequest = true;
    try {
      final channel = await ref
          .read(requestServiceProvider)
          .acceptRequest(request.requestId, identity, sessionId);
      if (!mounted || channel == null) return;

      ref
          .read(messagingServiceProvider)
          .attachChannel(
            channel.threadId,
            request.peerDisplayName,
            request.peerDeviceSuffix,
            channel,
            request.peerSessionId,
            request.peerHost,
            request.peerPort,
          );
      ref.read(requestServiceProvider).closeRequestSocket(request.requestId);
      ref.read(pendingRequestsProvider.notifier).remove(request.requestId);

      if (!mounted) return;
      Navigator.of(context)
        ..pop()
        ..pushNamed('${AppRoutes.chat}/${channel.threadId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('QR request failed: $e')));
      }
    } finally {
      _acceptingRequest = false;
    }
  }

  String _formatCountdown(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share via QR')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Let a nearby device scan this code to connect directly.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const CircularProgressIndicator()
                else if (_error != null)
                  _QrErrorCard(message: _error!, onRetry: _buildQr)
                else if (_expired)
                  _ExpiredCard(onRefresh: _buildQr)
                else if (_qrData != null)
                  _QrCard(qrData: _qrData!, remaining: _remaining)
                else
                  _QrErrorCard(
                    message: 'QR code is not ready yet. Please try again.',
                    onRetry: _buildQr,
                  ),
                const SizedBox(height: 16),
                if (!_expired && _qrData != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Expires in ${_formatCountdown(_remaining)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                if (!isDesktop)
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/qr-scan'),
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan a code instead'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrErrorCard extends StatelessWidget {
  const _QrErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: SizedBox(
        width: 260,
        height: 240,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off_outlined,
                size: 42,
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.qrData, required this.remaining});

  final String qrData;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fade the QR toward half-opacity in the last 30 seconds.
    final opacity = remaining.inSeconds <= 30
        ? 0.5 + 0.5 * (remaining.inSeconds / 30)
        : 1.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Opacity(
          opacity: opacity,
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 240,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: theme.colorScheme.onSurface,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: theme.colorScheme.onSurface,
            ),
            backgroundColor: theme.colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class _ExpiredCard extends StatelessWidget {
  const _ExpiredCard({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: SizedBox(
        width: 240,
        height: 240,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text('Code expired', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRefresh,
              child: const Text('Generate new code'),
            ),
          ],
        ),
      ),
    );
  }
}
