import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote/features/conversation/application/conversation_calls.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/application/conversation_links.dart';
import 'package:helix_remote/features/conversation/application/conversation_search.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote/features/conversation/application/message_actions.dart';
import 'package:helix_remote/features/conversation/application/message_info.dart';
import 'package:helix_remote/features/conversation/application/read_tracker.dart';
import 'package:helix_remote/features/conversation/application/timeline_builder.dart';
import 'package:helix_remote/features/conversation/application/timeline_provider.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/pending_members.dart';
import 'package:orbit_ui/orbit_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A group conversation's id is `group:<group id>`.
const _groupPrefix = 'group:';

/// Connector: one conversation, drawn by `orbit_ui`'s [ChatScreen] from the
/// app's providers (`contracts/conversation.md`).
///
/// [messageId] opens it at that message (a search hit, "Show in chat"). The
/// connector follows the app's lifecycle (read receipts only in the
/// foreground; a held recording is dropped in the background), watches the
/// attachments of the media rows the list has drawn, and turns the screen's
/// actions into the existing notifiers and routes.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    this.messageId,
  });

  final String conversationId;
  final String? messageId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  // Kept in fields: `ref` cannot be used once the screen is going away.
  late final PlaybackNotifier _playback;
  late final ComposerNotifier _composer;
  TimelineArgs? _args;
  TimelineSnapshot? _snapshot;

  /// Every row of the window by item id, for the screen's actions.
  Map<String, TimelineEntry> _entries = const {};

  /// Media rows the list has drawn: their attachments are watched.
  final Set<int> _mediaRows = {};

  /// The last jump, kept after its highlight fades so the screen can still
  /// bring it into view once its window has loaded.
  TimelineJump? _jump;

  String get _id => widget.conversationId;
  String? get _groupId =>
      _id.startsWith(_groupPrefix) ? _id.substring(_groupPrefix.length) : null;

  ConversationActions get _actions =>
      ref.read(conversationActionsProvider(_id));

  /// Watched by [build] from the first frame, so it lives as long as the
  /// screen.
  ReadTracker get _tracker => ref.read(readTrackerProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback = ref.read(playbackProvider.notifier);
    _composer = ref.read(composerProvider(_id).notifier);
    final target = widget.messageId;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(timelineJumpProvider(_id).notifier).to(target);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Read receipts wait for the foreground; a recording cannot continue
  /// behind the app (a held one is dropped, a locked one waits).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _tracker.setForeground(state == AppLifecycleState.resumed);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_composer.appBackgrounded());
      case AppLifecycleState.resumed:
        unawaited(_composer.appResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // ------------------------------------------------------------- helpers

  int? _rowid(String id) => _entries[id]?.messageRowid ?? int.tryParse(id);

  void _say(String? text) {
    if (text != null && text.isNotEmpty && mounted) {
      showOrbitToast(context, text);
    }
  }

  List<MediaPart> _partsOf(int rowid) =>
      ref.read(messageMediaProvider(rowid)).value ?? const <MediaPart>[];

  static ChatMessageAction? _actionOf(String id) => switch (id) {
    MessageActionIds.reply => ChatMessageAction.reply,
    MessageActionIds.copy => ChatMessageAction.copy,
    MessageActionIds.forward => ChatMessageAction.forward,
    MessageActionIds.edit => ChatMessageAction.edit,
    MessageActionIds.info => ChatMessageAction.info,
    MessageActionIds.select => ChatMessageAction.select,
    MessageActionIds.deleteForMe => ChatMessageAction.deleteForMe,
    MessageActionIds.deleteForEveryone => ChatMessageAction.deleteForEveryone,
    _ => null,
  };

  static AttachmentSource _sourceOf(ChatAttachSource s) => switch (s) {
    ChatAttachSource.gallery => AttachmentSource.gallery,
    ChatAttachSource.document => AttachmentSource.document,
    ChatAttachSource.audio => AttachmentSource.audio,
    ChatAttachSource.cameraPhoto => AttachmentSource.cameraPhoto,
    ChatAttachSource.cameraVideo => AttachmentSource.cameraVideo,
  };

  static HelixPersonItem _personOf(HelixMentionCandidate c) => HelixPersonItem(
    id: c.id,
    names: HelixPersonNames(phoneBookName: c.name, number: c.detail),
    image: c.image,
  );

  // ------------------------------------------------------------- actions

  Future<String?> _call({required bool video}) async {
    final peer = ref.read(conversationHeaderProvider(_id))?.peerAccount;
    if (peer == null) return null;
    final calls = ref.read(conversationCallsProvider);
    if (!calls.isAvailable) return 'Calls are not available on this device.';
    return calls.start(peer, video: video);
  }

  Future<ChatMessageMenu?> _menu(String id) async {
    final rowid = _rowid(id);
    if (rowid == null) return null;
    final menu = await _actions.menuFor(rowid);
    if (menu == null) return null;
    return ChatMessageMenu(
      actions: {for (final id in menu.actions) ?_actionOf(id)},
      allowReactions: menu.allowReactions,
      currentReaction: menu.currentReaction,
    );
  }

  Future<List<ChatReactionLine>> _reactions(String id) async {
    final rowid = _rowid(id);
    if (rowid == null) return const [];
    // Listened, not read: the provider is auto-disposed, and must stay up
    // until its answer arrives.
    final sub = ref.listenManual(
      reactionDetailsProvider(rowid).future,
      (_, _) {},
    );
    final List<ReactionLine> lines;
    try {
      lines = await sub.read();
    } finally {
      sub.close();
    }
    return [
      for (final l in lines)
        ChatReactionLine(
          emoji: l.emoji,
          name: l.name,
          avatar: l.avatar,
          mine: l.mine,
        ),
    ];
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _tapMedia(String id, int index) async {
    final rowid = _rowid(id);
    if (rowid == null) return;
    final parts = _partsOf(rowid);
    if (index < 0 || index >= parts.length) return;
    final part = parts[index];
    final media = ref.read(mediaActionsProvider);
    final result = await media.tap(part, messageRowid: rowid);
    if (result != MediaTap.open || !mounted) return;
    if (part.isVisual) {
      await context.push(mediaLocation(_id, rowid, index: index));
    } else {
      await media.share(part);
    }
  }

  Future<void> _toggleAudio(String id) async {
    final rowid = _rowid(id);
    if (rowid == null) return;
    final parts = _partsOf(rowid);
    if (parts.isEmpty) return;
    final part = parts.first;
    if (!part.ready) {
      await ref.read(mediaActionsProvider).tap(part, messageRowid: rowid);
      return;
    }
    await _playback.toggle(rowid, part.id);
  }

  void _quote(String id) {
    final replyTo = _entries[id]?.replyToId;
    if (replyTo != null) {
      ref.read(timelineJumpProvider(_id).notifier).to(replyTo);
    }
  }

  void _rowsShown(List<String> ids) {
    final rowids = <int>[];
    var media = false;
    for (final id in ids) {
      final entry = _entries[id];
      final rowid = entry?.messageRowid;
      if (rowid == null) continue;
      rowids.add(rowid);
      if (entry!.hasMedia && _mediaRows.add(rowid)) media = true;
    }
    if (rowids.isNotEmpty) unawaited(_tracker.displayed(rowids));
    if (media && mounted) setState(() {});
  }

  Future<void> _pickFiles(ChatAttachSource source) async {
    final files = await _composer.pick(_sourceOf(source));
    if (files.isEmpty || !mounted) return;
    ref.read(pendingAttachmentsProvider(_id).notifier).set(files);
    await context.push(sendFilesLocation(_id));
  }

  ({String text, int cursor}) _pickMention(
    HelixPersonItem person,
    String text,
    int cursor,
  ) {
    final candidates = ref.read(composerProvider(_id)).mentionCandidates;
    final candidate = candidates.where((c) => c.id == person.id).firstOrNull;
    if (candidate == null) return (text: text, cursor: cursor);
    return _composer.pickMention(candidate, text, cursor);
  }

  // --------------------------------------------------------------- build

  /// The window as the screen draws it, oldest first: media rows carry
  /// their attachments (and the player, for audio), the jump's message its
  /// highlight.
  List<HelixTimelineItem> _items(
    TimelineSnapshot snapshot,
    TimelineJump? highlight,
    PlaybackState playback,
  ) {
    final out = <HelixTimelineItem>[];
    for (var i = snapshot.newestFirst.length - 1; i >= 0; i--) {
      final entry = snapshot.newestFirst[i];
      final item = entry.item;
      if (item is! HelixMessageItem) {
        out.add(item);
        continue;
      }
      var message = item.message;
      final rowid = entry.messageRowid;
      if (entry.hasMedia && rowid != null && _mediaRows.contains(rowid)) {
        final parts = ref.watch(messageMediaProvider(rowid)).value;
        if (parts != null) {
          final placeholder = message.content;
          final caption = placeholder is HelixMediaContent
              ? placeholder.caption
              : '';
          final audio =
              parts.isNotEmpty &&
              (parts.first.row.kind == 'voice_note' ||
                  parts.first.row.mime.startsWith('audio/'));
          message = message.copyWith(
            content: mediaContentOf(
              rowid: rowid,
              caption: caption,
              parts: parts,
              playback: !audio
                  ? null
                  : playback.messageRowid == rowid
                  ? playback
                  : PlaybackState(
                      speed: playback.speed,
                      played: playback.played.contains(rowid)
                          ? {rowid}
                          : const {},
                    ),
            ),
          );
        }
      }
      if (highlight != null && entry.messageId == highlight.messageId) {
        message = message.copyWith(highlighted: true);
      }
      out.add(
        identical(message, item.message)
            ? item
            : HelixMessageItem(message, position: item.position),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readTrackerProvider(_id));
    final open = ref.watch(conversationOpenProvider(_id));
    final header = ref.watch(conversationHeaderProvider(_id));
    final composer = ref.watch(composerProvider(_id));
    final draft = ref.watch(composerDraftProvider(_id)).value ?? '';
    final enterSends = ref.watch(enterSendsProvider).value ?? false;
    final typing =
        ref.watch(conversationTypingProvider(_id)).value?.isNotEmpty ?? false;
    final unread = ref.watch(conversationRowProvider(_id)).value?.unreadCount;
    final group = _groupId;
    final pending = group == null
        ? const <PendingMemberItem>[]
        : ref.watch(pendingMemberItemsProvider(group));
    final query = ref.watch(inChatSearchQueryProvider(_id)).trim();
    final results = query.isEmpty
        ? null
        : ref.watch(inChatSearchResultsProvider(_id));

    ref.listen(composerProvider(_id).select((s) => s.noticeSerial), (_, _) {
      _say(ref.read(composerProvider(_id)).notice);
    });
    ref.listen(playbackProvider.select((s) => s.noticeSerial), (_, _) {
      _say(ref.read(playbackProvider).notice);
    });

    var load = ChatLoadState.loading;
    var items = const <HelixTimelineItem>[];
    var hasOlder = false;
    var hasNewer = false;
    ({String id, int serial})? focus;
    final info = open.value;
    if (info == null) {
      if (open.hasError) load = ChatLoadState.openFailed;
    } else {
      final args = _args ??= TimelineArgs(
        _id,
        initialLimit: initialLimitFor(info),
        anchorMessageId: widget.messageId,
      );
      // Watched here, not only through the timeline (whose stream reaches it
      // after its first awaits), so the window notifier the actions use is
      // the one that stays.
      ref.watch(timelineWindowProvider(args));
      final timeline = ref.watch(timelineProvider(args));
      ref.listen(timelineProvider(args), (_, next) {
        if (next.value != null) _tracker.messagesChanged();
      });
      ref.listen(timelineJumpProvider(_id), (_, next) {
        if (next == null) return;
        _jump = next;
        final snapshot = _snapshot;
        if (snapshot == null ||
            snapshot.indexOfMessage(next.messageId) == null) {
          // Not in the window yet: this opens a window around it, and the
          // next snapshot carries it.
          unawaited(
            ref
                .read(timelineWindowProvider(args).notifier)
                .jumpTo(next.messageId),
          );
        }
      });
      final highlight = ref.watch(timelineJumpProvider(_id));
      // A jump asked for before the window existed (opened at a message).
      if (highlight != null) _jump = highlight;
      final playback = ref.watch(playbackProvider);
      final snapshot = timeline.value;
      if (snapshot == null) {
        if (timeline.hasError) load = ChatLoadState.loadFailed;
      } else {
        if (_snapshot == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tracker.messagesChanged(),
          );
        }
        _snapshot = snapshot;
        load = ChatLoadState.ready;
        _entries = {for (final e in snapshot.newestFirst) e.item.id: e};
        items = _items(snapshot, highlight, playback);
        hasOlder = snapshot.hasOlder;
        hasNewer = snapshot.hasNewer;
        final jump = _jump;
        final index = jump == null
            ? null
            : snapshot.indexOfMessage(jump.messageId);
        if (jump != null && index != null) {
          focus = (
            id: snapshot.newestFirst[index].item.id,
            serial: jump.serial,
          );
        }
      }
    }

    final hits = results?.value;
    final model = ChatModel(
      conversationId: _id,
      title: header?.title ?? '',
      avatar: header?.avatar ?? const HelixAvatarModel(name: ''),
      loadState: load,
      subtitle: header?.subtitle,
      subtitleIsTyping: header?.typing ?? false,
      verified: header?.verified ?? false,
      isGroup: header?.isGroup ?? group != null,
      showCallButtons: header?.canCall ?? false,
      hasInfoPage: infoLocationOf(_id) != null,
      pendingMembers: pending,
      items: items,
      hasOlder: hasOlder,
      hasNewer: hasNewer,
      unreadCount: unread ?? 0,
      openAtUnread: true,
      focus: focus,
      someoneTyping: typing,
      composerDisabledReason: header?.composerDisabledReason,
      disabledIsBlock:
          (header?.blocked ?? false) || (header?.blockedByPeer ?? false),
      initialDraft: draft,
      banner: composerBannerOf(composer),
      mentionCandidates: [
        for (final c in composer.mentionCandidates) _personOf(c),
      ],
      recording: switch (composer.recording) {
        null => OrbitRecording.none,
        final r when r.locked => OrbitRecording.locked,
        _ => OrbitRecording.hold,
      },
      recordingTime: composer.recording?.elapsedLabel ?? '0:00',
      recordingWave: composer.recordingLevels,
      enterSends: enterSends,
      searchHits: query.isEmpty
          ? const []
          : [
              for (final h in hits ?? const <InChatHit>[])
                ChatSearchHit(
                  chatId: _id,
                  messageId: h.messageId,
                  title: header?.title ?? '',
                  avatar: h.result.avatar,
                  timeLabel: h.result.timeLabel,
                  who: h.result.senderLabel ?? h.result.chatTitle,
                  text: h.result.snippet,
                ),
            ],
      searchStatus: results == null || hits != null
          ? ListStatus.ready
          : results.hasError
          ? ListStatus.failed
          : ListStatus.loading,
    );

    final window = _args == null
        ? null
        : ref.read(timelineWindowProvider(_args!).notifier);
    final info0 = infoLocationOf(_id);
    final members = ref.read(pendingMemberActionsProvider);
    return ChatScreen(
      model: model,
      actions: ChatActions(
        onOpenInfo: info0 == null ? null : () => context.push(info0),
        onOpenSharedMedia: () => context.push(sharedMediaLocation(_id)),
        onOpenSettings: () => context.push(chatSettingsLocation(_id)),
        onCall: _call,
        messageMenu: _menu,
        onReact: (id, emoji) {
          final rowid = _rowid(id);
          if (rowid != null) unawaited(_actions.react(rowid, emoji));
        },
        reactionsOf: _reactions,
        onRemoveMyReaction: (id) async {
          final rowid = _rowid(id);
          if (rowid != null) await _actions.removeMyReaction(rowid);
        },
        onReply: (id) async {
          final rowid = _rowid(id);
          if (rowid != null) await _composer.reply(rowid);
        },
        onEdit: (id) async {
          final rowid = _rowid(id);
          return rowid == null ? null : _composer.beginEdit(rowid);
        },
        onCopy: (ids) => _actions.copy([...ids.map(_rowid).nonNulls]),
        onForward: (ids) =>
            context.push(forwardLocation(_id, [...ids.map(_rowid).nonNulls])),
        onMessageInfo: (id) {
          final rowid = _rowid(id);
          if (rowid != null) context.push(infoLocation(_id, rowid));
        },
        onDeleteForMe: (ids) =>
            _actions.deleteForMe([...ids.map(_rowid).nonNulls]),
        onDeleteForEveryone: (id) async {
          final rowid = _rowid(id);
          return rowid != null && await _actions.deleteForEveryone(rowid);
        },
        onRetry: (id) {
          final rowid = _rowid(id);
          if (rowid != null) unawaited(_actions.retry(rowid));
        },
        onRetryAction: (id) {
          final rowid = _rowid(id);
          if (rowid != null) unawaited(_actions.retryActions(rowid));
        },
        onRetryLoad: () {
          // Opening failed: open it again; loading failed: load it again.
          final args = _args;
          if (args == null) {
            ref.invalidate(conversationOpenProvider(_id));
          } else {
            ref.invalidate(timelineProvider(args));
          }
        },
        onConfirmMember: group == null
            ? null
            : (account) => members.confirm(group, account),
        onRemoveMember: group == null
            ? null
            : (account) => members.remove(group, account),
        onQuote: _quote,
        onOpenLink: _openLink,
        onTapMedia: _tapMedia,
        onOpenViewOnce: (id) {
          final rowid = _rowid(id);
          if (rowid != null) context.push(mediaLocation(_id, rowid));
        },
        onToggleAudio: _toggleAudio,
        onAudioSpeed: (_) => _playback.cycleSpeed(),
        onAudioSeek: (id, fraction) {
          final rowid = _rowid(id);
          if (rowid != null) unawaited(_playback.seek(rowid, fraction));
        },
        onLoadOlder: window == null ? null : () => window.loadOlder(),
        onLoadNewer: window?.loadNewer,
        onScrollToLatest: window?.jumpToLatest,
        onAtBottomChanged: (atBottom) => _tracker.setAtBottom(atBottom),
        onRowsShown: _rowsShown,
        onJumpTo: (messageId) =>
            ref.read(timelineJumpProvider(_id).notifier).to(messageId),
        onSearchQuery: (value) =>
            ref.read(inChatSearchQueryProvider(_id).notifier).set(value),
        onSend: _composer.send,
        onTextChanged: _composer.onChanged,
        onPickMention: _pickMention,
        onCancelBanner: _composer.cancelTarget,
        onPickFiles: _pickFiles,
        onVoiceStart: _composer.startVoice,
        onVoiceSlide: _composer.slideVoice,
        onVoiceLock: _composer.lockVoice,
        onVoiceEnd: ({required send}) => _composer.endVoice(send: send),
        onLeave: (text) {
          // The draft is saved even when the person leaves mid-word; a
          // voice note stops with the screen.
          unawaited(_composer.flushDraft(text));
          unawaited(_playback.stop());
        },
      ),
    );
  }
}
