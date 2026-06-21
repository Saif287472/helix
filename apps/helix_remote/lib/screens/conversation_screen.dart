import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/attachment_export.dart';
import 'package:helix_remote/app/attachment_safety.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

typedef AttachmentFilePicker = Future<File?> Function();
typedef AttachmentFileExporter =
    Future<String?> Function(RemoteAttachmentContent attachment, File file);

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.messagingService,
    this.attachmentService,
    this.pickAttachmentFile,
    this.exportAttachmentFile,
  });

  final String conversationId;
  final RemoteMessagingService messagingService;
  final RemoteAttachmentService? attachmentService;
  final AttachmentFilePicker? pickAttachmentFile;
  final AttachmentFileExporter? exportAttachmentFile;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const _pageSize = 50;

  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _receiptMarked = <String>{};

  List<RemoteDecryptedMessage> _messages = [];
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _searching = false;
  bool _typingActive = false;
  bool _attachmentBusy = false;
  String? _errorMessage;
  String? _attachmentStatus;
  StreamSubscription<RemoteSyncChange>? _changeSub;

  @override
  void initState() {
    super.initState();
    _changeSub = widget.messagingService.changes.listen(_onRemoteChange);
    _loadMessages();
  }

  void _onRemoteChange(RemoteSyncChange change) {
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
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _publishTyping(false);
    try {
      final deviceIds = widget.messagingService
          .recipientDeviceIdsForConversation(widget.conversationId);
      await widget.messagingService.sendText(
        conversationId: widget.conversationId,
        plaintext: text,
        recipientDeviceIds: deviceIds,
      );
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
  }

  Future<void> _attachFile() async {
    final attachmentService = widget.attachmentService;
    if (attachmentService == null || _attachmentBusy) return;
    String? attachmentId;
    try {
      final selected =
          await (widget.pickAttachmentFile ?? _pickAttachmentFile)();
      if (selected == null) return;
      if (!mounted) return;
      setState(() {
        _attachmentBusy = true;
        _attachmentStatus = 'Preparing attachment';
      });

      final prepared = await attachmentService.prepareAttachment(selected);
      attachmentId = prepared['attachment_id'] as String;
      final ciphertextPath = prepared['ciphertext_path'] as String;
      if (!mounted) return;
      setState(() => _attachmentStatus = 'Uploading attachment');

      await attachmentService.uploadAttachment(
        attachmentId: attachmentId,
        ciphertextPath: ciphertextPath,
      );

      final manifest = RemoteAttachmentManifest(
        fileId: attachmentId,
        fileSize: prepared['size_bytes'] as int,
        fileHash: prepared['file_hash'] as String,
        mimeType: _inferMimeType(selected.path),
      );
      final recipientDeviceIds = widget.messagingService
          .recipientDeviceIdsForConversation(widget.conversationId);
      if (!mounted) return;
      setState(() => _attachmentStatus = 'Queueing attachment message');
      final messageId = await widget.messagingService.sendAttachment(
        conversationId: widget.conversationId,
        manifest: manifest,
        filename: prepared['filename'] as String,
        keyDeliverySecret: prepared['key_delivery_secret'] as String,
        recipientDeviceIds: recipientDeviceIds,
      );
      await attachmentService.registerReference(
        fileId: attachmentId,
        messageId: messageId,
      );
      if (!mounted) return;
      setState(() => _attachmentStatus = 'Attachment queued');
      await _loadMessages();
    } catch (e) {
      if (attachmentId != null) {
        attachmentService.updateAttachmentStatus(attachmentId, 'FAILED');
      }
      if (mounted) {
        setState(() => _attachmentStatus = 'Attachment failed');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Attachment failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<File?> _pickAttachmentFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Select attachment',
      lockParentWindow: true,
    );
    final path = file?.path;
    if (path == null || path.isEmpty) return null;
    return File(path);
  }

  Future<void> _downloadAttachment(RemoteAttachmentContent attachment) async {
    final attachmentService = widget.attachmentService;
    if (attachmentService == null || _attachmentBusy) return;
    final proceed = await _confirm(
      title: 'Open attachment?',
      message: RemoteAttachmentSafety.malwareWarningMessage,
      confirmLabel: 'Download',
    );
    if (!proceed) return;
    try {
      setState(() {
        _attachmentBusy = true;
        _attachmentStatus = 'Downloading attachment';
      });
      await attachmentService.importAttachmentKeyFromMessage(
        manifest: attachment.manifest,
        filename: attachment.filename,
        keyDeliverySecret: attachment.keyDeliverySecret,
      );
      await attachmentService.downloadAttachment(
        attachmentId: attachment.fileId,
        savePath: p.join(
          attachmentService.tempDir.path,
          '${attachment.fileId}.download.enc',
        ),
      );
      if (!mounted) return;
      setState(() => _attachmentStatus = 'Attachment downloaded');
      await _refreshVisibleMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _attachmentStatus = 'Attachment download failed');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _exportAttachment(RemoteAttachmentContent attachment) async {
    final attachmentService = widget.attachmentService;
    final path = attachment.localPath;
    if (attachmentService == null || path == null || _attachmentBusy) return;
    final source = File(path);
    if (!source.existsSync()) return;
    final proceed = await _confirm(
      title: 'Export decrypted file?',
      message: RemoteAttachmentExport.exportWarningMessage,
      confirmLabel: 'Export',
    );
    if (!proceed) return;
    try {
      final exportedPath =
          await (widget.exportAttachmentFile ?? _exportAttachmentFile)(
            attachment,
            source,
          );
      if (exportedPath == null) return;
      attachmentService.markAttachmentExported(
        attachmentId: attachment.fileId,
        exportedPlaintextPath: exportedPath,
      );
      if (!mounted) return;
      setState(() => _attachmentStatus = 'Attachment exported');
      await _refreshVisibleMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<String?> _exportAttachmentFile(
    RemoteAttachmentContent attachment,
    File file,
  ) {
    return FilePicker.saveFile(
      dialogTitle: 'Export decrypted attachment',
      fileName: attachment.filename,
      bytes: Uint8List.fromList(file.readAsBytesSync()),
      lockParentWindow: true,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _publishTyping(bool isTyping) async {
    if (_typingActive == isTyping) return;
    _typingActive = isTyping;
    try {
      await widget.messagingService.publishTyping(
        conversationId: widget.conversationId,
        isTyping: isTyping,
      );
    } catch (_) {
      // Typing is ephemeral. Messaging must keep working if signaling is down.
    }
  }

  void _markVisibleReceipts(List<RemoteDecryptedMessage> messages) {
    final currentAccountId = widget.messagingService.currentAccountId;
    if (currentAccountId == null) return;
    for (final message in messages) {
      if (message.senderAccountId == currentAccountId) continue;
      if (!_receiptMarked.add(message.messageId)) continue;
      unawaited(
        widget.messagingService.markDelivered(
          messageId: message.messageId,
          conversationId: message.conversationId,
        ),
      );
      unawaited(
        widget.messagingService.markRead(
          messageId: message.messageId,
          conversationId: message.conversationId,
        ),
      );
    }
  }

  Future<void> _editMessage(RemoteDecryptedMessage message) async {
    var draft = message.text;
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draft.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null || updated.isEmpty || updated == message.text) return;
    await widget.messagingService.editMessage(
      messageId: message.messageId,
      conversationId: message.conversationId,
      plaintext: updated,
    );
    await _loadMessages();
  }

  Future<void> _addReaction(RemoteDecryptedMessage message) async {
    widget.messagingService.addReaction(
      messageId: message.messageId,
      reaction: '+1',
    );
    await _loadMessages();
  }

  Future<void> _deleteForSelf(RemoteDecryptedMessage message) async {
    widget.messagingService.deleteForSelf(message.messageId);
    await _loadMessages();
  }

  Future<void> _deleteForEveryone(RemoteDecryptedMessage message) async {
    widget.messagingService.deleteForEveryone(
      messageId: message.messageId,
      conversationId: message.conversationId,
    );
    await _loadMessages();
  }

  void _blockPeer() {
    final current = widget.messagingService.currentAccountId;
    final peer = widget.messagingService
        .conversationMemberIds(widget.conversationId)
        .where((memberId) => memberId != current)
        .firstOrNull;
    if (peer == null) return;
    widget.messagingService.blockContact(peer);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$peer blocked')));
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    unawaited(_publishTyping(false));
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversationId),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                }
              });
              _loadMessages();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') {
                _blockPeer();
              } else if (value == 'refresh') {
                _loadMessages();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              PopupMenuItem(value: 'block', child: Text('Block contact')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching) _buildSearchField(),
          if (!_searching && _hasMore) _buildLoadEarlierButton(),
          if (_attachmentStatus != null) _buildAttachmentBanner(),
          Expanded(child: _buildMessageList()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search this conversation',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => _loadMessages(),
      ),
    );
  }

  Widget _buildLoadEarlierButton() {
    return TextButton.icon(
      onPressed: _loadingMore ? null : _loadMore,
      icon: _loadingMore
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.expand_less),
      label: const Text('Load earlier messages'),
    );
  }

  Widget _buildMessageList() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: GestureDetector(
          onTap: _loadMessages,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(_searching ? 'No matching messages' : 'No messages yet'),
      );
    }
    final currentAccountId = widget.messagingService.currentAccountId;
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[_messages.length - 1 - index];
        return _MessageTile(
          message: msg,
          currentAccountId: currentAccountId,
          onEdit: () => _editMessage(msg),
          onReact: () => _addReaction(msg),
          onDeleteSelf: () => _deleteForSelf(msg),
          onDeleteEveryone: () => _deleteForEveryone(msg),
          onDownloadAttachment: msg.attachment == null
              ? null
              : () => _downloadAttachment(msg.attachment!),
          onExportAttachment: msg.attachment == null
              ? null
              : () => _exportAttachment(msg.attachment!),
        );
      },
    );
  }

  Widget _buildAttachmentBanner() {
    return MaterialBanner(
      content: Text(_attachmentStatus!),
      actions: [
        TextButton(
          onPressed: () => setState(() => _attachmentStatus = null),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _publishTyping(value.trim().isNotEmpty),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.attachmentService != null) ...[
              IconButton(
                icon: _attachmentBusy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
                onPressed: _attachmentBusy ? null : _attachFile,
                tooltip: 'Attach file',
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _send,
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }

  String _inferMimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.currentAccountId,
    required this.onEdit,
    required this.onReact,
    required this.onDeleteSelf,
    required this.onDeleteEveryone,
    required this.onDownloadAttachment,
    required this.onExportAttachment,
  });

  final RemoteDecryptedMessage message;
  final String? currentAccountId;
  final VoidCallback onEdit;
  final VoidCallback onReact;
  final VoidCallback onDeleteSelf;
  final VoidCallback onDeleteEveryone;
  final VoidCallback? onDownloadAttachment;
  final VoidCallback? onExportAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.senderAccountId == currentAccountId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(child: _buildMessageBody(theme)),
                      PopupMenuButton<String>(
                        tooltip: 'Message actions',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onEdit();
                              break;
                            case 'react':
                              onReact();
                              break;
                            case 'delete_self':
                              onDeleteSelf();
                              break;
                            case 'delete_everyone':
                              onDeleteEveryone();
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                            value: 'react',
                            child: Text('React +1'),
                          ),
                          PopupMenuItem(
                            value: 'delete_self',
                            child: Text('Delete for me'),
                          ),
                          PopupMenuItem(
                            value: 'delete_everyone',
                            child: Text('Delete for everyone'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _MessageStatusChip(status: message.status),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.edited)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'edited',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Text(message.text),
        if (message.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              children: message.reactions.map((r) => Text(r)).toList(),
            ),
          ),
        if (message.attachment != null)
          _AttachmentCard(
            attachment: message.attachment!,
            onDownload: onDownloadAttachment,
            onExport: onExportAttachment,
          ),
      ],
    );
  }

  String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.onDownload,
    required this.onExport,
  });

  final RemoteAttachmentContent attachment;
  final VoidCallback? onDownload;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final downloaded =
        attachment.localStatus == 'DOWNLOADED' && attachment.localPath != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.filename),
                Text(
                  '${_formatBytes(attachment.fileSize)} - '
                  '${attachment.localStatus ?? 'Not downloaded'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (downloaded)
            IconButton(
              tooltip: 'Export attachment',
              icon: const Icon(Icons.save_alt),
              onPressed: onExport,
            )
          else
            IconButton(
              tooltip: 'Download attachment',
              icon: const Icon(Icons.download),
              onPressed: onDownload,
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

// P4-06: Minimal production UI status indicator for every known message state.
class _MessageStatusChip extends StatelessWidget {
  const _MessageStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resolve(status);
    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }

  (IconData, Color, String) _resolve(String status) {
    switch (status) {
      case 'PENDING':
        return (Icons.schedule, Colors.grey, 'Queued');
      case 'SENT':
        return (Icons.done, Colors.blue, 'Sent');
      case 'DELIVERED':
        return (Icons.done_all, Colors.blue, 'Delivered');
      case 'READ':
        return (Icons.done_all, Colors.green, 'Read');
      case 'RETRYING':
        return (Icons.autorenew, Colors.orange, 'Retrying');
      case 'FAILED':
        return (Icons.error_outline, Colors.red, 'Failed to send');
      case 'SECURE_SESSION_UNAVAILABLE':
        return (Icons.lock_open, Colors.red, 'Secure session unavailable');
      case 'EDITED':
        return (Icons.edit, Colors.grey, 'Edited');
      case 'DELETED':
        return (Icons.delete_outline, Colors.grey, 'Deleted');
      case 'TOMBSTONED':
        return (Icons.delete_forever, Colors.grey, 'Deleted for everyone');
      case 'OFFLINE':
        return (Icons.cloud_off, Colors.grey, 'Offline');
      case 'KEY_CHANGED':
        return (Icons.warning_amber, Colors.orange, 'Safety key changed');
      case 'REVOKED_DEVICE':
        return (Icons.no_accounts, Colors.red, 'Device revoked');
      default:
        return (Icons.help_outline, Colors.grey, status);
    }
  }
}

// P4-06: Runtime coordinator state banner shown above the message list.
class RemoteRuntimeStateBanner extends StatelessWidget {
  const RemoteRuntimeStateBanner({super.key, required this.stateLabel});

  final String stateLabel;

  static String? bannerTextFor(String state) {
    switch (state) {
      case 'offline':
        return 'Offline - messages will be sent when connected';
      case 'connecting':
        return 'Connecting...';
      case 'syncing':
        return 'Syncing...';
      case 'authRequired':
        return 'Sign in required';
      case 'retryScheduled':
        return 'Reconnecting...';
      case 'degraded':
        return 'Connection degraded';
      case 'failed':
        return 'Connection failed';
      case 'ready':
      case 'disposed':
        return null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = bannerTextFor(stateLabel);
    if (text == null) return const SizedBox.shrink();
    return Material(
      color: Colors.orange.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
