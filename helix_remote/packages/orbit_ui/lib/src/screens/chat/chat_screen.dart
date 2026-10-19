import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/composer.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/timeline.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';
import 'package:orbit_ui/src/window/window_scaffold.dart';

/// Whether the conversation has opened (`contracts/conversation.md`).
enum ChatLoadState { loading, openFailed, loadFailed, ready }

/// Someone in a group who is not confirmed yet.
class PendingMemberItem {
  const PendingMemberItem({
    required this.account,
    required this.title,
    required this.explanation,
    required this.canRemove,
  });

  final String account;

  /// "Confirm Karim Uncle?"
  final String title;
  final String explanation;

  /// You are an admin: Remove is offered, and the member note is not.
  final bool canRemove;
}

/// `ChatModel` (`contracts/conversation.md`).
class ChatModel {
  const ChatModel({
    required this.conversationId,
    required this.title,
    required this.avatar,
    this.loadState = ChatLoadState.ready,
    this.subtitle,
    this.subtitleIsTyping = false,
    this.verified = false,
    this.isGroup = false,
    this.showCallButtons = true,
    this.pendingMembers = const [],
    this.items = const [],
    this.someoneTyping = false,
    this.composerDisabledReason,
    this.disabledIsBlock = false,
    this.initialDraft = '',
    this.banner,
    this.mentionCandidates = const [],
    this.recording = OrbitRecording.none,
    this.recordingWave = const [],
  });

  final String conversationId;
  final String title;
  final HelixAvatarModel avatar;
  final ChatLoadState loadState;

  /// "online", "last seen today at 08:31", "5 members", "typing...".
  final String? subtitle;
  final bool subtitleIsTyping;
  final bool verified;
  final bool isGroup;
  final bool showCallButtons;
  final List<PendingMemberItem> pendingMembers;

  /// The timeline, oldest first (the screen shows the newest at the bottom).
  final List<HelixTimelineItem> items;
  final bool someoneTyping;

  /// Replaces the composer: "You blocked this contact…".
  final String? composerDisabledReason;

  /// The reason starts with the "prohibited" sign.
  final bool disabledIsBlock;
  final String initialDraft;
  final HelixComposerBannerModel? banner;
  final List<HelixPersonItem> mentionCandidates;
  final OrbitRecording recording;
  final List<int> recordingWave;
}

/// `ChatActions` (`contracts/conversation.md`).
class ChatActions {
  const ChatActions({
    this.onBack,
    this.onOpenInfo,
    this.onOpenSharedMedia,
    this.onOpenSettings,
    this.onCall,
    this.onReply,
    this.onEdit,
    this.onCopy,
    this.onForward,
    this.onMessageInfo,
    this.onDeleteForMe,
    this.onDeleteForEveryone,
    this.onReact,
    this.onRetry,
    this.onRetryLoad,
    this.onConfirmMember,
    this.onRemoveMember,
    this.composer = const OrbitComposerActions(),
  });

  final VoidCallback? onBack;
  final VoidCallback? onOpenInfo;
  final VoidCallback? onOpenSharedMedia;
  final VoidCallback? onOpenSettings;
  final void Function({required bool video})? onCall;
  final ValueChanged<String>? onReply;
  final ValueChanged<String>? onEdit;
  final ValueChanged<Set<String>>? onCopy;
  final ValueChanged<Set<String>>? onForward;
  final ValueChanged<String>? onMessageInfo;
  final ValueChanged<Set<String>>? onDeleteForMe;
  final ValueChanged<String>? onDeleteForEveryone;
  final void Function(String messageId, String emoji)? onReact;
  final ValueChanged<String>? onRetry;
  final VoidCallback? onRetryLoad;
  final ValueChanged<String>? onConfirmMember;
  final ValueChanged<String>? onRemoveMember;
  final OrbitComposerActions composer;
}

/// Where the preview opens the chat (the prototype's `chat-*` keys).
class ChatStart {
  const ChatStart({
    this.searching = false,
    this.query = '',
    this.selected = const {},
    this.actionsFor,
    this.attach = false,
    this.emoji = false,
  });

  final bool searching;
  final String query;
  final Set<String> selected;

  /// The long-press actions are open on this message.
  final String? actionsFor;

  /// The attach sheet is open.
  final bool attach;

  /// The emoji panel is open under the composer.
  final bool emoji;
}

const _reactionSet = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const _emoji = {
  'Smileys':
      '😀 😃 😄 😁 😆 😅 😂 🤣 🙂 😉 😊 😇 🥰 😍 🤩 😘 😋 😜 🤪 🤗 🤭 🤔 😐 😏 😴 '
      '😌 😮 😢 😭 😤 😡 🥳 😎 🤓',
  'Gestures':
      '👍 👎 👌 ✌️ 🤞 🤟 🤙 👋 👏 🙌 👐 🤲 🙏 🤝 💪 👀 👆 👇 👉 👈 ✋ 🖐️ 🫶 ☝️',
  'Hearts and symbols':
      '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ 🔥 💯 ⭐ 🌟 💫 ✅ ❌ '
      '⚠️ ❓',
  'Things':
      '☕ 🍵 🍚 🍛 🍕 🍔 🎂 🍰 🎉 🎊 🎁 🎈 📷 📱 💻 🎧 📚 ✏️ 🔑 🏠 🚗 ✈️ 🌙 ☀️ 🌧️ '
      '🌊 🌸 🌻',
};

/// `chat` (`prototype/js/screens/conversation.js`): one conversation.
///
/// The header (←, the picture, name and subtitle that open the info page,
/// video and voice for a direct chat, ⋮), the pending-member cards of a
/// group, the timeline on the chat background with the newest at the
/// bottom, and the composer (or the reason nothing can be sent).
/// Long-press opens the message actions; selection swaps the header for
/// Copy, Forward and Delete; ⋮ offers the in-chat search.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.model,
    this.actions = const ChatActions(),
    this.start = const ChatStart(),
  });

  final ChatModel model;
  final ChatActions actions;
  final ChatStart start;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late bool _searching = widget.start.searching;
  late final _query = TextEditingController(text: widget.start.query);
  late final Set<String> _selected = {...widget.start.selected};
  late bool _emojiOpen = widget.start.emoji;
  final _attachKey = GlobalKey(debugLabel: 'attach');
  var _emojiTab = 'Smileys';

  ChatActions get _a => widget.actions;

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.attach) _attach();
      final id = s.actionsFor;
      if (id != null) _openActions(id);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  HelixMessage? _find(String id) {
    for (final it in widget.model.items) {
      if (it is HelixMessageItem && it.message.id == id) return it.message;
    }
    return null;
  }

  HelixRunPosition _position(String id) {
    for (final it in widget.model.items) {
      if (it is HelixMessageItem && it.message.id == id) return it.position;
    }
    return HelixRunPosition.single;
  }

  void _attach() {
    final t = OrbitTokens.of(context);
    Widget tile(OrbitGlyph icon, int colour, String label) {
      final (bg, ink) = OrbitAvatar.palette(t, colour);
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: OrbitIcon(
                      icon,
                      weight: OrbitIconWeight.fill,
                      size: 22,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: t.font.style(
                    size: OrbitType.caption,
                    weight: 560,
                    color: t.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tiles = [
      tile(OrbitIcons.fileText, 3, 'Document'),
      tile(OrbitIcons.camera, 5, 'Camera'),
      tile(OrbitIcons.images, 0, 'Gallery'),
      tile(OrbitIcons.headphones, 4, 'Audio'),
    ];
    // `.attach-grid`: four columns (the Pass 1 rule wins over the three
    // it first sets), 10px apart, 8px 18px 4px in.
    showOrbitSheet(
      context,
      anchor: _attachKey.currentContext,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, w) in tiles.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: w),
            ],
          ],
        ),
      ),
    );
  }

  void _openActions(String id) {
    final m = _find(id);
    if (m == null) return;
    final c = m.content;
    final placeholder = c is HelixPlaceholderContent;
    final deleted =
        c is HelixPlaceholderContent && c.kind == HelixPlaceholderKind.deleted;
    final hasText =
        c is HelixTextContent ||
        (c is HelixMediaContent && c.caption.isNotEmpty) ||
        (c is HelixDocumentContent && c.caption.isNotEmpty);
    final sent =
        m.status != HelixDeliveryStatus.pending &&
        m.status != HelixDeliveryStatus.failed;
    final textOrMedia = c is HelixTextContent || c is HelixMediaContent;
    final items = <(String, OrbitGlyph, String, bool, VoidCallback?)>[
      if (!placeholder && c is! HelixViewOnceContent)
        (
          'reply',
          OrbitIcons.arrowBendUpLeft,
          'Reply',
          false,
          () => _a.onReply?.call(id),
        ),
      if (hasText)
        ('copy', OrbitIcons.copy, 'Copy', false, () => _a.onCopy?.call({id})),
      if (!deleted && textOrMedia)
        (
          'forward',
          OrbitIcons.arrowBendUpRight,
          'Forward',
          false,
          () => _a.onForward?.call({id}),
        ),
      if (m.outgoing && sent && textOrMedia)
        (
          'edit',
          OrbitIcons.pencilSimple,
          'Edit',
          false,
          () => _a.onEdit?.call(id),
        ),
      if (m.outgoing)
        (
          'info',
          OrbitIcons.info,
          'Message info',
          false,
          () => _a.onMessageInfo?.call(id),
        ),
      (
        'select',
        OrbitIcons.checkCircle,
        'Select',
        false,
        () => setState(() => _selected.add(id)),
      ),
      (
        'delme',
        OrbitIcons.trash,
        'Delete for me',
        true,
        () => _a.onDeleteForMe?.call({id}),
      ),
      if (!deleted && m.outgoing && sent)
        (
          'delall',
          OrbitIcons.trashSimple,
          'Delete for everyone',
          true,
          () => _a.onDeleteForEveryone?.call(id),
        ),
    ];
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => _MessageActions(
          message: m,
          position: _position(id),
          group: widget.model.isGroup,
          showReactions: !placeholder,
          items: items,
          onReact: (e) => _a.onReact?.call(id, e),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final top = MediaQuery.paddingOf(context).top;
    Widget body;
    if (_searching) {
      body = _searchResults(t);
    } else {
      body = switch (m.loadState) {
        ChatLoadState.loading => const Center(
          child: OrbitPageLoading(label: 'Opening the conversation…'),
        ),
        ChatLoadState.openFailed => ListView(
          children: const [
            OrbitLoadFailed(title: 'This conversation could not be opened.'),
          ],
        ),
        ChatLoadState.loadFailed => ListView(
          children: [
            OrbitLoadFailed(
              title: 'Messages could not be loaded.',
              onRetry: _a.onRetryLoad,
            ),
          ],
        ),
        ChatLoadState.ready => _timeline(t),
      };
    }
    final showComposer =
        !_searching && _selected.isEmpty && m.loadState == ChatLoadState.ready;
    return ColoredBox(
      color: t.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t),
            if (!_searching && _selected.isEmpty)
              for (final p in m.pendingMembers) _PendingCard(p, actions: _a),
            Expanded(child: body),
            if (showComposer)
              OrbitComposer(
                initialText: m.initialDraft,
                banner: m.banner,
                recording: m.recording,
                recordingWave: m.recordingWave,
                disabled: m.composerDisabledReason,
                disabledIcon: m.disabledIsBlock,
                emojiOpen: _emojiOpen,
                mentions: m.mentionCandidates,
                attachKey: _attachKey,
                actions: OrbitComposerActions(
                  onSend: _a.composer.onSend,
                  onMic: _a.composer.onMic,
                  onAttach: _attach,
                  onCamera: _a.composer.onCamera,
                  onEmoji: () => setState(() => _emojiOpen = !_emojiOpen),
                  onCancelBanner: _a.composer.onCancelBanner,
                  onCancelRecording: _a.composer.onCancelRecording,
                  onSendRecording: _a.composer.onSendRecording,
                  onChanged: _a.composer.onChanged,
                  onMention: _a.composer.onMention,
                ),
              ),
            if (showComposer && _emojiOpen) _emojiPanel(t),
          ],
        ),
      ),
    );
  }

  Widget _header(OrbitTokens t) {
    final m = widget.model;
    if (_selected.isNotEmpty) {
      return OrbitAppBar(
        title: '${_selected.length} selected',
        selection: true,
        lead: OrbitAppBarLead.close,
        leadTooltip: 'Cancel selection',
        onLead: () => setState(_selected.clear),
        actions: [
          OrbitIconButton(
            icon: OrbitIcons.copy,
            tooltip: 'Copy',
            color: t.onInverse,
            onPressed: () => _a.onCopy?.call({..._selected}),
          ),
          OrbitIconButton(
            icon: OrbitIcons.arrowBendUpRight,
            tooltip: 'Forward',
            color: t.onInverse,
            onPressed: () => _a.onForward?.call({..._selected}),
          ),
          OrbitIconButton(
            icon: OrbitIcons.trash,
            tooltip: 'Delete',
            color: t.onInverse,
            onPressed: () {
              final ids = {..._selected};
              showOrbitDialog(
                context,
                title: ids.length > 1
                    ? 'Delete ${ids.length} messages?'
                    : 'Delete this message?',
                text: 'They are removed from this device only.',
                actions: [
                  const OrbitDialogAction('Cancel'),
                  OrbitDialogAction(
                    'Delete for me',
                    kind: OrbitButtonKind.danger,
                    onPressed: () {
                      _a.onDeleteForMe?.call(ids);
                      setState(_selected.clear);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      );
    }
    if (_searching) {
      return OrbitAppBar(
        leadTooltip: 'Close search',
        onLead: () => setState(() {
          _searching = false;
          _query.clear();
        }),
        titleWidget: SizedBox(
          height: 44,
          child: OrbitSearchField(
            hint: 'Search this chat',
            controller: _query,
            onChanged: (_) => setState(() {}),
          ),
        ),
      );
    }
    final sub = m.subtitle;
    final scope = OrbitPaneScope.maybeOf(context);
    final detailRoot =
        scope != null && scope.root && scope.pane == OrbitPane.detail;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      // The first page on a window's right has no back arrow: the list is
      // the way back (`.detail-root`, 14px in instead).
      padding: EdgeInsets.fromLTRB(detailRoot ? 14 : 6, 4, 2, 4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line2)),
      ),
      child: Row(
        children: [
          if (!detailRoot)
            OrbitIconButton(
              icon: OrbitIcons.arrowLeft,
              tooltip: 'Back',
              onPressed: _a.onBack ?? () => Navigator.maybePop(context),
            ),
          Expanded(
            child: Tooltip(
              message: m.isGroup ? 'Group info' : 'Contact info',
              excludeFromSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _a.onOpenInfo,
                  hoverColor: t.field,
                  splashFactory: NoSplash.splashFactory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        OrbitAvatar(avatar: m.avatar, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: OrbitText(
                                      m.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.font.style(
                                        size: OrbitType.headline,
                                        weight: 620,
                                        color: t.ink,
                                        letterSpacingEm: -0.01,
                                      ),
                                    ),
                                  ),
                                  if (m.verified) ...[
                                    const SizedBox(width: 5),
                                    OrbitIcon(
                                      OrbitIcons.sealCheck,
                                      weight: OrbitIconWeight.fill,
                                      size: 15,
                                      color: t.accent,
                                    ),
                                  ],
                                ],
                              ),
                              if (sub != null && sub.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: OrbitText(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.mono.style(
                                      size: OrbitType.meta,
                                      color: m.subtitleIsTyping
                                          ? t.accentInk
                                          : t.ink3,
                                      letterSpacingEm: 0.03,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (m.showCallButtons) ...[
            OrbitIconButton(
              icon: OrbitIcons.videoCamera,
              tooltip: 'Video call',
              onPressed: () => _a.onCall?.call(video: true),
            ),
            OrbitIconButton(
              icon: OrbitIcons.phone,
              tooltip: 'Voice call',
              onPressed: () => _a.onCall?.call(video: false),
            ),
          ],
          OrbitIconButton(
            icon: OrbitIcons.dotsThreeVertical,
            tooltip: 'More options',
            onPressed: () => showOrbitMenu(context, [
              OrbitMenuItem(
                icon: OrbitIcons.magnifyingGlass,
                label: 'Search',
                onTap: () => setState(() => _searching = true),
              ),
              OrbitMenuItem(
                icon: m.isGroup ? OrbitIcons.usersThree : OrbitIcons.userCircle,
                label: m.isGroup ? 'Group info' : 'Contact info',
                onTap: _a.onOpenInfo,
              ),
              OrbitMenuItem(
                icon: OrbitIcons.images,
                label: 'Media, links and docs',
                onTap: _a.onOpenSharedMedia,
              ),
              OrbitMenuItem(
                icon: OrbitIcons.gearSix,
                label: 'Chat settings',
                onTap: _a.onOpenSettings,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _timeline(OrbitTokens t) {
    final m = widget.model;
    final items = [
      for (final it in m.items)
        if (it is HelixMessageItem)
          HelixMessageItem(
            it.message,
            position: it.position,
            selected: _selected.contains(it.message.id),
          )
        else
          it,
      if (m.items.isEmpty) const HelixEncryptionNoticeItem(),
      if (m.someoneTyping) const HelixTypingItem(),
    ];
    return OrbitPatternBackground(
      pattern: t.chatPattern,
      color: t.chatBg,
      child: SingleChildScrollView(
        reverse: true,
        child: OrbitTimeline(
          items: items,
          group: m.isGroup,
          onRetry: _a.onRetry,
          onTapMessage: (id) {
            if (_selected.isNotEmpty) {
              setState(
                () => _selected.contains(id)
                    ? _selected.remove(id)
                    : _selected.add(id),
              );
            }
          },
          onLongPressMessage: (id) => _selected.isNotEmpty
              ? setState(() => _selected.add(id))
              : _openActions(id),
        ),
      ),
    );
  }

  Widget _searchResults(OrbitTokens t) {
    final m = widget.model;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      return ColoredBox(
        color: t.surface,
        child: const SingleChildScrollView(
          child: OrbitEmptyState(
            icon: OrbitIcons.magnifyingGlass,
            title: 'Search this chat',
            text: 'Type a word to find messages that contain it.',
          ),
        ),
      );
    }
    final hits = [
      for (final it in m.items)
        if (it is HelixMessageItem &&
            it.message.content is HelixTextContent &&
            (it.message.content as HelixTextContent).text
                .toLowerCase()
                .contains(q))
          it.message,
    ];
    if (hits.isEmpty) {
      return ColoredBox(
        color: t.surface,
        child: SingleChildScrollView(
          child: OrbitEmptyState(
            icon: OrbitIcons.magnifyingGlass,
            title: 'No results',
            text: 'Nothing matches “${_query.text.trim()}”.',
          ),
        ),
      );
    }
    return ColoredBox(
      color: t.surface,
      child: ListView(
        padding: const EdgeInsets.only(top: 6),
        children: [
          for (final h in hits) _SearchHit(message: h, chat: m, query: q),
        ],
      ),
    );
  }

  Widget _emojiPanel(OrbitTokens t) => Container(
    height: 260,
    decoration: BoxDecoration(
      color: t.surface,
      border: Border(top: BorderSide(color: t.line2)),
    ),
    child: Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line2)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                for (final (i, k) in _emoji.keys.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  OrbitChip(
                    label: k,
                    on: k == _emojiTab,
                    onTap: () => setState(() => _emojiTab = k),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 8,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
            childAspectRatio: (412 - 16) / 8 / 44,
            children: [
              for (final e in _emoji[_emojiTab]!.split(' '))
                Semantics(
                  button: true,
                  label: e,
                  child: Center(child: Text(e, style: t.font.style(size: 26))),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// `.pending-card`: a member to confirm, amber: a filled shield 12px before
/// the title (weight 640), the explanation in `--ink-2`, and Confirm (and
/// Remove for an admin) as 38px buttons 10px under it.
class _PendingCard extends StatelessWidget {
  const _PendingCard(this.p, {required this.actions});

  final PendingMemberItem p;
  final ChatActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final text = t.font.style(
      size: OrbitType.small,
      color: t.ink2,
      height: 1.45,
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.warningSoft,
        border: Border.all(color: t.warningLine),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: OrbitIcon(
              OrbitIcons.shieldWarning,
              weight: OrbitIconWeight.fill,
              size: 22,
              color: t.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrbitText(
                  p.title,
                  style: text.copyWith(
                    color: t.ink,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [ui.FontVariation('wght', 640)],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: OrbitText(p.explanation, style: text),
                ),
                if (!p.canRemove)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OrbitText(
                      'Only an admin can remove someone. If you do not know '
                      'them, you can leave the group.',
                      style: text.copyWith(color: t.ink3),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OrbitButton(
                        label: 'Confirm',
                        height: 38,
                        padding: 16,
                        fontSize: 13,
                        onPressed: () =>
                            actions.onConfirmMember?.call(p.account),
                      ),
                      if (p.canRemove)
                        OrbitButton(
                          label: 'Remove',
                          kind: OrbitButtonKind.secondary,
                          height: 38,
                          padding: 16,
                          fontSize: 13,
                          onPressed: () =>
                              actions.onRemoveMember?.call(p.account),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A message found by the in-chat search: who sent it (a 44px picture),
/// the time, and the text with the match in bold `--accent-ink`.
class _SearchHit extends StatelessWidget {
  const _SearchHit({
    required this.message,
    required this.chat,
    required this.query,
  });

  final HelixMessage message;
  final ChatModel chat;
  final String query;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = message;
    final who = m.outgoing
        ? 'You'
        : (m.authorName ?? chat.title.split(' ').first);
    final avatar = m.outgoing
        ? const HelixAvatarModel(name: 'Hasan')
        : m.authorName != null
        ? HelixAvatarModel(name: m.authorName!, colorIndex: m.authorColorIndex)
        : chat.avatar;
    final text = (m.content as HelixTextContent).text;
    final at = text.toLowerCase().indexOf(query);
    final base = t.font.style(size: OrbitType.small, color: t.ink3);
    return InkWell(
      onTap: () {},
      hoverColor: t.hover,
      splashFactory: NoSplash.splashFactory,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OrbitSpace.gutter,
            vertical: 10,
          ),
          child: Row(
            children: [
              OrbitAvatar(avatar: avatar, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OrbitText(
                            who,
                            style: t.font.style(
                              size: OrbitType.headline,
                              weight: 600,
                              color: t.ink,
                              letterSpacingEm: -0.01,
                            ),
                          ),
                        ),
                        OrbitText(
                          m.timeLabel,
                          style: t.mono.style(
                            size: OrbitType.meta,
                            color: t.ink3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    OrbitText.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: text.substring(0, at)),
                          TextSpan(
                            text: text.substring(at, at + query.length),
                            style: base.copyWith(
                              color: t.accentInk,
                              fontWeight: FontWeight.w700,
                              fontVariations: const [
                                ui.FontVariation('wght', 700),
                              ],
                            ),
                          ),
                          TextSpan(text: text.substring(at + query.length)),
                        ],
                      ),
                      style: base,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.msg-actions`: a long-pressed message over a blurred scrim, with the
/// reactions above it (a pill of six and +) and the actions under it (a
/// card of 46px rows), on the message's side.
class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.message,
    required this.position,
    required this.group,
    required this.showReactions,
    required this.items,
    required this.onReact,
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final bool group;
  final bool showReactions;
  final List<(String, OrbitGlyph, String, bool, VoidCallback?)> items;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final out = message.outgoing;
    final align = out ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    void close() => Navigator.of(context).pop();
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: close,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                // The prototype's own rgba(13, 16, 25, 0.5).
                child: const ColoredBox(color: Color(0x800D1019)),
              ),
            ),
          ),
          // A window keeps it to the middle 560px (`.win .msg-actions`).
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: align,
                  children: [
                    if (showReactions)
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: t.surface,
                          border: Border.all(color: t.line),
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: t.shadowFloat,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, e) in _reactionSet.indexed) ...[
                              if (i > 0) const SizedBox(width: 2),
                              _ReactButton(
                                mine: message.reactions.any(
                                  (r) => r.mine && r.emoji == e,
                                ),
                                label: 'React with $e',
                                onTap: () {
                                  close();
                                  onReact(e);
                                },
                                child: Text(e, style: t.font.style(size: 24)),
                              ),
                            ],
                            const SizedBox(width: 2),
                            _ReactButton(
                              label: 'More reactions',
                              onTap: close,
                              child: OrbitIcon(
                                OrbitIcons.plus,
                                weight: OrbitIconWeight.bold,
                                size: 20,
                                color: t.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    IgnorePointer(
                      child: OrbitMessageBubble(
                        message: message,
                        position: position,
                        group: group,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      constraints: const BoxConstraints(minWidth: 220),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: t.surface,
                        border: Border.all(color: t.line),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: t.shadowFloat,
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (_, icon, label, danger, run) in items)
                              Material(
                                type: MaterialType.transparency,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    close();
                                    run?.call();
                                  },
                                  hoverColor: t.field,
                                  splashFactory: NoSplash.splashFactory,
                                  child: SizedBox(
                                    height: 46,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          OrbitIcon(
                                            icon,
                                            size: 19,
                                            color: danger ? t.danger : t.ink3,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            label,
                                            style: t.font.style(
                                              size: 14.5,
                                              color: danger ? t.danger : t.ink,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactButton extends StatelessWidget {
  const _ReactButton({
    required this.child,
    required this.label,
    required this.onTap,
    this.mine = false,
  });

  final Widget child;
  final String label;
  final VoidCallback onTap;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: mine ? t.accentSoft : null,
              shape: BoxShape.circle,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
