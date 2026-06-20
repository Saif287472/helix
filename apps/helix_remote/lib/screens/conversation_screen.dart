import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.messagingService,
  });

  final String conversationId;
  final RemoteMessagingService messagingService;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _controller = TextEditingController();
  List<RemoteDecryptedMessage> _messages = [];
  bool _loaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await widget.messagingService.messageHistory(
        widget.conversationId,
      );
      if (mounted) {
        setState(() {
          _messages = messages;
          _loaded = true;
          _errorMessage = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _errorMessage = 'Could not load messages. Tap to retry.';
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final deviceIds = widget.messagingService.recipientDeviceIdsForConversation(
      widget.conversationId,
    );
    await widget.messagingService.sendText(
      conversationId: widget.conversationId,
      plaintext: text,
      recipientDeviceIds: deviceIds,
    );
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.conversationId)),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInput(),
        ],
      ),
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
      return const Center(child: Text('No messages yet'));
    }
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[_messages.length - 1 - index];
        return _MessageTile(message: msg);
      },
    );
  }

  Widget _buildInput() {
    return Padding(
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
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _send,
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final RemoteDecryptedMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = false; // TODO: wire to local account ID
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                        children: message.reactions
                            .map((r) => Text(r))
                            .toList(),
                      ),
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

  String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
        return (Icons.schedule, Colors.grey, 'Pending');
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
        return 'Offline — messages will be sent when connected';
      case 'connecting':
        return 'Connecting…';
      case 'syncing':
        return 'Syncing…';
      case 'authRequired':
        return 'Sign in required';
      case 'retryScheduled':
        return 'Reconnecting…';
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
