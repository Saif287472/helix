import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/composer.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/timeline.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart';
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
    this.name = '',
  });

  final String account;

  /// "Confirm Karim Uncle?"
  final String title;
  final String explanation;

  /// You are an admin: Remove is offered, and the member note is not.
  final bool canRemove;

  /// "Karim Uncle", for "Remove Karim Uncle?"; empty takes it from [title].
  final String name;

  String get displayName {
    if (name.isNotEmpty) return name;
    final t = title.trim();
    final bare = t.startsWith('Confirm ') ? t.substring(8) : t;
    return bare.endsWith('?') ? bare.substring(0, bare.length - 1) : bare;
  }
}

/// What can be done to one message, in the order the actions view lists
/// them.
enum ChatMessageAction {
  reply,
  copy,
  forward,
  edit,
  info,
  select,
  deleteForMe,
  deleteForEveryone,
}

/// The long-press menu of one message, when the app decides it
/// (`ChatActions.messageMenu`).
class ChatMessageMenu {
  const ChatMessageMenu({
    required this.actions,
    this.allowReactions = true,
    this.currentReaction,
  });

  final Set<ChatMessageAction> actions;

  /// The reactions pill is offered.
  final bool allowReactions;

  /// The reaction this account already gave.
  final String? currentReaction;
}

/// One line of the Reactions sheet: who reacted with what.
class ChatReactionLine {
  const ChatReactionLine({
    required this.emoji,
    required this.name,
    required this.avatar,
    this.mine = false,
  });

  final String emoji;
  final String name;
  final HelixAvatarModel avatar;

  /// Yours: "Tap to remove".
  final bool mine;
}

/// Where picked files come from (the attach and camera sheets).
enum ChatAttachSource { gallery, document, audio, cameraPhoto, cameraVideo }

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
    this.hasInfoPage = true,
    this.pendingMembers = const [],
    this.items = const [],
    this.hasOlder = false,
    this.hasNewer = false,
    this.unreadCount = 0,
    this.openAtUnread = false,
    this.focus,
    this.someoneTyping = false,
    this.composerDisabledReason,
    this.disabledIsBlock = false,
    this.initialDraft = '',
    this.banner,
    this.mentionCandidates = const [],
    this.recording = OrbitRecording.none,
    this.recordingTime = '0:07',
    this.recordingWave = const [],
    this.enterSends = false,
    this.searchHits,
    this.searchStatus = ListStatus.ready,
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

  /// There is a contact or group info page (the header and ⋮ open it).
  final bool hasInfoPage;
  final List<PendingMemberItem> pendingMembers;

  /// The timeline, oldest first (the screen shows the newest at the bottom).
  final List<HelixTimelineItem> items;

  /// There are older messages than [items] (scrolling up loads them).
  final bool hasOlder;

  /// [items] stop before the newest message (after a jump into the past).
  final bool hasNewer;

  /// The badge on "Scroll to latest message".
  final int unreadCount;

  /// Open at the unread line rather than at the newest message (the app;
  /// the prototype always opens at the bottom).
  final bool openAtUnread;

  /// Bring the item with this id into view (a jump); a new [serial] asks
  /// again for the same one. The highlight is the item's own.
  final ({String id, int serial})? focus;
  final bool someoneTyping;

  /// Replaces the composer: "You blocked this contact…".
  final String? composerDisabledReason;

  /// The reason starts with the "prohibited" sign.
  final bool disabledIsBlock;
  final String initialDraft;
  final HelixComposerBannerModel? banner;
  final List<HelixPersonItem> mentionCandidates;
  final OrbitRecording recording;

  /// The recording's length so far, "0:07".
  final String recordingTime;
  final List<int> recordingWave;

  /// Enter sends the message (You > Chats); Shift+Enter is a new line.
  final bool enterSends;

  /// The in-chat search's results, when the app runs the search; null
  /// searches [items] here.
  final List<ChatSearchHit>? searchHits;
  final ListStatus searchStatus;
}

/// `ChatActions` (`contracts/conversation.md`). Message ids are
/// [HelixMessage.id]; everything is optional.
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
    this.messageMenu,
    this.reactionsOf,
    this.onRemoveMyReaction,
    this.onQuote,
    this.onOpenLink,
    this.onTapMedia,
    this.onOpenViewOnce,
    this.onToggleAudio,
    this.onAudioSpeed,
    this.onAudioSeek,
    this.onLoadOlder,
    this.onLoadNewer,
    this.onScrollToLatest,
    this.onAtBottomChanged,
    this.onRowsShown,
    this.onJumpTo,
    this.onSearchQuery,
    this.onSend,
    this.onTextChanged,
    this.onPickMention,
    this.onCancelBanner,
    this.onPickFiles,
    this.onVoiceStart,
    this.onVoiceSlide,
    this.onVoiceLock,
    this.onVoiceEnd,
    this.onLeave,
    this.composer = const OrbitComposerActions(),
  });

  final VoidCallback? onBack;
  final VoidCallback? onOpenInfo;
  final VoidCallback? onOpenSharedMedia;
  final VoidCallback? onOpenSettings;

  /// Places a call; returns a sentence to show when it could not start.
  final FutureOr<String?> Function({required bool video})? onCall;

  /// Quote the message in the next one; the field gets the cursor after.
  final FutureOr<void> Function(String id)? onReply;

  /// Start editing; returns the text for the field, null when it can no
  /// longer be edited.
  final FutureOr<String?> Function(String id)? onEdit;

  /// Copies the messages ("Copied" follows).
  final FutureOr<void> Function(Set<String> ids)? onCopy;
  final ValueChanged<Set<String>>? onForward;
  final ValueChanged<String>? onMessageInfo;

  /// Deletes from this device; the confirm dialog is the screen's.
  final FutureOr<void> Function(Set<String> ids)? onDeleteForMe;

  /// False when it can no longer be deleted for everyone.
  final FutureOr<bool> Function(String id)? onDeleteForEveryone;

  /// The same emoji again takes it back; another swaps it.
  final void Function(String messageId, String emoji)? onReact;
  final ValueChanged<String>? onRetry;
  final VoidCallback? onRetryLoad;

  /// Confirm or remove a pending member; returns a sentence to show.
  final FutureOr<String?> Function(String account)? onConfirmMember;
  final FutureOr<String?> Function(String account)? onRemoveMember;

  /// What the message's actions view offers; null when it is gone. Without
  /// it the screen decides from the message alone.
  final FutureOr<ChatMessageMenu?> Function(String id)? messageMenu;

  /// Who reacted to the message, for the Reactions sheet.
  final Future<List<ChatReactionLine>> Function(String id)? reactionsOf;
  final FutureOr<void> Function(String id)? onRemoveMyReaction;

  /// The quote in this message was tapped.
  final ValueChanged<String>? onQuote;
  final ValueChanged<String>? onOpenLink;
  final void Function(String id, int index)? onTapMedia;
  final ValueChanged<String>? onOpenViewOnce;
  final ValueChanged<String>? onToggleAudio;
  final ValueChanged<String>? onAudioSpeed;
  final void Function(String id, double fraction)? onAudioSeek;

  /// Scrolled near the oldest (or, after a jump, the newest) loaded item.
  final VoidCallback? onLoadOlder;
  final VoidCallback? onLoadNewer;

  /// "Scroll to latest message" (the scroll itself is the screen's).
  final VoidCallback? onScrollToLatest;

  /// The list reached or left the newest message (read receipts).
  final ValueChanged<bool>? onAtBottomChanged;

  /// Items the list built, by id, once per frame.
  final ValueChanged<List<String>>? onRowsShown;

  /// A search result was picked: its message id.
  final ValueChanged<String>? onJumpTo;
  final ValueChanged<String>? onSearchQuery;

  /// Sends the text (or saves the edit); true clears the field.
  final FutureOr<bool> Function(String text)? onSend;
  final void Function(String text, int cursor)? onTextChanged;

  /// Inserts "@Name ": the new text and cursor.
  final ({String text, int cursor}) Function(
    HelixPersonItem person,
    String text,
    int cursor,
  )?
  onPickMention;
  final VoidCallback? onCancelBanner;
  final ValueChanged<ChatAttachSource>? onPickFiles;

  /// Hold to record (see [OrbitComposerActions]).
  final VoidCallback? onVoiceStart;
  final void Function(double cancel, double lock)? onVoiceSlide;
  final VoidCallback? onVoiceLock;
  final void Function({required bool send})? onVoiceEnd;

  /// The screen is closing, with the unsent text.
  final ValueChanged<String>? onLeave;

  /// The preview's composer hooks, used where the ones above are not set.
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
///
/// The timeline is a lazy list built from the bottom: it opens at the
/// unread line, follows the newest message while you are at the bottom (or
/// after you send), keeps your place when messages arrive while you read
/// further up, pages older (and, after a jump, newer) messages in as you
/// near either end, and brings [ChatModel.focus] into view.
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

  // The composer's text, owned here so an edit can fill it, an emoji goes in
  // at the cursor, and the draft is saved when the screen closes.
  late final _text = TextEditingController(text: widget.model.initialDraft);
  final _focus = FocusNode(debugLabel: 'composer');
  var _typed = false;

  // The timeline's scrolling (`contracts/conversation.md`, kept inside).
  final _scroll = ScrollController();
  var _atBottom = true;
  var _away = false;
  var _olderAskedAt = -1;
  String? _newestId;
  var _keepPosition = false;
  var _openedAtUnread = false;
  String? _focusId;
  GlobalKey? _focusKey;
  int? _focusSerial;
  String? _pendingFocus;
  var _rowsList = const <HelixTimelineItem>[];
  final Map<String, _CachedRow> _rows = {};
  final Set<String> _drawn = {};
  var _flushQueued = false;

  final Set<String> _busyMembers = {};
  late OrbitBubbleActions _bubble = _bubbleFor(widget);

  ChatActions get _a => widget.actions;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _focus.addListener(_onFocus);
    _newestId = _newest(widget.model.items);
    final s = widget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.attach) _attach();
      final id = s.actionsFor;
      if (id != null) _openActions(id);
      _afterItems();
    });
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    final m = widget.model;
    final next = _bubbleFor(widget);
    if (!_sameHooks(next, _bubble)) {
      _bubble = next;
      _rows.clear();
    }
    // The draft arrives after the screen opens.
    if (!_typed &&
        _text.text.isEmpty &&
        m.initialDraft.isNotEmpty &&
        m.initialDraft != old.model.initialDraft) {
      _text.text = m.initialDraft;
    }
    if (!identical(old.model.items, m.items) ||
        old.model.focus?.serial != m.focus?.serial) {
      _itemsChanged();
    }
  }

  @override
  void dispose() {
    _a.onLeave?.call(_text.text);
    _scroll.dispose();
    _query.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ bubbles

  /// The bubbles' hooks, for what [w] offers. Swiping to reply is off where
  /// nothing can be sent (blocked, or no longer in the group).
  OrbitBubbleActions _bubbleFor(ChatScreen w) {
    final a = w.actions;
    return OrbitBubbleActions(
      onReply: a.onReply == null || w.model.composerDisabledReason != null
          ? null
          : _reply,
      onQuote: a.onQuote == null
          ? null
          : (id) => widget.actions.onQuote?.call(id),
      onReactions: a.reactionsOf == null ? null : _reactionsSheet,
      onLink: a.onOpenLink == null
          ? null
          : (url) => widget.actions.onOpenLink?.call(url),
      onMedia: a.onTapMedia == null
          ? null
          : (id, i) => widget.actions.onTapMedia?.call(id, i),
      onViewOnce: a.onOpenViewOnce == null
          ? null
          : (id) => widget.actions.onOpenViewOnce?.call(id),
      onAudioToggle: a.onToggleAudio == null
          ? null
          : (id) => widget.actions.onToggleAudio?.call(id),
      onAudioSpeed: a.onAudioSpeed == null
          ? null
          : (id) => widget.actions.onAudioSpeed?.call(id),
      onAudioSeek: a.onAudioSeek == null
          ? null
          : (id, f) => widget.actions.onAudioSeek?.call(id, f),
    );
  }

  static bool _sameHooks(OrbitBubbleActions a, OrbitBubbleActions b) =>
      (a.onReply == null) == (b.onReply == null) &&
      (a.onQuote == null) == (b.onQuote == null) &&
      (a.onReactions == null) == (b.onReactions == null) &&
      (a.onLink == null) == (b.onLink == null) &&
      (a.onMedia == null) == (b.onMedia == null) &&
      (a.onViewOnce == null) == (b.onViewOnce == null) &&
      (a.onAudioToggle == null) == (b.onAudioToggle == null) &&
      (a.onAudioSpeed == null) == (b.onAudioSpeed == null) &&
      (a.onAudioSeek == null) == (b.onAudioSeek == null);

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

  void _toast(String? text) {
    if (text == null || text.isEmpty || !mounted) return;
    showOrbitToast(context, text);
  }

  // ------------------------------------------------------------ timeline

  static String? _newest(List<HelixTimelineItem> items) =>
      items.isEmpty ? null : items.last.id;

  /// What the list draws, newest first: the typing dots, then the items (or
  /// the encryption card when there are none).
  List<HelixTimelineItem> _newestFirst() {
    final m = widget.model;
    return [
      if (m.someoneTyping) const HelixTypingItem(),
      if (m.items.isEmpty) const HelixEncryptionNoticeItem(),
      for (var i = m.items.length - 1; i >= 0; i--) m.items[i],
    ];
  }

  int? _indexOf(String id) {
    final i = _rowsList.indexWhere((it) => it.id == id);
    return i < 0 ? null : i;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // The list is reversed: pixels 0 is the newest message.
    final atBottom = pos.pixels <= 60;
    if (atBottom != _atBottom) {
      _atBottom = atBottom;
      _a.onAtBottomChanged?.call(atBottom);
    }
    final away = pos.pixels >= 160;
    if (away != _away) setState(() => _away = away);
    final m = widget.model;
    if (pos.maxScrollExtent - pos.pixels < 800 &&
        m.hasOlder &&
        _olderAskedAt != m.items.length) {
      _olderAskedAt = m.items.length;
      _a.onLoadOlder?.call();
    }
    if (pos.pixels < 800 && m.hasNewer) _a.onLoadNewer?.call();
  }

  /// New items: stay put, follow the newest message, open at the unread
  /// line, or bring the focus into view.
  void _itemsChanged() {
    final m = widget.model;
    final newest = _newest(m.items);
    final grew = _newestId != null && newest != _newestId;
    final last = m.items.isEmpty ? null : m.items.last;
    final mine = last is HelixMessageItem && last.message.outgoing;
    _newestId = newest;
    if (grew && !m.hasNewer) {
      if (_atBottom || mine) {
        // Follow: a message you sent, or one that arrived while you were at
        // the bottom, is shown.
        _keepPosition = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        // Reading further up: keep what is on screen where it is.
        _keepPosition = true;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterItems());
  }

  void _afterItems() {
    if (!mounted) return;
    final m = widget.model;
    if (m.openAtUnread &&
        !_openedAtUnread &&
        m.items.any((it) => it is HelixUnreadDividerItem)) {
      _openedAtUnread = true;
      _scrollTo('unread');
    }
    final focus = m.focus;
    if (focus != null && focus.serial != _focusSerial) {
      _focusSerial = focus.serial;
      _pendingFocus = focus.id;
    }
    final pending = _pendingFocus;
    if (pending != null && m.items.any((it) => it.id == pending)) {
      _pendingFocus = null;
      _scrollTo(pending);
    }
  }

  /// Brings the item [id] into view, even when it is far from what is built.
  void _scrollTo(String id, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final index = _indexOf(id);
    if (index == null) {
      if (attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(id, attempt: attempt + 1),
        );
      }
      return;
    }
    if (_focusId != id) {
      setState(() {
        _focusId = id;
        _focusKey = GlobalKey();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _focusKey?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 250),
        );
        return;
      }
      if (attempt < 6 && _scroll.hasClients) {
        // Not built yet: jump close by an estimate, so it gets built.
        final estimate = index * 90.0;
        _scroll.jumpTo(estimate.clamp(0.0, _scroll.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(id, attempt: attempt + 1),
        );
      }
    });
  }

  void _toLatest() {
    if (widget.model.hasNewer) _a.onScrollToLatest?.call();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// An item was built: reported after the frame, never during one.
  void _noteDrawn(String id) {
    if (_a.onRowsShown == null) return;
    _drawn.add(id);
    if (_flushQueued) return;
    _flushQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushQueued = false;
      if (!mounted || _drawn.isEmpty) return;
      final ids = _drawn.toList(growable: false);
      _drawn.clear();
      _a.onRowsShown?.call(ids);
    });
  }

  void _tapMessage(String id) {
    if (_selected.isNotEmpty) _toggle(id);
  }

  void _longPress(String id) =>
      _selected.isNotEmpty ? _toggle(id) : _openActions(id);

  void _toggle(String id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

  void _retry(String id) => widget.actions.onRetry?.call(id);

  // ------------------------------------------------------------ actions

  Future<void> _reply(String id) async {
    await widget.actions.onReply?.call(id);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _edit(String id) async {
    final text = await widget.actions.onEdit?.call(id);
    if (text == null || !mounted) return;
    _typed = true;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _copy(Set<String> ids) async {
    await widget.actions.onCopy?.call(ids);
    _toast('Copied');
  }

  void _deleteForMe(Set<String> ids, {bool clearSelection = false}) {
    showOrbitDialog(
      context,
      title: ids.length > 1
          ? 'Delete ${ids.length} messages?'
          : 'Delete this message?',
      text: clearSelection
          ? 'They are removed from this device only.'
          : 'It is removed from this device only.',
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          'Delete for me',
          kind: OrbitButtonKind.danger,
          onPressed: () {
            widget.actions.onDeleteForMe?.call(ids);
            if (clearSelection && mounted) setState(_selected.clear);
          },
        ),
      ],
    );
  }

  void _deleteForEveryone(String id) {
    showOrbitDialog(
      context,
      title: 'Delete for everyone?',
      text: 'People in this chat will see that it was deleted.',
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          'Delete for everyone',
          kind: OrbitButtonKind.danger,
          onPressed: () async {
            final done = await widget.actions.onDeleteForEveryone?.call(id);
            if (done == false) {
              _toast('It can no longer be deleted for everyone.');
            }
          },
        ),
      ],
    );
  }

  /// The prototype's rules, when the app does not decide the menu.
  ChatMessageMenu _menuOf(HelixMessage m) {
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
    String? mine;
    for (final r in m.reactions) {
      if (r.mine) mine = r.emoji;
    }
    return ChatMessageMenu(
      actions: {
        if (!placeholder && c is! HelixViewOnceContent) ChatMessageAction.reply,
        if (hasText) ChatMessageAction.copy,
        if (!deleted && textOrMedia) ChatMessageAction.forward,
        if (m.outgoing && sent && textOrMedia) ChatMessageAction.edit,
        if (m.outgoing) ChatMessageAction.info,
        ChatMessageAction.select,
        ChatMessageAction.deleteForMe,
        if (!deleted && m.outgoing && sent) ChatMessageAction.deleteForEveryone,
      },
      allowReactions: !placeholder,
      currentReaction: mine,
    );
  }

  void _openActions(String id) {
    final ask = widget.actions.messageMenu;
    if (ask == null) {
      final m = _find(id);
      if (m != null) _showActions(id, m, _menuOf(m));
      return;
    }
    Future.sync(() => ask(id)).then((menu) {
      final m = _find(id);
      if (menu == null || m == null || !mounted) return;
      _showActions(id, m, menu);
    });
  }

  void _showActions(String id, HelixMessage m, ChatMessageMenu menu) {
    final a = widget.actions;
    final rows = <ChatMessageAction, (OrbitGlyph, String, bool, VoidCallback)>{
      ChatMessageAction.reply: (
        OrbitIcons.arrowBendUpLeft,
        'Reply',
        false,
        () => _reply(id),
      ),
      ChatMessageAction.copy: (
        OrbitIcons.copy,
        'Copy',
        false,
        () => _copy({id}),
      ),
      ChatMessageAction.forward: (
        OrbitIcons.arrowBendUpRight,
        'Forward',
        false,
        () => a.onForward?.call({id}),
      ),
      ChatMessageAction.edit: (
        OrbitIcons.pencilSimple,
        'Edit',
        false,
        () => _edit(id),
      ),
      ChatMessageAction.info: (
        OrbitIcons.info,
        'Message info',
        false,
        () => a.onMessageInfo?.call(id),
      ),
      ChatMessageAction.select: (
        OrbitIcons.checkCircle,
        'Select',
        false,
        () => setState(() => _selected.add(id)),
      ),
      ChatMessageAction.deleteForMe: (
        OrbitIcons.trash,
        'Delete for me',
        true,
        () => _deleteForMe({id}),
      ),
      ChatMessageAction.deleteForEveryone: (
        OrbitIcons.trashSimple,
        'Delete for everyone',
        true,
        () => _deleteForEveryone(id),
      ),
    };
    final items = [
      for (final action in ChatMessageAction.values)
        if (menu.actions.contains(action)) rows[action]!,
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
          showReactions: menu.allowReactions,
          currentReaction: menu.currentReaction,
          items: items,
          onReact: (e) => widget.actions.onReact?.call(id, e),
          onMore: () => _moreReactions(id),
        ),
      ),
    );
  }

  /// "+": every emoji, to react with (`App.sheet({ title: 'React' })`).
  void _moreReactions(String id) {
    final t = OrbitTokens.of(context);
    final all = [for (final g in _emoji.values) ...g.split(' ')];
    showOrbitSheet(
      context,
      title: 'React',
      body: Builder(
        builder: (sheet) => ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: GridView.count(
            crossAxisCount: 8,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
            childAspectRatio: (412 - 16) / 8 / 44,
            children: [
              for (final e in all)
                Semantics(
                  button: true,
                  label: e,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      widget.actions.onReact?.call(id, e);
                    },
                    child: Center(
                      child: Text(e, style: t.font.style(size: 26)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A reaction under a message: who reacted with what; yours can go.
  void _reactionsSheet(String id) {
    final load = widget.actions.reactionsOf;
    if (load == null) return;
    final lines = load(id);
    showOrbitSheet(
      context,
      title: 'Reactions',
      body: Builder(
        builder: (sheet) {
          final t = OrbitTokens.of(sheet);
          return FutureBuilder<List<ChatReactionLine>>(
            future: lines,
            builder: (context, snap) {
              final value = snap.data;
              if (value == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: OrbitSpinner(size: 28)),
                );
              }
              if (value.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: OrbitText(
                    'No reactions yet.',
                    style: t.font.style(size: OrbitType.small, color: t.ink3),
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in value)
                    OrbitListRow(
                      title: line.name,
                      sub: line.mine ? 'Tap to remove' : '',
                      leading: OrbitAvatar(avatar: line.avatar, size: 40),
                      trailing: Text(line.emoji, style: t.font.style(size: 22)),
                      onTap: line.mine
                          ? () {
                              Navigator.of(sheet).pop();
                              widget.actions.onRemoveMyReaction?.call(id);
                            }
                          : null,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmMember(PendingMemberItem p) async {
    final run = widget.actions.onConfirmMember;
    if (run == null || _busyMembers.contains(p.account)) return;
    setState(() => _busyMembers.add(p.account));
    final said = await run(p.account);
    if (!mounted) return;
    setState(() => _busyMembers.remove(p.account));
    _toast(said);
  }

  void _removeMember(PendingMemberItem p) {
    if (_busyMembers.contains(p.account)) return;
    final name = p.displayName;
    showOrbitDialog(
      context,
      title: 'Remove $name?',
      text:
          '$name will be taken out of the group. The group key changes, so '
          'they cannot read anything new.',
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          'Remove',
          kind: OrbitButtonKind.danger,
          onPressed: () async {
            final run = widget.actions.onRemoveMember;
            if (run == null || !mounted) return;
            setState(() => _busyMembers.add(p.account));
            final said = await run(p.account);
            if (!mounted) return;
            setState(() => _busyMembers.remove(p.account));
            _toast(said);
          },
        ),
      ],
    );
  }

  Future<void> _call({required bool video}) async {
    final said = await widget.actions.onCall?.call(video: video);
    _toast(said);
  }

  // ------------------------------------------------------------ composer

  void _onFocus() {
    if (_focus.hasFocus && _emojiOpen) setState(() => _emojiOpen = false);
  }

  void _changed(String text, int cursor) {
    _typed = true;
    widget.actions.onTextChanged?.call(text, cursor);
  }

  Future<void> _send(String text) async {
    final send = widget.actions.onSend;
    if (send == null) {
      widget.actions.composer.onSend?.call(text);
      return;
    }
    final sent = await send(text);
    if (sent && mounted) _text.clear();
  }

  void _cancelBanner() {
    if (widget.model.banner?.kind == HelixComposerBannerKind.edit) {
      _text.clear();
    }
    (widget.actions.onCancelBanner ?? widget.actions.composer.onCancelBanner)
        ?.call();
  }

  void _pickMention(HelixPersonItem person) {
    final pick = widget.actions.onPickMention;
    if (pick == null) return;
    final next = pick(person, _text.text, _text.selection.baseOffset);
    _text.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursor),
    );
    _focus.requestFocus();
  }

  void _insertEmoji(String emoji) {
    final value = _text.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final next = value.text.replaceRange(start, end, emoji);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _changed(next, start + emoji.length);
  }

  void _toggleEmoji() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      setState(() => _emojiOpen = true);
    }
    widget.actions.composer.onEmoji?.call();
  }

  void _pick(ChatAttachSource source) =>
      widget.actions.onPickFiles?.call(source);

  /// The camera: a photo or a video (`cameraSheet()`).
  void _cameraSheet() {
    if (widget.actions.onPickFiles == null) {
      widget.actions.composer.onCamera?.call();
      return;
    }
    showOrbitSheet(
      context,
      items: [
        OrbitMenuItem(
          icon: OrbitIcons.camera,
          label: 'Take a photo',
          onTap: () => _pick(ChatAttachSource.cameraPhoto),
        ),
        OrbitMenuItem(
          icon: OrbitIcons.videoCamera,
          label: 'Record a video',
          onTap: () => _pick(ChatAttachSource.cameraVideo),
        ),
      ],
    );
  }

  void _attach() {
    final t = OrbitTokens.of(context);
    void chose(VoidCallback run) {
      Navigator.of(context).pop();
      Timer(const Duration(milliseconds: 80), () {
        if (mounted) run();
      });
    }

    Widget tile(OrbitGlyph icon, int colour, String label, VoidCallback run) {
      final (bg, ink) = OrbitAvatar.palette(t, colour);
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: () => chose(run),
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
      tile(
        OrbitIcons.fileText,
        3,
        'Document',
        () => _pick(ChatAttachSource.document),
      ),
      tile(OrbitIcons.camera, 5, 'Camera', _cameraSheet),
      tile(
        OrbitIcons.images,
        0,
        'Gallery',
        () => _pick(ChatAttachSource.gallery),
      ),
      tile(
        OrbitIcons.headphones,
        4,
        'Audio',
        () => _pick(ChatAttachSource.audio),
      ),
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

  // ------------------------------------------------------------ search

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query.clear();
    });
    widget.actions.onSearchQuery?.call('');
    if (!_atBottom) {
      // The list opens at the bottom again.
      _atBottom = true;
      _away = false;
      widget.actions.onAtBottomChanged?.call(true);
    }
  }

  void _pickHit(String messageId) {
    _closeSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.actions.onJumpTo?.call(messageId);
    });
  }

  // ------------------------------------------------------------ build

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
          children: [
            OrbitLoadFailed(
              title: 'This conversation could not be opened.',
              onRetry: _a.onRetryLoad,
            ),
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
    final c = _a.composer;
    final holds = _a.onVoiceStart != null;
    return PopScope(
      canPop: _selected.isEmpty && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected.isNotEmpty) {
          setState(_selected.clear);
        } else if (_searching) {
          _closeSearch();
        }
      },
      child: ColoredBox(
        color: t.bg,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t),
              if (!_searching && _selected.isEmpty)
                for (final p in m.pendingMembers)
                  _PendingCard(
                    p,
                    busy: _busyMembers.contains(p.account),
                    onConfirm: () => _confirmMember(p),
                    onRemove: () => _removeMember(p),
                  ),
              Expanded(child: body),
              if (showComposer)
                OrbitComposer(
                  controller: _text,
                  focusNode: _focus,
                  enterSends: m.enterSends,
                  banner: m.banner,
                  recording: m.recording,
                  recordingTime: m.recordingTime,
                  recordingWave: m.recordingWave,
                  disabled: m.composerDisabledReason,
                  disabledIcon: m.disabledIsBlock,
                  emojiOpen: _emojiOpen,
                  mentions: m.mentionCandidates,
                  attachKey: _attachKey,
                  actions: OrbitComposerActions(
                    onSend: _send,
                    onMic: holds
                        ? () => _toast(
                            'Hold the microphone to record a voice message.',
                          )
                        : c.onMic,
                    onAttach: _attach,
                    onCamera: _cameraSheet,
                    onEmoji: _toggleEmoji,
                    onCancelBanner: _cancelBanner,
                    onCancelRecording: holds
                        ? () => _a.onVoiceEnd?.call(send: false)
                        : c.onCancelRecording,
                    onSendRecording: holds
                        ? () => _a.onVoiceEnd?.call(send: true)
                        : c.onSendRecording,
                    onChanged: c.onChanged,
                    onTextChanged: _changed,
                    onMention: c.onMention,
                    onPickMention: _pickMention,
                    onVoiceStart: _a.onVoiceStart,
                    onVoiceSlide: _a.onVoiceSlide,
                    onVoiceLock: _a.onVoiceLock,
                    onVoiceEnd: _a.onVoiceEnd,
                  ),
                ),
              if (showComposer && _emojiOpen) _emojiPanel(t),
            ],
          ),
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
            onPressed: () {
              final ids = {..._selected};
              setState(_selected.clear);
              _copy(ids);
            },
          ),
          OrbitIconButton(
            icon: OrbitIcons.arrowBendUpRight,
            tooltip: 'Forward',
            color: t.onInverse,
            onPressed: () {
              final ids = {..._selected};
              setState(_selected.clear);
              _a.onForward?.call(ids);
            },
          ),
          OrbitIconButton(
            icon: OrbitIcons.trash,
            tooltip: 'Delete',
            color: t.onInverse,
            onPressed: () => _deleteForMe({..._selected}, clearSelection: true),
          ),
        ],
      );
    }
    if (_searching) {
      return OrbitAppBar(
        leadTooltip: 'Close search',
        onLead: _closeSearch,
        titleWidget: SizedBox(
          height: 44,
          child: OrbitSearchField(
            hint: 'Search this chat',
            controller: _query,
            autofocus: _a.onSearchQuery != null,
            onChanged: (value) {
              setState(() {});
              _a.onSearchQuery?.call(value);
            },
          ),
        ),
      );
    }
    final sub = m.subtitle;
    final scope = OrbitPaneScope.maybeOf(context);
    final detailRoot =
        scope != null && scope.root && scope.pane == OrbitPane.detail;
    final info = m.hasInfoPage ? _a.onOpenInfo : null;
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
                  onTap: info,
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
              onPressed: () => _call(video: true),
            ),
            OrbitIconButton(
              icon: OrbitIcons.phone,
              tooltip: 'Voice call',
              onPressed: () => _call(video: false),
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
              if (m.hasInfoPage)
                OrbitMenuItem(
                  icon: m.isGroup
                      ? OrbitIcons.usersThree
                      : OrbitIcons.userCircle,
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

  Widget _row(HelixTimelineItem item, bool group, bool selecting) {
    final id = item.id;
    final selected = _selected.contains(id);
    final shown = item is HelixMessageItem
        ? HelixMessageItem(
            item.message,
            position: item.position,
            selected: selected,
          )
        : item;
    final cached = _rows[id];
    if (cached != null &&
        cached.item == shown &&
        cached.group == group &&
        cached.selecting == selecting) {
      return cached.widget;
    }
    final widget = OrbitTimelineEntry(
      item: shown,
      group: group,
      onRetry: _retry,
      onTapMessage: _tapMessage,
      onLongPressMessage: _longPress,
      // While selecting, a touch anywhere on a message ticks it.
      bubble: selecting ? OrbitBubbleActions.none : _bubble,
    );
    _rows[id] = _CachedRow(shown, group, selecting, widget);
    return widget;
  }

  Widget _timeline(OrbitTokens t) {
    final m = widget.model;
    final list = _newestFirst();
    if (!identical(list, _rowsList)) {
      final ids = {for (final it in list) it.id};
      _rows.removeWhere((id, _) => !ids.contains(id));
    }
    _rowsList = list;
    final selecting = _selected.isNotEmpty;
    final indexOf = {for (final (i, it) in list.indexed) it.id: i};
    final toBottom = _away || m.hasNewer;
    return Stack(
      children: [
        Positioned.fill(
          child: OrbitPatternBackground(
            pattern: t.chatPattern,
            color: t.chatBg,
            child: LayoutBuilder(
              builder: (context, box) => ListView.builder(
                reverse: true,
                controller: _scroll,
                physics: _KeepVisiblePhysics(
                  anchor: () {
                    final keep = _keepPosition;
                    _keepPosition = false;
                    return keep;
                  },
                ),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: OrbitTimeline.paddingFor(box.maxWidth),
                itemCount: list.length,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? indexOf[key.value] : null,
                itemBuilder: (context, index) {
                  final item = list[index];
                  final id = item.id;
                  if (item is HelixMessageItem ||
                      item is HelixSystemNoticeItem) {
                    _noteDrawn(id);
                  }
                  final row = _row(item, m.isGroup, selecting);
                  if (id == _focusId && _focusKey != null) {
                    return KeyedSubtree(key: _focusKey, child: row);
                  }
                  return KeyedSubtree(key: ValueKey(id), child: row);
                },
              ),
            ),
          ),
        ),
        if (toBottom)
          Positioned(
            right: 14,
            bottom: 10,
            child: _ToLatest(unread: m.unreadCount, onTap: _toLatest),
          ),
      ],
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
    final given = m.searchHits;
    if (given != null && m.searchStatus == ListStatus.loading) {
      return ColoredBox(
        color: t.surface,
        child: Center(child: OrbitSpinner(size: 26, color: t.accent)),
      );
    }
    if (given != null && m.searchStatus == ListStatus.failed) {
      return ColoredBox(
        color: t.surface,
        child: ListView(
          children: const [
            OrbitLoadFailed(
              title: 'The search could not be run.',
              sub: '',
              retry: false,
            ),
          ],
        ),
      );
    }
    final hits = given ?? _localHits(q);
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 6),
        children: [
          for (final h in hits)
            _SearchHit(
              key: ValueKey('hit:${h.messageId}'),
              hit: h,
              onTap: () => _pickHit(h.messageId),
            ),
        ],
      ),
    );
  }

  /// The preview's search: the text messages of [ChatModel.items] holding
  /// [q], with the first match marked.
  List<ChatSearchHit> _localHits(String q) {
    final m = widget.model;
    return [
      for (final it in m.items)
        if (it is HelixMessageItem &&
            it.message.content is HelixTextContent &&
            (it.message.content as HelixTextContent).text
                .toLowerCase()
                .contains(q))
          _hitOf(it.message, q),
    ];
  }

  ChatSearchHit _hitOf(HelixMessage msg, String q) {
    final m = widget.model;
    final text = (msg.content as HelixTextContent).text;
    return ChatSearchHit(
      chatId: m.conversationId,
      messageId: msg.id,
      title: m.title,
      avatar: msg.outgoing
          ? const HelixAvatarModel(name: 'Hasan')
          : msg.authorName != null
          ? HelixAvatarModel(
              name: msg.authorName!,
              colorIndex: msg.authorColorIndex,
            )
          : m.avatar,
      timeLabel: msg.timeLabel,
      who: msg.outgoing ? 'You' : (msg.authorName ?? m.title.split(' ').first),
      text: HelixHighlightedText(text, [
        HelixTextRange(text.toLowerCase().indexOf(q), q.length),
      ]),
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _insertEmoji(e),
                    child: Center(
                      child: Text(e, style: t.font.style(size: 26)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CachedRow {
  const _CachedRow(this.item, this.group, this.selecting, this.widget);

  final HelixTimelineItem item;
  final bool group;
  final bool selecting;
  final Widget widget;
}

/// A clamping scroll that, when told to, keeps what the person is reading
/// where it is while messages are added below it. In a reversed list the
/// offset counts from the newest message, so a message arriving at the bottom
/// would push everything up; growing the offset by the same amount cancels it.
class _KeepVisiblePhysics extends ClampingScrollPhysics {
  const _KeepVisiblePhysics({super.parent, required this.anchor});

  /// Whether the next change of the list's size is messages arriving at the
  /// bottom. Reading it clears it.
  final bool Function() anchor;

  @override
  _KeepVisiblePhysics applyTo(ScrollPhysics? ancestor) =>
      _KeepVisiblePhysics(parent: buildParent(ancestor), anchor: anchor);

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final base = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    final grew = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;
    if (grew > 0 && !isScrolling && oldPosition.pixels > 60 && anchor()) {
      return base + grew;
    }
    return base;
  }
}

/// `.to-bottom`: "Scroll to latest message", 44px, corner 14, `--surface`
/// with a `--line` edge and `--shadow-float`, a bold caret in `--ink-2`; the
/// unread count as a 20px badge over its top right corner.
class _ToLatest extends StatelessWidget {
  const _ToLatest({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final label = unread > 0
        ? 'Scroll to latest message, $unread unread'
        : 'Scroll to latest message';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: OrbitTapArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: t.shadowFloat,
                  ),
                  child: Center(
                    child: OrbitIcon(
                      OrbitIcons.caretDown,
                      weight: OrbitIconWeight.bold,
                      size: 19,
                      color: t.ink2,
                    ),
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    top: -8,
                    right: -6,
                    child: Container(
                      height: 20,
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: t.mono.style(
                          size: 10,
                          weight: 600,
                          color: t.onAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.pending-card`: a member to confirm, amber: a filled shield 12px before
/// the title (weight 640), the explanation in `--ink-2`, and Confirm (and
/// Remove for an admin) as 38px buttons 10px under it. [busy] while an
/// answer is on its way: the buttons wait.
class _PendingCard extends StatelessWidget {
  const _PendingCard(
    this.p, {
    required this.busy,
    required this.onConfirm,
    required this.onRemove,
  });

  final PendingMemberItem p;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final text = t.font.style(
      size: OrbitType.small,
      color: t.ink2,
      height: 1.45,
    );
    return Semantics(
      container: true,
      label: p.title,
      child: Container(
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
                          onPressed: busy ? null : onConfirm,
                        ),
                        if (p.canRemove)
                          OrbitButton(
                            label: 'Remove',
                            kind: OrbitButtonKind.secondary,
                            height: 38,
                            padding: 16,
                            fontSize: 13,
                            onPressed: busy ? null : onRemove,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A message found by the in-chat search: who sent it (a 44px picture),
/// the time, and the text with the match in bold `--accent-ink`.
class _SearchHit extends StatelessWidget {
  const _SearchHit({super.key, required this.hit, required this.onTap});

  final ChatSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final base = t.font.style(size: OrbitType.small, color: t.ink3);
    final mark = base.copyWith(
      color: t.accentInk,
      fontWeight: FontWeight.w700,
      fontVariations: const [ui.FontVariation('wght', 700)],
    );
    final text = hit.text.text;
    final spans = <TextSpan>[];
    var at = 0;
    for (final r in hit.text.ranges) {
      final start = r.start.clamp(at, text.length);
      final end = (r.start + r.length).clamp(start, text.length);
      spans
        ..add(TextSpan(text: text.substring(at, start)))
        ..add(TextSpan(text: text.substring(start, end), style: mark));
      at = end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return InkWell(
      onTap: onTap,
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
              OrbitAvatar(avatar: hit.avatar, size: 44),
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
                            hit.who,
                            style: t.font.style(
                              size: OrbitType.headline,
                              weight: 600,
                              color: t.ink,
                              letterSpacingEm: -0.01,
                            ),
                          ),
                        ),
                        OrbitText(
                          hit.timeLabel,
                          style: t.mono.style(
                            size: OrbitType.meta,
                            color: t.ink3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    OrbitText.rich(TextSpan(children: spans), style: base),
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
    required this.currentReaction,
    required this.items,
    required this.onReact,
    required this.onMore,
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final bool group;
  final bool showReactions;
  final String? currentReaction;
  final List<(OrbitGlyph, String, bool, VoidCallback)> items;
  final ValueChanged<String> onReact;
  final VoidCallback onMore;

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
                                mine: currentReaction == e,
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
                              onTap: () {
                                close();
                                Timer(const Duration(milliseconds: 60), onMore);
                              },
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
                            for (final (icon, label, danger, run) in items)
                              Material(
                                type: MaterialType.transparency,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    close();
                                    run();
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
