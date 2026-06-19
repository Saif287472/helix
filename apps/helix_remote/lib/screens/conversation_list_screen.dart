import 'package:flutter/material.dart';
import 'package:helix_remote_domain/models.dart';
import '../app/remote_messaging_service.dart';
import '../app/composition_root.dart';
import 'conversation_screen.dart';
import 'settings_screen.dart';

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({
    super.key,
    required this.messagingService,
    required this.root,
  });

  final RemoteMessagingService messagingService;
  final RemoteCompositionRoot root;

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  late List<RemoteConversation> _conversations;
  List<RemoteContact> _contacts = [];
  bool _loaded = false;
  bool _showContacts = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    try {
      final convos = widget.messagingService.conversationList();
      final contacts = widget.messagingService.searchLocalContacts('');
      setState(() {
        _conversations = convos;
        _contacts = contacts;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('ConversationListScreen._reload error: $e');
      setState(() => _loaded = true);
    }
  }

  void _addContact() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Peer account ID',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final peer = controller.text.trim();
              if (peer.isNotEmpty) {
                widget.messagingService.sendContactRequest(peerAccountId: peer);
                Navigator.pop(ctx);
                _reload();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _startConversation(RemoteContact contact) {
    final convId = widget.messagingService.createDirectConversation(
      peerAccountId: contact.peerAccountId,
      title: contact.nickname.isNotEmpty
          ? contact.nickname
          : contact.peerAccountId,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: convId,
          messagingService: widget.messagingService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helix Remote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  root: widget.root,
                  messagingService: widget.messagingService,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_showContacts ? Icons.chat : Icons.people),
            onPressed: () => setState(() => _showContacts = !_showContacts),
          ),
        ],
      ),
      body: _showContacts ? _buildContactList() : _buildConversationList(),
      floatingActionButton: _showContacts
          ? FloatingActionButton(
              onPressed: _addContact,
              child: const Icon(Icons.person_add),
            )
          : FloatingActionButton(
              onPressed: _reload,
              child: const Icon(Icons.refresh),
            ),
    );
  }

  Widget _buildConversationList() {
    if (_conversations.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }
    return ListView.builder(
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conv = _conversations[index];
        return ListTile(
          title: Text(conv.title),
          subtitle: Text(conv.conversationId),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                conversationId: conv.conversationId,
                messagingService: widget.messagingService,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactList() {
    if (_contacts.isEmpty) {
      return const Center(child: Text('No contacts yet'));
    }
    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return ListTile(
          title: Text(
            contact.nickname.isNotEmpty
                ? contact.nickname
                : contact.peerAccountId,
          ),
          subtitle: Text(contact.status),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _startConversation(contact),
        );
      },
    );
  }
}
