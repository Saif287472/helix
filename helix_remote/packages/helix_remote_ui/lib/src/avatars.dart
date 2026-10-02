part of '../helix_remote_ui.dart';

/// Avatar diameters.
enum HelixAvatarSize {
  xs(24),
  sm(32),
  md(40),
  lg(52),
  xl(72);

  const HelixAvatarSize(this.diameter);
  final double diameter;
}

/// A round avatar: the picture when there is one, otherwise initials on a
/// stable palette colour (or a group glyph), with an optional presence dot and
/// a selection check.
///
/// Decorative by default: the name is always announced by the row it sits in.
/// Pass [semanticLabel] when it stands alone (a profile header).
class HelixAvatar extends StatelessWidget {
  const HelixAvatar({
    super.key,
    required this.model,
    this.size = HelixAvatarSize.md,
    this.online = false,
    this.selected = false,
    this.semanticLabel,
  });

  final HelixAvatarModel model;
  final HelixAvatarSize size;

  /// Shows the presence dot.
  final bool online;

  /// Replaces the picture with a check (selection mode).
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = size.diameter;
    final palette = HelixColorTokens.avatarPalette;
    final color = palette[model.colorIndex.abs() % palette.length];
    final Widget face;
    if (selected) {
      face = DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, size: d * .5, color: scheme.onPrimary),
      );
    } else {
      final image = model.image;
      final fallback = _AvatarFallback(model: model, color: color, diameter: d);
      face = image == null
          ? fallback
          : ClipOval(
              child: Image(
                image: ResizeImage.resizeIfNeeded(
                  (d * MediaQuery.devicePixelRatioOf(context)).round(),
                  null,
                  image,
                ),
                width: d,
                height: d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
            );
    }
    final dot = d * .3;
    final stack = SizedBox.square(
      dimension: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: face),
          if (online && !selected)
            PositionedDirectional(
              end: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: HelixStatusColors.positive,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: stack)
        : Semantics(
            label: semanticLabel,
            image: true,
            child: ExcludeSemantics(child: stack),
          );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.model,
    required this.color,
    required this.diameter,
  });
  final HelixAvatarModel model;
  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final child = model.isGroup
        ? Icon(
            Icons.group,
            size: diameter * .55,
            color: HelixScrimColors.onBackdrop,
          )
        : Text(
            model.initials,
            // Fixed size: an avatar is a graphic, it must not outgrow its
            // circle when the user scales text.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: diameter * .4,
              fontWeight: FontWeight.w600,
              color: HelixScrimColors.onBackdrop,
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}

/// The short label for what a message is, used in chat-list previews, reply
/// quotes and banners when there is no text of its own.
String helixPreviewLabel(HelixPreviewKind kind) => switch (kind) {
  HelixPreviewKind.text => '',
  HelixPreviewKind.image => 'Photo',
  HelixPreviewKind.video => 'Video',
  HelixPreviewKind.gif => 'GIF',
  HelixPreviewKind.voiceNote => 'Voice message',
  HelixPreviewKind.document => 'Document',
  HelixPreviewKind.sticker => 'Sticker',
  HelixPreviewKind.location => 'Location',
  HelixPreviewKind.contact => 'Contact',
  HelixPreviewKind.poll => 'Poll',
  HelixPreviewKind.call => 'Call',
  HelixPreviewKind.deleted => 'This message was deleted',
  HelixPreviewKind.undecryptable => "Couldn't decrypt this message",
  HelixPreviewKind.unsupported => 'Needs a newer version of Helix',
};

/// The small glyph shown before a [helixPreviewLabel]; null for plain text.
IconData? helixPreviewIcon(HelixPreviewKind kind) => switch (kind) {
  HelixPreviewKind.text => null,
  HelixPreviewKind.image => Icons.photo_camera_outlined,
  HelixPreviewKind.video => Icons.videocam_outlined,
  HelixPreviewKind.gif => Icons.gif_box_outlined,
  HelixPreviewKind.voiceNote => Icons.mic_none,
  HelixPreviewKind.document => Icons.insert_drive_file_outlined,
  HelixPreviewKind.sticker => Icons.emoji_emotions_outlined,
  HelixPreviewKind.location => Icons.location_on_outlined,
  HelixPreviewKind.contact => Icons.person_outline,
  HelixPreviewKind.poll => Icons.poll_outlined,
  HelixPreviewKind.call => Icons.call_outlined,
  HelixPreviewKind.deleted => Icons.block,
  HelixPreviewKind.undecryptable => Icons.lock_outline,
  HelixPreviewKind.unsupported => Icons.system_update_alt,
};

/// The delivery tick for [status]: one tick (pending clock, sent), two
/// (delivered), two blue (read), or a red "!" (failed).
///
/// [color] is the neutral tick colour (defaults to the bubble metadata
/// colour); read and failed use their own status colours. Retrying a failed
/// message is a separate 48 px button under the bubble, not this glyph.
class HelixStatusTicks extends StatelessWidget {
  const HelixStatusTicks({
    super.key,
    required this.status,
    this.size = 16,
    this.color = HelixChatColors.metaText,
  });

  final HelixDeliveryStatus status;
  final double size;
  final Color color;

  static String labelFor(HelixDeliveryStatus status) => switch (status) {
    HelixDeliveryStatus.pending => 'Sending',
    HelixDeliveryStatus.sent => 'Sent',
    HelixDeliveryStatus.delivered => 'Delivered',
    HelixDeliveryStatus.read => 'Read',
    HelixDeliveryStatus.failed => 'Not sent',
  };

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      HelixDeliveryStatus.pending => Icon(
        Icons.schedule,
        size: size - 2,
        color: color,
      ),
      HelixDeliveryStatus.sent => Icon(Icons.done, size: size, color: color),
      HelixDeliveryStatus.delivered => Icon(
        Icons.done_all,
        size: size,
        color: color,
      ),
      HelixDeliveryStatus.read => Icon(
        Icons.done_all,
        size: size,
        color: HelixChatColors.readTick,
      ),
      HelixDeliveryStatus.failed => Icon(
        Icons.error,
        size: size,
        color: HelixStatusColors.danger,
      ),
    };
    final label = labelFor(status);
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: icon),
    );
  }
}
