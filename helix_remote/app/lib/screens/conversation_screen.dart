import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/attachment_export.dart';
import 'package:helix_remote/app/attachment_safety.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/contact_info_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

part 'conversation/app_bars.dart';
part 'conversation/attachment_actions.dart';
part 'conversation/body.dart';
part 'conversation/message_actions.dart';
part 'conversation/message_tile.dart';

typedef AttachmentFilePicker = Future<File?> Function();
typedef AttachmentFileExporter =
    Future<String?> Function(RemoteAttachmentContent attachment, File file);

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

class _ChatPalette {
  const _ChatPalette({
    required this.page,
    required this.appBar,
    required this.onAppBar,
    required this.inputBar,
    required this.input,
    required this.incoming,
    required this.outgoing,
    required this.incomingTime,
    required this.outgoingTime,
    required this.dateChip,
    required this.dateChipText,
    required this.accent,
    required this.readTick,
  });

  final Color page;
  final Color appBar;
  final Color onAppBar;
  final Color inputBar;
  final Color input;
  final Color incoming;
  final Color outgoing;
  final Color incomingTime;
  final Color outgoingTime;
  final Color dateChip;
  final Color dateChipText;
  final Color accent;
  final Color readTick;
}

_ChatPalette _chatPalette(ThemeData theme) {
  final cs = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  if (dark) {
    return _ChatPalette(
      page: const Color(0xFF0B1417),
      appBar: const Color(0xFF0B1114),
      onAppBar: Colors.white,
      inputBar: const Color(0xFF0B1417),
      input: const Color(0xFF1F2C34),
      incoming: const Color(0xFF1F2C34),
      outgoing: const Color(0xFF005C4B),
      incomingTime: const Color(0xFF98A4AA),
      outgoingTime: const Color(0xFFB8D5C8),
      dateChip: const Color(0xE61C252B),
      dateChipText: const Color(0xFFD7DEE2),
      accent: const Color(0xFF00A884),
      readTick: const Color(0xFF53BDEB),
    );
  }
  return _ChatPalette(
    page: const Color(0xFFEDE7DE),
    appBar: cs.surface,
    onAppBar: cs.onSurface,
    inputBar: const Color(0xFFEDE7DE),
    input: Colors.white,
    incoming: Colors.white,
    outgoing: const Color(0xFFD9FFD2),
    incomingTime: const Color(0xFF667781),
    outgoingTime: const Color(0xFF667781),
    dateChip: const Color(0xF7FFFFFF),
    dateChipText: const Color(0xFF667781),
    accent: const Color(0xFF00A884),
    readTick: const Color(0xFF34B7F1),
  );
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.messagingService,
    this.attachmentService,
    this.pickAttachmentFile,
    this.exportAttachmentFile,
    this.groupService,
    this.callsAvailable = false,
    this.onStartAudioCall,
    this.onStartVideoCall,
  });

  final String conversationId;
  final RemoteMessagingService messagingService;
  final RemoteAttachmentService? attachmentService;
  final AttachmentFilePicker? pickAttachmentFile;
  final AttachmentFileExporter? exportAttachmentFile;
  final RemoteGroupService? groupService;
  final bool callsAvailable;
  final VoidCallback? onStartAudioCall;
  final VoidCallback? onStartVideoCall;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const _pageSize = 50;

  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _receiptMarked = <String>{};
  final _messageKeys = <String, GlobalKey>{};

  List<RemoteDecryptedMessage> _messages = [];
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _searching = false;
  bool _typingActive = false;
  bool _attachmentBusy = false;
  String? _errorMessage;
  String? _attachmentStatus;
  String? _highlightedMessageId;
  StreamSubscription<RemoteSyncChange>? _changeSub;

  // Selection / reply state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  RemoteDecryptedMessage? _replyTo;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _changeSub = widget.messagingService.changes.listen(_onRemoteChange);
    _loadMessages();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 150;
    if (show != _showScrollToBottom) setState(() => _showScrollToBottom = show);
  }

  void _onRemoteChange(RemoteSyncChange change) {
    // Contact updates can change the display name shown in the app bar.
    if (change.affects(RemoteSyncChangeArea.contacts)) {
      if (mounted) setState(() {});
      return;
    }
    if (!change.affectsConversation(widget.conversationId)) return;
    if (!change.affects(RemoteSyncChangeArea.messages) &&
        !change.affects(RemoteSyncChangeArea.conversations)) {
      return;
    }
    unawaited(_refreshVisibleMessages());
  }

  Future<void> _loadMessages({int? limit}) async {
    try {
      final effectiveLimit = limit ?? _pageSize;
      final messages = _searching && _searchController.text.trim().isNotEmpty
          ? await widget.messagingService.searchDecryptedHistory(
              conversationId: widget.conversationId,
              query: _searchController.text.trim(),
            )
          : await widget.messagingService.messageHistory(
              widget.conversationId,
              limit: effectiveLimit,
            );
      if (mounted) {
        setState(() {
          _messages = messages;
          _loaded = true;
          _hasMore = !_searching && messages.length == _pageSize;
          _errorMessage = null;
        });
      }
      _markVisibleReceipts(messages);
      widget.messagingService.markConversationRead(widget.conversationId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _errorMessage = 'Could not load messages. Tap to retry.';
        });
      }
    }
  }

  Future<void> _refreshVisibleMessages() async {
    final visibleLimit = _messages.length > _pageSize
        ? _messages.length
        : _pageSize;
    await _loadMessages(limit: visibleLimit);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _searching) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = await widget.messagingService.messageHistory(
        widget.conversationId,
        limit: _pageSize,
        offset: _messages.length,
      );
      if (mounted) {
        setState(() {
          _messages = [..._messages, ...nextPage];
          _hasMore = nextPage.length == _pageSize;
        });
      }
      _markVisibleReceipts(nextPage);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    unawaited(_publishTyping(false));

    final reply = _replyTo;
    final replyReference = reply == null
        ? null
        : RemoteReplyReference(
            messageId: reply.messageId,
            senderAccountId: reply.senderAccountId,
            snippet: _snippet(reply.text),
          );
    setState(() => _replyTo = null);

    final tempId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
    final accountId = widget.messagingService.currentAccountId ?? '';
    final optimistic = RemoteDecryptedMessage(
      messageId: tempId,
      conversationId: widget.conversationId,
      senderAccountId: accountId,
      senderDeviceId: '',
      text: text,
      status: 'PENDING',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      replyTo: replyReference,
    );
    setState(() => _messages = [optimistic, ..._messages]);

    final deviceIds = widget.messagingService.recipientDeviceIdsForConversation(
      widget.conversationId,
    );
    widget.messagingService
        .sendText(
          conversationId: widget.conversationId,
          plaintext: text,
          recipientDeviceIds: deviceIds,
          replyTo: replyReference,
        )
        .catchError((Object e, StackTrace _) {
          if (mounted) {
            setState(
              () => _messages = _messages
                  .where((m) => m.messageId != tempId)
                  .toList(),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not send message. Try again.'),
              ),
            );
          }
          return '';
        });
  }

  static String _snippet(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;

  void _update(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    _changeSub?.cancel();
    unawaited(_publishTyping(false));
    _scrollController.dispose();
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayName =
        widget.messagingService.peerDisplayName(widget.conversationId) ??
        widget.conversationId;
    final initials = displayName.isEmpty
        ? '?'
        : displayName
              .substring(0, displayName.length.clamp(1, 2))
              .toUpperCase();

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelectionMode();
      },
      child: Scaffold(
        backgroundColor: _chatPalette(theme).page,
        appBar: _selectionMode
            ? _buildSelectionAppBar(cs)
            : _buildNormalAppBar(cs, displayName, initials),
        body: Column(
          children: [
            if (_searching) _buildSearchField(),
            if (_attachmentStatus != null) _buildAttachmentBanner(),
            Expanded(
              child: Stack(
                children: [
                  _buildMessageList(),
                  if (_showScrollToBottom)
                    Positioned(
                      right: 18,
                      bottom: 16,
                      child: Material(
                        color: _chatPalette(theme).input,
                        elevation: 3,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          ),
                          child: SizedBox.square(
                            dimension: 50,
                            child: Icon(
                              Icons.keyboard_double_arrow_down,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_replyTo != null) _buildReplyPreview(cs),
            _buildInput(),
          ],
        ),
      ),
    );
  }
}
