import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/timeline_builder.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What a tap, long press or swipe on a bubble does. The conversation screen
/// implements it; rows receive it so they stay free of navigation and
/// provider calls, and so a row can be compared by value.
abstract interface class ConversationUi {
  void showMenu(int rowid);
  void toggleSelect(int rowid);
  void reply(int rowid);
  void jumpToMessage(String messageId);
  void showReactions(int rowid);
  void retry(int rowid);
  void openLink(String url);
  void openViewOnce(int rowid);

  /// A tap on item [index] of a media or document bubble.
  void tapMedia(int rowid, int index, List<MediaPart> parts);

  /// Play or pause the audio of a bubble.
  void toggleAudio(int rowid, List<MediaPart> parts);
}

/// How many rows were built (a test hook): a burst of messages must rebuild
/// the rows that changed, not every row on screen.
@visibleForTesting
int timelineRowBuilds = 0;

/// One row of the timeline: a bubble, a separator, a notice or the unread
/// divider.
///
/// The timeline view keeps the row widget it built for an entry while the
/// entry, the selection and the highlight stay equal, and hands the *same*
/// widget back; Flutter does not rebuild an element whose widget is
/// identical, which is what keeps a thousand-message burst cheap.
class TimelineRowView extends ConsumerWidget {
  const TimelineRowView({
    super.key,
    required this.entry,
    required this.ui,
    this.selected = false,
    this.selectionMode = false,
    this.highlighted = false,
  });

  final TimelineEntry entry;
  final ConversationUi ui;
  final bool selected;
  final bool selectionMode;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    timelineRowBuilds++;
    final item = entry.item;
    if (item is! HelixMessageItem) return HelixTimelineRow(item: item);
    final rowid = entry.messageRowid!;
    var message = item.message;
    if (highlighted) message = message.copyWith(highlighted: true);
    if (entry.hasMedia) {
      return _MediaBubble(
        entry: entry,
        message: message,
        position: item.position,
        ui: ui,
        selected: selected,
        selectionMode: selectionMode,
      );
    }
    return HelixMessageBubble(
      message: message,
      position: item.position,
      selected: selected,
      actions: _actions(entry, ui, selectionMode, rowid),
    );
  }
}

HelixBubbleActions _actions(
  TimelineEntry entry,
  ConversationUi ui,
  bool selectionMode,
  int rowid, {
  ValueChanged<int>? onMediaTap,
  VoidCallback? onAudioToggle,
  VoidCallback? onAudioSpeed,
  ValueChanged<double>? onAudioSeek,
}) {
  final replyTo = entry.replyToId;
  return HelixBubbleActions(
    onTap: selectionMode ? () => ui.toggleSelect(rowid) : null,
    onLongPress: () =>
        selectionMode ? ui.toggleSelect(rowid) : ui.showMenu(rowid),
    onReply: selectionMode ? null : () => ui.reply(rowid),
    onQuoteTap: replyTo == null ? null : () => ui.jumpToMessage(replyTo),
    onReactionsTap: () => ui.showReactions(rowid),
    onRetry: () => ui.retry(rowid),
    onLinkTap: ui.openLink,
    onViewOnceTap: () => ui.openViewOnce(rowid),
    onMediaTap: selectionMode ? null : onMediaTap,
    onTransferTap: selectionMode ? null : onMediaTap,
    onAudioToggle: onAudioToggle,
    onAudioSpeed: onAudioSpeed,
    onAudioSeek: onAudioSeek,
  );
}

/// A media, voice or document bubble: its content comes from the message's
/// attachments (and, for audio, the player), watched here so only this row
/// rebuilds when a transfer moves or playback advances.
class _MediaBubble extends ConsumerWidget {
  const _MediaBubble({
    required this.entry,
    required this.message,
    required this.position,
    required this.ui,
    required this.selected,
    required this.selectionMode,
  });

  final TimelineEntry entry;
  final HelixMessage message;
  final HelixRunPosition position;
  final ConversationUi ui;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowid = entry.messageRowid!;
    final parts = ref.watch(messageMediaProvider(rowid)).value;
    final placeholder = message.content;
    final caption = placeholder is HelixMediaContent ? placeholder.caption : '';
    final isAudio =
        parts != null &&
        parts.isNotEmpty &&
        (parts.first.row.kind == 'voice_note' ||
            parts.first.row.mime.startsWith('audio/'));
    // Only the bubble that is playing listens to the player.
    final playback = isAudio
        ? ref.watch(
            playbackProvider.select(
              (s) => s.messageRowid == rowid
                  ? s
                  : PlaybackState(
                      speed: s.speed,
                      played: s.played.contains(rowid) ? {rowid} : const {},
                    ),
            ),
          )
        : null;
    final content = parts == null
        ? placeholder
        : mediaContentOf(
            rowid: rowid,
            caption: caption,
            parts: parts,
            playback: playback,
          );
    final list = parts ?? const <MediaPart>[];
    return HelixMessageBubble(
      message: message.copyWith(content: content),
      position: position,
      selected: selected,
      actions: _actions(
        entry,
        ui,
        selectionMode,
        rowid,
        onMediaTap: (index) => ui.tapMedia(rowid, index, list),
        onAudioToggle: () => ui.toggleAudio(rowid, list),
        onAudioSpeed: () => ref.read(playbackProvider.notifier).cycleSpeed(),
        onAudioSeek: (fraction) =>
            ref.read(playbackProvider.notifier).seek(rowid, fraction),
      ),
    );
  }
}
