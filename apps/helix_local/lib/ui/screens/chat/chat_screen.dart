// lib/ui/screens/chat/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:helix/ui/screens/media/audio_player_screen.dart';
import 'package:helix/ui/screens/media/video_player_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/core/identity_phrase.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';
import 'package:helix/ui/app_theme.dart';
import 'package:helix/ui/widgets/status_badge.dart';

part '_chat_message_bubble.dart';
part '_chat_widgets.dart';
part '_verify_identity_sheet.dart';
part '_chat_search.dart';
part '_chat_composer_actions.dart';
part '_chat_message_actions.dart';
part '_chat_thread_actions.dart';

// ---------------------------------------------------------------------------
// Emoji palette for reactions
// ---------------------------------------------------------------------------

const _kReactionEmoji = ['👍', '❤️', '😂', '😮', '😢', '👎'];

// Markdown trigger characters — any of these in the message means "try MD".
final _kMdPattern = RegExp(r'\*\*|\*|`|^###? |^- ', multiLine: true);

// URL pattern for tappable links (non-markdown messages).
final _kUrlPattern = RegExp(r'https?://\S+');

bool _sameMinute(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameBubbleGroup(ChatMessage a, ChatMessage b) =>
    !a.isSystem &&
    !b.isSystem &&
    a.origin == b.origin &&
    _sameMinute(a.timestamp, b.timestamp);

// ---------------------------------------------------------------------------
// ChatScreen
// ---------------------------------------------------------------------------

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId});
  final String threadId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

// ---------------------------------------------------------------------------
// Shared fields, lifecycle, and helpers used across the mixins below.
// ---------------------------------------------------------------------------

abstract class _ChatScreenBase extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _searchController = TextEditingController();
  bool _sending = false;
  bool _showScrollFab = false;
  int _lastMessageCount = 0;
  Timer? _qualityTimer;
  Timer? _typingDebounce;
  bool _typingSent = false;

  // Saved in initState so dispose() never touches ref after unmount.
  late final StateController<String?> _threadIdController;

  // Search
  bool _searchActive = false;
  String _searchQuery = '';
  List<int> _searchHitIndices = [];
  int _searchHitIndex = 0;

  /// Non-null while the user is composing a reply.
  ChatMessage? _replyTo;

  /// Keys for each message widget, used for quote tap-to-scroll.
  final Map<String, GlobalKey> _messageKeys = {};

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  void _scrollToMessage(String messageId) {
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _threadIdController = ref.read(currentChatThreadIdProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _threadIdController.state = widget.threadId;
    });
    _scrollController.addListener(_handleScroll);
    _qualityTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // Cancel timers first — before any state changes that could trigger callbacks.
    _qualityTimer?.cancel();
    _typingDebounce?.cancel();
    _scrollController.removeListener(_handleScroll);
    _threadIdController.state = null;
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int get _bytesRemaining =>
      kMaxMessageBytes - utf8.encode(_textController.text).length;

  bool get _canSend =>
      _textController.text.trim().isNotEmpty &&
      _bytesRemaining >= 0 &&
      !_sending;

  void _refocusComposer() {
    if (!isDesktop || !_focusNode.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final next = distance > 220;
    if (next != _showScrollFab && mounted) {
      setState(() => _showScrollFab = next);
    }
  }
}

// ---------------------------------------------------------------------------
// _ChatScreenState — composes the mixins above and implements build().
// ---------------------------------------------------------------------------

class _ChatScreenState extends _ChatScreenBase
    with
        _ChatSearchMixin,
        _ChatComposerMixin,
        _ChatMessageActionsMixin,
        _ChatThreadActionsMixin {
  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(threadByIdProvider(widget.threadId));
    final messagingService = ref.read(messagingServiceProvider);
    final theme = Theme.of(context);

    if (thread == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Thread not found.')),
      );
    }

    final isActive = thread.status == ThreadStatus.active;
    final supportsCalls =
        messagingService.getChannel(widget.threadId)?.supportsCapability(
          kCapWebRTC,
        ) ??
        false;
    final hasActiveCall = ref.watch(currentCallProvider).value != null;
    final canStartCall = isActive && supportsCalls && !hasActiveCall;
    final hasConnectivity =
        ref.watch(hasConnectivityProvider).value ?? true;
    final isAtCapacity = messagingService.isAtCapacity(widget.threadId);
    final peerTyping =
        ref.watch(peerTypingProvider(widget.threadId)).value ?? false;
    final avatarTag = thread.peerSessionId.isEmpty
        ? 'peer-avatar-${thread.peerHost}:${thread.peerPort}'
        : 'peer-avatar-${thread.peerSessionId}';

    ref.watch(knownPeersProvider);
    final trustService = ref.read(trustServiceProvider);
    final peerName = trustService.displayNameFor(
      thread.peerStaticKeyFingerprint,
      thread.peerDisplayName,
    );
    final isTrustedPeer = trustService.isTrusted(
      thread.peerStaticKeyFingerprint,
    );

    if (thread.unreadCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(messagingServiceProvider).markThreadRead(widget.threadId);
        }
      });
    }

    if (isActive) _sendReadReceipts(thread);

    final currentCount = thread.messages.length;
    if (currentCount > _lastMessageCount) {
      _lastMessageCount = currentCount;
      _scrollToBottom();
    }

    final appBarTitle = _searchActive
        ? TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search messages…',
              border: InputBorder.none,
              suffixText: _searchHitIndices.isEmpty
                  ? (_searchQuery.isEmpty ? null : '0 results')
                  : '${_searchHitIndex + 1} / ${_searchHitIndices.length}',
            ),
            onChanged: (q) => _updateSearch(thread.messages, q),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Hero(
                    tag: avatarTag,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primary.withAlpha(30),
                      child: Text(
                        thread.peerDisplayName.isNotEmpty
                            ? thread.peerDisplayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isTrustedPeer) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_user,
                            size: 14,
                            color: Colors.teal,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${thread.peerDeviceSuffix} • ${isActive ? 'secure session' : 'offline'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    final appBarActions = _searchActive
        ? [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous result',
              onPressed: _searchHitIndices.isEmpty
                  ? null
                  : () => _navigateSearch(thread.messages, forward: false),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next result',
              onPressed: _searchHitIndices.isEmpty
                  ? null
                  : () => _navigateSearch(thread.messages, forward: true),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchActive = false;
                  _searchQuery = '';
                  _searchHitIndices = [];
                  _searchHitIndex = 0;
                });
              },
            ),
          ]
        : [
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: supportsCalls
                  ? 'Voice call'
                  : 'Peer does not support calls yet',
              onPressed: canStartCall
                  ? () => ref
                        .read(callServiceProvider)
                        .initiateCall(widget.threadId, peerName)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.videocam),
              tooltip: supportsCalls
                  ? 'Video call'
                  : 'Peer does not support calls yet',
              onPressed: canStartCall
                  ? () => ref
                        .read(callServiceProvider)
                        .initiateVideoCall(widget.threadId, peerName)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About this chat',
              onPressed: _showInfoDialog,
            ),
            PopupMenuButton<String>(
              tooltip: 'Chat options',
              onSelected: (value) {
                switch (value) {
                  case 'search':
                    setState(() => _searchActive = true);
                  case 'verify':
                    _showVerifyIdentitySheet(thread);
                  case 'export':
                    _exportThread(thread);
                  case 'end':
                    _endConnection();
                  case 'clear':
                    _clearThread();
                  case 'close':
                    _closeThread();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18),
                      SizedBox(width: 10),
                      Text('Search messages'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'verify',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Verify identity'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Export…'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'end',
                  child: Row(
                    children: [
                      Icon(Icons.link_off, size: 18),
                      SizedBox(width: 10),
                      Text('Disconnect session'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Clear local thread'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text(
                        'Delete local chat',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: appBarTitle,
        actions: appBarActions,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                children: [
                  if (isAtCapacity)
                    _WarningBanner(
                      icon: Icons.storage_outlined,
                      message:
                          'Thread is at capacity. Clear the thread to continue.',
                    ),
                  if (!isActive)
                    _WarningBanner(
                      icon: hasConnectivity
                          ? Icons.link_off
                          : Icons.wifi_off_outlined,
                      message: hasConnectivity
                          ? 'Offline. You can reconnect when the peer is available.'
                          : 'No internet connection. Reconnecting automatically when network is restored.',
                      action: hasConnectivity
                          ? FilledButton.tonal(
                              onPressed: () => _sendNewRequest(thread),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('Reconnect'),
                            )
                          : null,
                    ),
                  Expanded(
                    child: thread.messages.isEmpty && !peerTyping
                        ? Center(
                            child: Text(
                              isActive
                                  ? 'No messages yet.'
                                  : 'No local messages in this thread.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(
                                  120,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                            itemCount:
                                thread.messages.length +
                                (thread.hasNewSessionSeparator ? 1 : 0) +
                                (peerTyping ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (thread.hasNewSessionSeparator && i == 0) {
                                return const SessionSeparatorChip();
                              }
                              final offset = thread.hasNewSessionSeparator
                                  ? 1
                                  : 0;
                              if (peerTyping &&
                                  i == thread.messages.length + offset) {
                                return _TypingBubble(
                                  peerInitial: thread.peerDisplayName.isNotEmpty
                                      ? thread.peerDisplayName[0].toUpperCase()
                                      : 'P',
                                );
                              }
                              final msgIdx = i - offset;
                              final msg = thread.messages[msgIdx];
                              ChatMessage? replySource;
                              if (msg.replyToMessageId != null) {
                                replySource = thread.messages
                                    .where(
                                      (m) =>
                                          m.messageId == msg.replyToMessageId,
                                    )
                                    .firstOrNull;
                              }
                              final previous = msgIdx > 0
                                  ? thread.messages[msgIdx - 1]
                                  : null;
                              final next = msgIdx < thread.messages.length - 1
                                  ? thread.messages[msgIdx + 1]
                                  : null;
                              final showDateDivider =
                                  previous == null ||
                                  !_sameDay(msg.timestamp, previous.timestamp);
                              final groupedWithPrevious =
                                  previous != null &&
                                  _sameBubbleGroup(previous, msg);
                              final groupedWithNext =
                                  next != null && _sameBubbleGroup(msg, next);
                              final isSearchHit =
                                  _searchQuery.isNotEmpty &&
                                  _searchHitIndices.isNotEmpty &&
                                  _searchHitIndices[_searchHitIndex] == msgIdx;
                              return Column(
                                key: _keyFor(msg.messageId),
                                children: [
                                  if (showDateDivider)
                                    _TimestampDivider(
                                      timestamp: msg.timestamp,
                                    ),
                                  _MessageSendAnimation(
                                    messageId: msg.messageId,
                                    child: _MessageBubble(
                                      message: msg,
                                      peerInitial: thread
                                              .peerDisplayName.isNotEmpty
                                          ? thread.peerDisplayName[0]
                                                .toUpperCase()
                                          : 'P',
                                      peerDisplayName: thread.peerDisplayName,
                                      showAvatar: !groupedWithPrevious,
                                      groupedWithPrevious: groupedWithPrevious,
                                      groupedWithNext: groupedWithNext,
                                      showMeta: !groupedWithNext,
                                      replySource: replySource,
                                      searchQuery: _searchQuery,
                                      isSearchHit: isSearchHit,
                                      onLongPress: () =>
                                          _showContextMenu(msg),
                                      onReplySwipe: () {
                                        setState(() => _replyTo = msg);
                                        _focusNode.requestFocus();
                                      },
                                      onQuoteTap: msg.replyToMessageId != null
                                          ? () => _scrollToMessage(
                                              msg.replyToMessageId!,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  if (_replyTo != null)
                    _ReplyBar(
                      message: _replyTo!,
                      onDismiss: () => setState(() => _replyTo = null),
                    ),
                  _Composer(
                    controller: _textController,
                    focusNode: _focusNode,
                    disabled: !isActive || isAtCapacity,
                    bytesRemaining: _bytesRemaining,
                    sending: _sending,
                    canSend: _canSend,
                    onSend: () => _sendMessage(thread),
                    onChanged: _onTextChanged,
                    onAttach: isActive ? () => _pickAndSendFile(thread) : null,
                    onAttachPrivateMedia: isActive
                        ? () => _pickAndSendPrivateMediaNow(thread)
                        : null,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 88,
              child: AnimatedScale(
                scale: _showScrollFab ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: FloatingActionButton.small(
                  tooltip: 'Jump to latest',
                  onPressed: _scrollToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
