import 'package:flutter/material.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/presentation/call_parts.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Full-screen incoming call: who is calling, and two big buttons.
///
/// Shown over the lock screen by the app's call host (the window flags come
/// from the platform integration), so it carries nothing but the caller's name
/// and the two answers.
class IncomingCallView extends StatelessWidget {
  const IncomingCallView({
    super.key,
    required this.state,
    required this.onAccept,
    required this.onDecline,
    this.onDismissNotice,
  });

  final CallScreenState state;

  /// Null while an answer is already in flight.
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onDismissNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = state.video ? 'video' : 'voice';
    final subtitle = state.subtitle?.trim() ?? '';
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
                  padding: EdgeInsets.symmetric(
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
                            avatar: state.avatar,
                            diameter: avatar,
                            pulse: true,
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          Semantics(
                            header: true,
                            child: Text(
                              state.title,
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
                              padding: const EdgeInsets.only(top: 4),
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                state.statusText,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: HelixScrimColors.onBackdropMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 12 : 24),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.notice != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: CallNoticeBar(
                                message: state.notice!,
                                onDismiss: onDismissNotice,
                              ),
                            ),
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
                                  icon: state.video
                                      ? Icons.videocam
                                      : Icons.call,
                                  label: 'Answer',
                                  tooltip: state.video
                                      ? 'Answer video call'
                                      : 'Answer call',
                                  diameter: 72,
                                  fill: HelixCallColors.answerCall,
                                  onPressed: onAccept,
                                ),
                              ),
                            ],
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
