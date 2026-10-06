import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote/features/conversation/application/conversation_links.dart';
import 'package:helix_remote/features/conversation/application/conversation_search.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote/features/conversation/application/message_actions.dart';
import 'package:helix_remote/features/conversation/application/message_info.dart';
import 'package:helix_remote/features/conversation/application/read_tracker.dart';
import 'package:helix_remote/features/conversation/application/timeline_provider.dart';
import 'package:helix_remote/features/conversation/presentation/composer_bar.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_app_bar.dart';
import 'package:helix_remote/features/conversation/presentation/emoji_panel.dart';
import 'package:helix_remote/features/conversation/presentation/in_chat_search_view.dart';
import 'package:helix_remote/features/conversation/presentation/timeline_row.dart';
import 'package:helix_remote/features/conversation/presentation/timeline_view.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/widgets/pending_members_prompt.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A group conversation's id is `group:<group id>`.
const _groupPrefix = 'group:';

/// One conversation: the app bar, the messages and the composer.
///
/// [messageId] opens it at that message (a search hit, a quote). The screen
/// implements [ConversationUi], the one place bubbles' taps and long presses
/// are turned into navigation and engine calls.
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
    with WidgetsBindingObserver
    implements ConversationUi {
  final GlobalKey<ComposerBarState> _composerKey = GlobalKey();
  final TextEditingController _search = TextEditingController();
  late final PlaybackNotifier _playback;
  TimelineArgs? _args;
  bool _searching = false;

  String get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback = ref.read(playbackProvider.notifier);
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
    _playback.stop();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(readTrackerProvider(_id).notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  // ------------------------------------------------------- ConversationUi

  ConversationActions get _actions =>
      ref.read(conversationActionsProvider(_id));

  @override
  void toggleSelect(int rowid) =>
      ref.read(messageSelectionProvider(_id).notifier).toggle(rowid);

  @override
  Future<void> showMenu(int rowid) async {
    final menu = await _actions.menuFor(rowid);
    if (menu == null || !mounted) return;
    final choice = await showHelixMessageActionMenu(
      context,
      actions: menu.actions,
      allowReactions: menu.allowReactions,
      currentReaction: menu.currentReaction,
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('react:')) {
      var emoji = choice.substring('react:'.length);
      if (emoji == 'more') {
        final picked = await showEmojiSheet(context);
        if (picked == null) return;
        emoji = picked;
      }
      await _actions.react(rowid, emoji);
      return;
    }
    switch (choice) {
      case HelixMessageActionIds.reply:
        await reply(rowid);
      case HelixMessageActionIds.copy:
        await _actions.copy([rowid]);
        if (mounted) showHelixSnackBar(context, 'Copied');
      case HelixMessageActionIds.forward:
        await context.push(forwardLocation(_id, [rowid]));
      case HelixMessageActionIds.edit:
        final text = await ref
            .read(composerProvider(_id).notifier)
            .beginEdit(rowid);
        if (text != null) _composerKey.currentState?.setText(text);
      case HelixMessageActionIds.info:
        await context.push(infoLocation(_id, rowid));
      case HelixMessageActionIds.select:
        ref.read(messageSelectionProvider(_id).notifier).start(rowid);
      case HelixMessageActionIds.deleteForMe:
        final ok = await showHelixDestructiveDialog(
          context,
          title: 'Delete this message?',
          message: 'It is removed from this device only.',
          action: 'Delete for me',
        );
        if (ok) await _actions.deleteForMe([rowid]);
      case HelixMessageActionIds.deleteForEveryone:
        final ok = await showHelixDestructiveDialog(
          context,
          title: 'Delete for everyone?',
          message: 'People in this chat will see that it was deleted.',
          action: 'Delete for everyone',
        );
        if (!ok) return;
        final done = await _actions.deleteForEveryone(rowid);
        if (!done && mounted) {
          showHelixSnackBar(
            context,
            'It can no longer be deleted for everyone.',
          );
        }
    }
  }

  @override
  Future<void> reply(int rowid) async {
    await ref.read(composerProvider(_id).notifier).reply(rowid);
    _composerKey.currentState?.focus();
  }

  @override
  void jumpToMessage(String messageId) =>
      ref.read(timelineJumpProvider(_id).notifier).to(messageId);

  @override
  void showReactions(int rowid) {
    showHelixBottomSheet<void>(
      context,
      title: 'Reactions',
      builder: (sheetContext) => _ReactionsList(rowid: rowid),
    );
  }

  @override
  void retry(int rowid) => _actions.retry(rowid);

  @override
  Future<void> openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void openViewOnce(int rowid) => context.push(mediaLocation(_id, rowid));

  @override
  Future<void> tapMedia(int rowid, int index, List<MediaPart> parts) async {
    if (index < 0 || index >= parts.length) return;
    final part = parts[index];
    final result = await ref
        .read(mediaActionsProvider)
        .tap(part, messageRowid: rowid);
    if (result != MediaTap.open || !mounted) return;
    if (part.isVisual) {
      await context.push(mediaLocation(_id, rowid, index: index));
    } else {
      await ref.read(mediaActionsProvider).share(part);
    }
  }

  @override
  Future<void> toggleAudio(int rowid, List<MediaPart> parts) async {
    if (parts.isEmpty) return;
    final part = parts.first;
    if (!part.ready) {
      await ref.read(mediaActionsProvider).tap(part, messageRowid: rowid);
      return;
    }
    await ref.read(playbackProvider.notifier).toggle(rowid, part.id);
  }

  // ----------------------------------------------------------------- build

  Future<void> _deleteSelected(Set<int> selection) async {
    final count = selection.length;
    final ok = await showHelixDestructiveDialog(
      context,
      title: count == 1 ? 'Delete this message?' : 'Delete $count messages?',
      message: 'They are removed from this device only.',
      action: 'Delete for me',
    );
    if (!ok) return;
    await _actions.deleteForMe(selection);
    ref.read(messageSelectionProvider(_id).notifier).clear();
  }

  void _pickSearchHit(String messageId) {
    setState(() => _searching = false);
    _search.clear();
    ref.read(inChatSearchQueryProvider(_id).notifier).set('');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(timelineJumpProvider(_id).notifier).to(messageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(conversationOpenProvider(_id));
    final selection = ref.watch(messageSelectionProvider(_id));
    final selecting = selection.isNotEmpty;
    ref.listen(playbackProvider.select((s) => s.noticeSerial), (_, _) {
      final notice = ref.read(playbackProvider).notice;
      if (notice != null && mounted) showHelixSnackBar(context, notice);
    });

    final info = open.value;
    if (info == null) {
      return Scaffold(
        appBar: ConversationAppBar(conversationId: _id, onMenu: (_) {}),
        body: open.hasError
            ? const HelixErrorState(
                message: 'This conversation could not be opened.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final args = _args ??= TimelineArgs(
      _id,
      initialLimit: initialLimitFor(info),
      anchorMessageId: widget.messageId,
    );
    // Watched so the tracker lives as long as the screen.
    ref.watch(readTrackerProvider(_id));
    final tracker = ref.read(readTrackerProvider(_id).notifier);

    final PreferredSizeWidget appBar = selecting
        ? HelixSelectionBar(
            count: selection.length,
            onClose: ref.read(messageSelectionProvider(_id).notifier).clear,
            actions: [
              HelixBarAction(
                icon: Icons.content_copy,
                tooltip: 'Copy',
                onPressed: () async {
                  await _actions.copy(selection);
                  ref.read(messageSelectionProvider(_id).notifier).clear();
                  if (context.mounted) showHelixSnackBar(context, 'Copied');
                },
              ),
              HelixBarAction(
                icon: Icons.forward,
                tooltip: 'Forward',
                onPressed: () async {
                  final ids = selection.toList();
                  ref.read(messageSelectionProvider(_id).notifier).clear();
                  await context.push(forwardLocation(_id, ids));
                },
              ),
              HelixBarAction(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                onPressed: () => _deleteSelected(selection),
              ),
            ],
          )
        : _searching
        ? HelixSearchAppBar(
            title: '',
            searching: true,
            controller: _search,
            searchHint: 'Search this chat',
            onSearchChanged: (value) => setState(() => _searching = value),
            onQueryChanged: (value) =>
                ref.read(inChatSearchQueryProvider(_id).notifier).set(value),
          )
        : ConversationAppBar(
            conversationId: _id,
            onMenu: (action) {
              switch (action) {
                case ConversationMenuAction.search:
                  setState(() => _searching = true);
                case ConversationMenuAction.info:
                  final info = infoLocationOf(_id);
                  if (info != null) context.push(info);
                case ConversationMenuAction.media:
                  context.push(sharedMediaLocation(_id));
                case ConversationMenuAction.settings:
                  context.push(chatSettingsLocation(_id));
              }
            },
          );

    return PopScope(
      canPop: !selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          ref.read(messageSelectionProvider(_id).notifier).clear();
        } else if (_searching) {
          _search.clear();
          ref.read(inChatSearchQueryProvider(_id).notifier).set('');
          setState(() => _searching = false);
        }
      },
      child: Scaffold(
        appBar: appBar,
        body: Column(
          children: [
            // A group member the server's roster added without an admin's
            // announcement waits for this person's yes (not while selecting
            // or searching, which have the screen's attention).
            if (_id.startsWith(_groupPrefix) && !_searching && !selecting)
              PendingMembersPrompt(groupId: _id.substring(_groupPrefix.length)),
            Expanded(
              child: _searching
                  ? InChatSearchView(
                      conversationId: _id,
                      onPick: _pickSearchHit,
                    )
                  : TimelineView(
                      args: args,
                      ui: this,
                      onAtBottomChanged: tracker.setAtBottom,
                      onVisibleMessages: tracker.messagesChanged,
                    ),
            ),
            if (!_searching && !selecting)
              ComposerBar(key: _composerKey, conversationId: _id),
          ],
        ),
      ),
    );
  }
}

class _ReactionsList extends ConsumerWidget {
  const _ReactionsList({required this.rowid});

  final int rowid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(reactionDetailsProvider(rowid));
    return switch (lines) {
      AsyncData(:final value) when value.isEmpty => const Padding(
        padding: EdgeInsets.all(HelixSpace.lg),
        child: Text('No reactions yet.'),
      ),
      AsyncData(:final value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in value)
            ListTile(
              leading: HelixAvatar(
                model: line.avatar,
                size: HelixAvatarSize.sm,
              ),
              title: Text(line.name),
              trailing: Text(
                line.emoji,
                style: const TextStyle(fontSize: 22),
                textScaler: TextScaler.noScaling,
              ),
            ),
        ],
      ),
      _ => const Padding(
        padding: EdgeInsets.all(HelixSpace.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}
