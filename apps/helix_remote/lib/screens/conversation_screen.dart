import 'package:flutter/material.dart';
import '../app/remote_messaging_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await widget.messagingService.messageHistory(
      widget.conversationId,
    );
    setState(() {
      _messages = messages;
      _loaded = true;
    });
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
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(child: Text('No messages'))
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[_messages.length - 1 - index];
                      return ListTile(
                        title: Text(msg.text),
                        subtitle: Text(msg.status),
                        trailing: Text(
                          DateTime.fromMillisecondsSinceEpoch(
                            msg.timestamp,
                          ).toString().substring(11, 16),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
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
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
