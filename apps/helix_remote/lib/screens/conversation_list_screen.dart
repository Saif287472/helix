import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote/screens/settings_screen.dart';
import 'package:helix_remote_domain/models.dart';

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
  List<RemoteContactRequest> _requests = [];
  bool _loaded = false;
  bool _showContacts = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    try {
      final convos = widget.messagingService.conversationList();
      final contacts = widget.messagingService.searchLocalContacts('');
      final requests = widget.messagingService.contactRequests();
      setState(() {
        _conversations = convos;
        _contacts = contacts;
        _requests = requests;
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
                try {
                  widget.messagingService.sendContactRequest(
                    peerAccountId: peer,
                  );
                  setState(() => _statusText = 'Contact request sent');
                } catch (e) {
                  setState(() => _statusText = _safeError(e));
                }
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
    if (contact.status != 'Accepted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accept the contact request before opening a chat.'),
        ),
      );
      return;
    }
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

  void _acceptRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.acceptContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
        nickname: contact.nickname,
      );
      setState(() => _statusText = 'Contact request accepted');
    } catch (e) {
      setState(() => _statusText = _safeError(e));
    }
    _reload();
  }

  void _rejectRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.rejectContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
      );
      setState(() => _statusText = 'Contact request rejected');
    } catch (e) {
      setState(() => _statusText = _safeError(e));
    }
    _reload();
  }

  void _cancelRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.cancelContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
      );
      setState(() => _statusText = 'Contact request cancelled');
    } catch (e) {
      setState(() => _statusText = _safeError(e));
    }
    _reload();
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
      body: Column(
        children: [
          if (_statusText != null)
            MaterialBanner(
              content: Text(_statusText!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _statusText = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: _showContacts
                ? _buildContactList()
                : _buildConversationList(),
          ),
        ],
      ),
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
        final request = _openRequestFor(contact);
        return ListTile(
          title: Text(
            contact.nickname.isNotEmpty
                ? contact.nickname
                : contact.peerAccountId,
          ),
          subtitle: Text(contact.status),
          trailing: _contactTrailing(contact, request),
          onTap: () => _startConversation(contact),
        );
      },
    );
  }

  RemoteContactRequest? _openRequestFor(RemoteContact contact) {
    for (final request in _requests) {
      if (request.peerAccountId == contact.peerAccountId &&
          request.status == 'Pending') {
        return request;
      }
    }
    return null;
  }

  Widget _contactTrailing(
    RemoteContact contact,
    RemoteContactRequest? request,
  ) {
    if (contact.status == 'PendingReceived' && request != null) {
      return Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Accept request',
            icon: const Icon(Icons.check),
            onPressed: () => _acceptRequest(contact, request),
          ),
          IconButton(
            tooltip: 'Reject request',
            icon: const Icon(Icons.close),
            onPressed: () => _rejectRequest(contact, request),
          ),
        ],
      );
    }
    if (contact.status == 'PendingSent' && request != null) {
      return TextButton(
        onPressed: () => _cancelRequest(contact, request),
        child: const Text('Cancel'),
      );
    }
    if (contact.status == 'Accepted') {
      return const Icon(Icons.chevron_right);
    }
    return Text(contact.status);
  }

  String _safeError(Object error) {
    final text = error.toString();
    if (text.startsWith('Bad state: ')) {
      return text.substring('Bad state: '.length);
    }
    return 'Contact operation failed';
  }
}
