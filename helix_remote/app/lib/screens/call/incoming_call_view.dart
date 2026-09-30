import 'package:flutter/material.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'package:helix_remote/screens/call/call_controls.dart';
import 'package:helix_remote/screens/call/call_parts.dart';

/// Full-screen incoming call: who is calling, and two big buttons.
class IncomingCallView extends StatelessWidget {
  const IncomingCallView({
    super.key,
    required this.status,
    required this.onAccept,
    required this.onDecline,
    this.peerSubtitle,
    this.onMessage,
  });

  final RemoteCallStatus status;
  final VoidCallback? onAccept;
  final VoidCallback onDecline;
  final String? peerSubtitle;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = status.isVideo ? 'video' : 'voice';
    final subtitle = peerSubtitle?.trim() ?? '';

    return CallSurface(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 520;
            final avatar = (constraints.maxHeight * (compact ? 0.28 : 0.3))
                .clamp(72.0, 140.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: HelixInsets.symmetric(
                    horizontal: HelixSpace.lg,
                    vertical: compact ? HelixSpace.sm : HelixSpace.lg,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      EncryptedCallLabel(prefix: 'Helix $kind call'),
                      SizedBox(height: compact ? 12 : 32),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CallAvatar(
                            status: status,
                            diameter: avatar,
                            pulse: true,
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          Semantics(
                            header: true,
                            child: Text(
                              status.displayName,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: HelixScrimColors.onBackdrop,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: HelixInsets.only(top: 4),
                              child: Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: HelixScrimColors.onBackdropMuted,
                                ),
                              ),
                            ),
                          Padding(
                            padding: HelixInsets.only(top: 8),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                'Incoming $kind call',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: HelixScrimColors.onBackdropMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 12 : 40),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: CallRoundButton(
                                  icon: Icons.call_end,
                                  label: 'Decline',
                                  tooltip: 'Decline call',
                                  diameter: 72,
                                  fill: HelixCallColors.endCall,
                                  onPressed: onDecline,
                                ),
                              ),
                              Flexible(
                                child: CallRoundButton(
                                  icon: status.isVideo
                                      ? Icons.videocam
                                      : Icons.call,
                                  label: 'Accept',
                                  tooltip: status.isVideo
                                      ? 'Accept video call'
                                      : 'Accept call',
                                  diameter: 72,
                                  fill: HelixCallColors.answerCall,
                                  onPressed: onAccept,
                                ),
                              ),
                            ],
                          ),
                          if (onMessage != null)
                            Padding(
                              padding: HelixInsets.only(top: 12),
                              child: TextButton.icon(
                                onPressed: onMessage,
                                style: TextButton.styleFrom(
                                  foregroundColor: HelixScrimColors.onBackdrop,
                                  minimumSize: const Size(48, 48),
                                ),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Message'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
