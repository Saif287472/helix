import 'package:flutter/material.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One round control in the call tray.
class CallControl {
  const CallControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.toggled,
    this.danger = false,
  });

  final IconData icon;

  /// The short word under the button ("Mute").
  final String label;

  /// What the button will do, for the tooltip and screen readers
  /// ("Unmute microphone"). Defaults to [label].
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Non-null for a toggle; true paints the button filled.
  final bool? toggled;

  /// The red hang-up button.
  final bool danger;
}

/// A round button with its label underneath. Used by the tray and by the
/// incoming screen's big Accept / Decline pair.
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.diameter,
    this.tooltip,
    this.toggled,
    this.fill,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double diameter;
  final bool? toggled;

  /// Overrides the idle/toggled fill (Accept, Decline, End).
  final Color? fill;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final isOn = toggled ?? false;
    final background = !enabled
        ? (fill == null
              ? HelixScrimColors.controlSurface
              : HelixCallColors.controlDisabled)
        : fill ??
              (isOn
                  ? HelixCallColors.controlToggled
                  : HelixCallColors.controlIdle);
    final foreground = !enabled
        ? HelixScrimColors.onBackdropFaint
        : iconColor ??
              (isOn && fill == null
                  ? HelixCallColors.onControlToggled
                  : HelixScrimColors.onBackdrop);
    final size = diameter < 48 ? 48.0 : diameter;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      toggled: toggled,
      label: tooltip ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: background,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox.square(
                  dimension: size,
                  child: Icon(icon, color: foreground, size: size * 0.44),
                ),
              ),
            ),
            // The label is part of the target, so a tap on the word works.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed,
              child: SizedBox(
                width: size + 16,
                child: Padding(
                  padding: HelixInsets.only(top: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: enabled
                            ? HelixScrimColors.onBackdrop
                            : HelixScrimColors.onBackdropFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact rounded tray: exactly one row of evenly spaced controls,
/// sized from the available width so five buttons fit a 360 dp phone.
class CallControlTray extends StatelessWidget {
  const CallControlTray({super.key, required this.controls});

  final List<CallControl> controls;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HelixCallColors.controlPanel,
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 6, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / controls.length;
            final diameter = (slot - 12).clamp(48.0, 60.0);
            // Top-aligned so a label shrunk by FittedBox never nudges its
            // button off the shared row.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final control in controls)
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: CallRoundButton(
                        icon: control.icon,
                        label: control.label,
                        tooltip: control.tooltip,
                        onPressed: control.onPressed,
                        toggled: control.toggled,
                        diameter: diameter,
                        fill: control.danger && control.onPressed != null
                            ? HelixCallColors.endCall
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Builds the tray contents for [status].
///
/// Audio: Speaker, Video, Mute, End. Video: Flip camera, Video, Mute,
/// Speaker, End. Everything is disabled once the call has finished.
List<CallControl> buildCallControls({
  required RemoteCallStatus status,
  required bool finished,
  required VoidCallback onEnd,
  void Function({required bool muted})? onMute,
  void Function({required bool enabled})? onSpeaker,
  void Function({required bool enabled})? onVideo,
  VoidCallback? onSwitchCamera,
}) {
  VoidCallback? live(VoidCallback? action) => finished ? null : action;

  final speaker = CallControl(
    icon: status.isSpeakerOn ? Icons.volume_up : Icons.volume_up_outlined,
    label: 'Speaker',
    tooltip: status.isSpeakerOn ? 'Turn speaker off' : 'Turn speaker on',
    toggled: status.isSpeakerOn,
    onPressed: live(
      onSpeaker == null ? null : () => onSpeaker(enabled: !status.isSpeakerOn),
    ),
  );
  final mute = CallControl(
    icon: status.isMuted ? Icons.mic_off : Icons.mic,
    label: 'Mute',
    tooltip: status.isMuted ? 'Unmute microphone' : 'Mute microphone',
    toggled: status.isMuted,
    onPressed: live(
      onMute == null ? null : () => onMute(muted: !status.isMuted),
    ),
  );
  // A voice call cannot be upgraded to video by the engine, so the button is
  // shown for a stable layout but is honestly unavailable.
  final cameraOn = status.isVideo && status.isLocalVideoEnabled;
  final video = CallControl(
    icon: cameraOn ? Icons.videocam : Icons.videocam_off,
    label: 'Video',
    tooltip: !status.isVideo
        ? 'Video is not available on a voice call'
        : cameraOn
        ? 'Turn camera off'
        : 'Turn camera on',
    toggled: status.isVideo ? !cameraOn : null,
    onPressed: live(
      !status.isVideo || onVideo == null
          ? null
          : () => onVideo(enabled: !status.isLocalVideoEnabled),
    ),
  );
  final end = CallControl(
    icon: Icons.call_end,
    label: 'End',
    tooltip: 'End call',
    danger: true,
    onPressed: live(onEnd),
  );

  if (!status.isVideo) return [speaker, video, mute, end];
  final flip = CallControl(
    icon: Icons.cameraswitch,
    label: 'Flip',
    tooltip: 'Flip camera',
    onPressed: live(onSwitchCamera),
  );
  return [flip, video, mute, speaker, end];
}
