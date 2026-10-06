part of '../helix_remote_ui.dart';

/// The reply/edit banner above the text field.
class HelixComposerBanner extends StatelessWidget {
  const HelixComposerBanner({super.key, required this.model, this.onClose});

  final HelixComposerBannerModel model;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = model.text.isEmpty
        ? helixPreviewLabel(model.previewKind)
        : model.text;
    final icon = helixPreviewIcon(model.previewKind);
    final editing = model.kind == HelixComposerBannerKind.edit;
    return Semantics(
      container: true,
      label: '${model.title}. $label',
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: HelixSpace.sm,
            top: HelixSpace.xs,
            bottom: HelixSpace.xs,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
                const SizedBox(width: HelixSpace.xs),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        Row(
                          children: [
                            if (icon != null)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 4,
                                ),
                                child: Icon(
                                  icon,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (model.thumbnail != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: HelixSpace.xs,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(
                          120,
                          null,
                          model.thumbnail!,
                        ),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) =>
                            const SizedBox.square(dimension: 40),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: editing ? 'Cancel edit' : 'Cancel reply',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list of people offered while typing `@`, shown above the composer.
/// Scrolls after four rows.
class HelixMentionSuggestions extends StatelessWidget {
  const HelixMentionSuggestions({
    super.key,
    required this.candidates,
    required this.onSelected,
  });

  /// Row height; also the `itemExtent`.
  static const rowHeight = 56.0;
  static const maxRows = 4;

  final List<HelixMentionCandidate> candidates;
  final ValueChanged<HelixMentionCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final row = math.max(rowHeight, scaler.scale(rowHeight * .8));
    final rows = math.min(candidates.length, maxRows);
    return Semantics(
      label: 'Mention suggestions',
      container: true,
      child: Material(
        color: scheme.surfaceContainerLow,
        elevation: HelixElevation.card,
        child: SizedBox(
          height: row * rows,
          child: ListView.builder(
            itemCount: candidates.length,
            itemExtent: row,
            itemBuilder: (context, index) {
              final c = candidates[index];
              return Semantics(
                button: true,
                label: 'Mention ${c.name}',
                onTap: () => onSelected(c),
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => onSelected(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HelixSpace.md,
                      ),
                      child: Row(
                        children: [
                          HelixAvatar(
                            model: c.avatar,
                            size: HelixAvatarSize.sm,
                          ),
                          const SizedBox(width: HelixSpace.sm),
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (c.detail != null)
                            Text(
                              c.detail!,
                              maxLines: 1,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Hold-to-record microphone button. Reports the gesture; the app owns the
/// recorder and feeds the result back as a [HelixVoiceRecordState].
///
/// Slide towards the start edge to cancel, up to lock. The button never
/// records by itself.
class HelixMicButton extends StatefulWidget {
  const HelixMicButton({
    super.key,
    this.onTap,
    this.onStart,
    this.onSlide,
    this.onLock,
    this.onCancel,
    this.onEnd,
    this.cancelDistance = 120,
    this.lockDistance = 80,
  });

  /// A plain tap: the app should hint "Hold to record".
  final VoidCallback? onTap;

  /// Finger down long enough: start recording.
  final VoidCallback? onStart;

  /// (cancelProgress, lockProgress), each 0..1, while the finger moves.
  final void Function(double cancel, double lock)? onSlide;

  /// Slid up far enough: keep recording hands-free.
  final VoidCallback? onLock;

  /// Slid towards the start far enough: discard.
  final VoidCallback? onCancel;

  /// Released in place: stop and send.
  final VoidCallback? onEnd;
  final double cancelDistance;
  final double lockDistance;

  @override
  State<HelixMicButton> createState() => _HelixMicButtonState();
}

class _HelixMicButtonState extends State<HelixMicButton> {
  Offset _origin = Offset.zero;
  bool _settled = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: 'Record voice message',
      hint: 'Press and hold to record',
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: (d) {
            _origin = d.globalPosition;
            _settled = false;
            widget.onStart?.call();
          },
          onLongPressMoveUpdate: (d) {
            if (_settled) return;
            final delta = d.globalPosition - _origin;
            final towardsStart = rtl ? delta.dx : -delta.dx;
            final cancel = (towardsStart / widget.cancelDistance).clamp(
              0.0,
              1.0,
            );
            final lock = (-delta.dy / widget.lockDistance).clamp(0.0, 1.0);
            widget.onSlide?.call(cancel, lock);
            if (cancel >= 1) {
              _settled = true;
              widget.onCancel?.call();
            } else if (lock >= 1) {
              _settled = true;
              widget.onLock?.call();
            }
          },
          onLongPressEnd: (_) {
            if (!_settled) widget.onEnd?.call();
            _settled = false;
          },
          onLongPressCancel: () {
            if (!_settled) widget.onCancel?.call();
            _settled = false;
          },
          child: SizedBox.square(
            dimension: HelixChatMetrics.minTarget,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// What replaces the text field while recording: a red dot and the timer
/// with "Slide to cancel", or - once locked - delete / timer / send.
class HelixVoiceRecordBar extends StatelessWidget {
  const HelixVoiceRecordBar({
    super.key,
    required this.state,
    this.onCancel,
    this.onSend,
  });

  final HelixVoiceRecordState state;

  /// Delete the recording (locked mode only).
  final VoidCallback? onCancel;

  /// Send the recording (locked mode only).
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slideOpacity = (1 - state.cancelProgress).clamp(0.0, 1.0);
    return Semantics(
      liveRegion: true,
      label: state.locked
          ? 'Recording locked, ${state.elapsedLabel}'
          : 'Recording, ${state.elapsedLabel}. Slide to cancel',
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HelixChatMetrics.minTarget,
          ),
          child: Row(
            children: [
              if (state.locked)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: 'Delete recording',
                  onPressed: onCancel,
                )
              else
                const SizedBox(width: HelixSpace.md),
              ExcludeSemantics(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: HelixCallColors.endCall,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: HelixSpace.xs),
              ExcludeSemantics(
                child: Text(
                  state.elapsedLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const Spacer(),
              if (!state.locked)
                Flexible(
                  flex: 3,
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: slideOpacity,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: HelixSpace.md + state.cancelProgress * 40,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chevron_left,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            Flexible(
                              child: Text(
                                'Slide to cancel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: 'Send recording',
                  onPressed: onSend,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small lock column that rises above the mic while the finger is down.
class HelixVoiceLockHint extends StatelessWidget {
  const HelixVoiceLockHint({super.key, required this.progress});

  /// 0 = hint, 1 = locked.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 12 - 6 * progress, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                progress >= 1 ? Icons.lock : Icons.lock_open,
                size: 20,
                color: scheme.onSurface,
              ),
              Icon(
                Icons.keyboard_arrow_up,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The message composer: grows with the text up to [maxLines], then scrolls.
///
/// Stateless: the text lives in [controller], recording state comes in as
/// [recording], and every action is a callback. The right-hand button is
/// "send" when there is text (or [editing]) and the microphone otherwise.
class HelixComposer extends StatelessWidget {
  const HelixComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.hint = 'Message',
    this.banner,
    this.onBannerClose,
    this.editing = false,
    this.onEmoji,
    this.onAttach,
    this.onCamera,
    this.onChanged,
    this.mentionCandidates = const [],
    this.onMentionSelected,
    this.recording,
    this.mic = const HelixMicButton(),
    this.onRecordingCancel,
    this.onRecordingSend,
    this.disabledMessage,
    this.maxLines = 6,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final String hint;
  final HelixComposerBannerModel? banner;
  final VoidCallback? onBannerClose;

  /// The banner is an edit: the send button saves and shows a check.
  final bool editing;
  final VoidCallback? onEmoji;
  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final ValueChanged<String>? onChanged;
  final List<HelixMentionCandidate> mentionCandidates;
  final ValueChanged<HelixMentionCandidate>? onMentionSelected;

  /// Non-null while a voice message is being recorded.
  final HelixVoiceRecordState? recording;

  /// The microphone; pass a [HelixMicButton] with the app's callbacks.
  final Widget mic;
  final VoidCallback? onRecordingCancel;
  final VoidCallback? onRecordingSend;

  /// When set, the composer is replaced by this notice ("You blocked this
  /// contact").
  final String? disabledMessage;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (disabledMessage != null) {
      return ColoredBox(
        color: scheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Center(
              child: Text(
                disabledMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      );
    }
    final rec = recording;
    return ColoredBox(
      color: HelixChatColors.page,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mentionCandidates.isNotEmpty && onMentionSelected != null)
              HelixMentionSuggestions(
                candidates: mentionCandidates,
                onSelected: onMentionSelected!,
              ),
            if (banner != null && rec == null)
              HelixComposerBanner(model: banner!, onClose: onBannerClose),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: rec != null
                        ? HelixVoiceRecordBar(
                            state: rec,
                            onCancel: onRecordingCancel,
                            onSend: onRecordingSend,
                          )
                        : _TextBar(
                            controller: controller,
                            focusNode: focusNode,
                            hint: hint,
                            maxLines: maxLines,
                            onChanged: onChanged,
                            onEmoji: onEmoji,
                            onAttach: onAttach,
                            onCamera: onCamera,
                          ),
                  ),
                  if (rec == null || !rec.locked) ...[
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        final hasText = value.text.trim().isNotEmpty;
                        if (hasText || editing) {
                          return IconButton.filled(
                            icon: Icon(editing ? Icons.check : Icons.send),
                            tooltip: editing ? 'Save edit' : 'Send',
                            onPressed: hasText ? onSend : null,
                          );
                        }
                        // One shape for both states: the microphone keeps its
                        // place in the tree when recording starts, so the
                        // finger that is holding it is still its gesture.
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            mic,
                            if (rec != null)
                              PositionedDirectional(
                                bottom: HelixChatMetrics.minTarget + 8,
                                start: 0,
                                end: 0,
                                child: Center(
                                  child: HelixVoiceLockHint(
                                    progress: rec.lockProgress,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextBar extends StatelessWidget {
  const _TextBar({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.maxLines,
    this.onChanged,
    this.onEmoji,
    this.onAttach,
    this.onCamera,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEmoji;
  final VoidCallback? onAttach;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined),
            tooltip: 'Emoji',
            onPressed: onEmoji,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: maxLines,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                color: scheme.onSurface,
              ),
              // The padding is inside the field so the whole 48 px row is
              // the tap target, not just the line of text.
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach',
            onPressed: onAttach,
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? IconButton(
                    icon: const Icon(Icons.photo_camera_outlined),
                    tooltip: 'Camera',
                    onPressed: onCamera,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// One tile in the attachment sheet.
class HelixAttachmentOption {
  const HelixAttachmentOption({
    required this.id,
    required this.label,
    required this.icon,
    this.colorIndex = 0,
  });
  final String id;
  final String label;
  final IconData icon;

  /// Index into the avatar palette for the circle behind the glyph.
  final int colorIndex;
}

/// The options offered by [showHelixAttachmentSheet] by default: the content
/// types a chat can send.
const helixDefaultAttachmentOptions = <HelixAttachmentOption>[
  HelixAttachmentOption(
    id: 'document',
    label: 'Document',
    icon: Icons.insert_drive_file,
    colorIndex: 2,
  ),
  HelixAttachmentOption(
    id: 'camera',
    label: 'Camera',
    icon: Icons.photo_camera,
    colorIndex: 0,
  ),
  HelixAttachmentOption(
    id: 'gallery',
    label: 'Gallery',
    icon: Icons.photo_library,
    colorIndex: 1,
  ),
  HelixAttachmentOption(
    id: 'audio',
    label: 'Audio',
    icon: Icons.headphones,
    colorIndex: 6,
  ),
  HelixAttachmentOption(
    id: 'location',
    label: 'Location',
    icon: Icons.location_on,
    colorIndex: 5,
  ),
  HelixAttachmentOption(
    id: 'contact',
    label: 'Contact',
    icon: Icons.person,
    colorIndex: 3,
  ),
  HelixAttachmentOption(
    id: 'poll',
    label: 'Poll',
    icon: Icons.poll,
    colorIndex: 4,
  ),
];

/// The grid of attachment choices.
class HelixAttachmentSheet extends StatelessWidget {
  const HelixAttachmentSheet({
    super.key,
    required this.onSelected,
    this.options = helixDefaultAttachmentOptions,
  });

  final ValueChanged<String> onSelected;
  final List<HelixAttachmentOption> options;

  @override
  Widget build(BuildContext context) {
    final palette = HelixColorTokens.avatarPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: HelixSpace.md,
        runSpacing: HelixSpace.md,
        children: [
          for (final option in options)
            SizedBox(
              width: 88,
              child: Semantics(
                button: true,
                label: option.label,
                onTap: () => onSelected(option.id),
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    onTap: () => onSelected(option.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color:
                                  palette[option.colorIndex.abs() %
                                      palette.length],
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(
                              dimension: 56,
                              child: Icon(
                                option.icon,
                                color: HelixScrimColors.onBackdrop,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows [HelixAttachmentSheet]; returns the chosen option id or null.
Future<String?> showHelixAttachmentSheet(
  BuildContext context, {
  List<HelixAttachmentOption> options = helixDefaultAttachmentOptions,
}) => showHelixBottomSheet<String>(
  context,
  builder: (sheetContext) => HelixAttachmentSheet(
    options: options,
    onSelected: (id) => Navigator.pop(sheetContext, id),
  ),
);
