import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/services/screen_security.dart';
import 'package:helix_remote/app/attachment_export.dart';
import 'package:helix_remote/app/attachment_safety.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/presentation/conversation/conversation_view_model.dart';
import 'package:helix_remote/screens/conversation/chat_palette.dart';
import 'package:helix_remote/screens/conversation/message_tile.dart';
import 'package:helix_remote/screens/contact_info_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote/l10n/helix_localizations.dart';

part 'conversation/app_bars.dart';
part 'conversation/attachment_actions.dart';
part 'conversation/body.dart';
part 'conversation/message_actions.dart';

typedef AttachmentFilePicker = Future<File?> Function();
typedef AttachmentFileExporter =
    Future<String?> Function(RemoteAttachmentContent attachment, File file);

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

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

class _ConversationScreenState extends State<ConversationScreen>
    with SecureScreenStateMixin {
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageKeys = <String, GlobalKey>{};
  late final ConversationViewModel _model;

  List<RemoteDecryptedMessage> get _messages => _model.messages;
  bool get _loaded => _model.loaded;
  bool get _loadingMore => _model.loadingMore;
  bool get _hasMore => _model.hasMore;
  String? get _errorMessage => _model.errorMessage;
  bool _searching = false;
  bool _typingActive = false;
  bool _attachmentBusy = false;
  String? _attachmentStatus;
  String? _highlightedMessageId;

  // Selection / reply state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  RemoteDecryptedMessage? _replyTo;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _model = ConversationViewModel(
      conversationId: widget.conversationId,
      messaging: widget.messagingService,
    )..addListener(_onModelChanged);
    unawaited(_model.load());
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 150;
    if (show != _showScrollToBottom) setState(() => _showScrollToBottom = show);
  }

  Future<void> _loadMessages({int? limit}) =>
      _model.load(query: _searching ? _searchController.text : '');

  Future<void> _refreshVisibleMessages() async {
    await _loadMessages();
  }

  Future<void> _loadMore() => _model.loadMore();

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

    try {
      await _model.sendText(text, replyTo: replyReference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotSendMessageTry,
            ),
          ),
        );
      }
    }
  }

  static String _snippet(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;

  void _update(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    _model
      ..removeListener(_onModelChanged)
      ..dispose();
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
    final displayName = _model.peerDisplayName ?? widget.conversationId;
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
        backgroundColor: conversationPalette(theme).page,
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
                        color: conversationPalette(theme).input,
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
