import 'package:flutter/material.dart';

enum LaunchStatus {
  deploying,
  retrievingData,
  connecting,
  validating,
  syncing,
  unreachable,
}

class LaunchSkeletonWidget extends StatelessWidget {
  const LaunchSkeletonWidget({
    super.key,
    required this.status,
    required this.serverUrl,
    required this.onConnectDifferentServer,
    required this.onRetry,
  });

  final LaunchStatus status;
  final String serverUrl;
  final VoidCallback onConnectDifferentServer;
  final VoidCallback onRetry;

  String get _statusText {
    switch (status) {
      case LaunchStatus.deploying:
        return 'Deploying Helix Admin…';
      case LaunchStatus.retrievingData:
        return 'Retrieving user data…';
      case LaunchStatus.connecting:
        return 'Connecting to the server…';
      case LaunchStatus.validating:
        return 'Validating user account…';
      case LaunchStatus.syncing:
        return 'Syncing…';
      case LaunchStatus.unreachable:
        return 'Server unreachable or down.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnreachable = status == LaunchStatus.unreachable;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Icon & Header
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDBEAFE)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 32,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Helix Admin',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Administrative Operations Portal',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 36),

                    if (!isUnreachable) ...[
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _statusText,
                          key: ValueKey(status),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (serverUrl.isNotEmpty)
                        Text(
                          serverUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'monospace',
                          ),
                        ),
                    ] else ...[
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 42,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Server unreachable or down.',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.0,
                        ),
                      ),
                      if (serverUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          serverUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: const Text(
                          'Connect to a different server',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onConnectDifferentServer,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF334155),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Retry Connection',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onRetry,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
