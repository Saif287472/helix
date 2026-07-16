import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/add_contact_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.messagingService,
    required this.root,
  });

  final RemoteMessagingService messagingService;
  final RemoteCompositionRoot root;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<_ContactSearchEntry> _contacts = [];
  Map<String, RemoteContactRequest> _openRequestsByPeer = const {};
  int _pendingReceivedCount = 0;
  bool _loaded = false;
  bool _showSearch = false;
  String _searchQuery = '';
  String? _statusText;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<RemoteSyncChange>? _changeSub;

  @override
  void initState() {
    super.initState();
    _changeSub = widget.messagingService.changes.listen(_onRemoteChange);
    _reload();
  }

  void _onRemoteChange(RemoteSyncChange change) {
    if (!change.affects(RemoteSyncChangeArea.contacts)) return;
    _reload();
  }

  void _reload({String? statusText}) {
    try {
      final contacts = widget.messagingService.searchLocalContacts('');
      final requests = widget.messagingService.contactRequests();
      final openRequestsByPeer = <String, RemoteContactRequest>{};
      var pendingReceivedCount = 0;
      for (final request in requests) {
        if (request.status != 'Pending') continue;
        openRequestsByPeer.putIfAbsent(request.peerAccountId, () => request);
        if (request.direction == 'received') pendingReceivedCount++;
      }
      final entries = contacts
          .map((contact) => _ContactSearchEntry(contact))
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _contacts = entries;
          _openRequestsByPeer = openRequestsByPeer;
          _pendingReceivedCount = pendingReceivedCount;
          _loaded = true;
          if (statusText != null) _statusText = statusText;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          if (statusText != null) _statusText = statusText;
        });
      }
    }
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<_ContactSearchEntry> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    final q = _searchQuery.toLowerCase();
    return _contacts.where((entry) => entry.searchText.contains(q)).toList();
  }

  Future<void> _startConversation(RemoteContact contact) async {
    if (contact.status == 'PendingSent') {
      // Sync first — the other side may have already accepted
      await _sync();
      final updated = widget.messagingService
          .searchLocalContacts('')
          .where((c) => c.peerAccountId == contact.peerAccountId)
          .firstOrNull;
      if (updated == null || updated.status != 'Accepted') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Waiting for the other person to accept your request.',
              ),
            ),
          );
        }
        return;
      }
      // Fall through with the updated contact
      _openChat(updated);
      return;
    }
    if (contact.status != 'Accepted') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accept the request before opening a chat.'),
          ),
        );
      }
      return;
    }
    _openChat(contact);
  }

  void _openChat(RemoteContact contact) {
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
          attachmentService: _tryAttachmentService(),
          groupService: _tryGroupService(),
          callsAvailable: _tryCallsAvailable(),
        ),
      ),
    );
  }

  bool _tryCallsAvailable() {
    try {
      return widget.root.callsAvailable;
    } catch (_) {
      return false;
    }
  }

  RemoteAttachmentService? _tryAttachmentService() {
    try {
      return widget.root.attachmentService;
    } catch (_) {
      return null;
    }
  }

  RemoteGroupService? _tryGroupService() {
    try {
      return widget.root.groupService;
    } catch (_) {
      return null;
    }
  }

  void _acceptRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.acceptContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
        nickname: contact.nickname,
      );
      _reload(statusText: 'Contact request accepted');
    } catch (e) {
      _reload(statusText: '$e');
    }
  }

  void _rejectRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.rejectContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
      );
      _reload(statusText: 'Contact request rejected');
    } catch (e) {
      _reload(statusText: '$e');
    }
  }

  Future<void> _removeContact(RemoteContact contact) async {
    final name = contact.nickname.isNotEmpty
        ? contact.nickname
        : contact.peerAccountId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact'),
        content: Text('Remove $name from your contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      widget.messagingService.removeContact(contact.peerAccountId);
      _reload(statusText: 'Contact removed');
    } catch (e) {
      _reload(statusText: '$e');
    }
  }

  void _cancelRequest(RemoteContact contact, RemoteContactRequest request) {
    try {
      widget.messagingService.cancelContactRequest(
        requestId: request.requestId,
        peerAccountId: contact.peerAccountId,
      );
      _reload(statusText: 'Contact request cancelled');
    } catch (e) {
      _reload(statusText: '$e');
    }
  }

  Future<void> _sync() async {
    try {
      await widget.root.runtimeCoordinator.softSync();
    } catch (_) {}
    _reload();
  }

  Future<void> _addContact() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddContactScreen(
          root: widget.root,
          messagingService: widget.messagingService,
        ),
      ),
    );
    if (sent == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: cs.onPrimary),
                cursorColor: cs.onPrimary,
                decoration: InputDecoration(
                  hintText: 'Search contacts…',
                  hintStyle: TextStyle(color: cs.onPrimary.withAlpha(160)),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Text(
                'Contacts',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(Icons.sync, color: cs.onPrimary),
            onPressed: _sync,
            tooltip: 'Sync now',
          ),
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: cs.onPrimary,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            tooltip: _showSearch ? 'Close search' : 'Search',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pendingReceivedCount > 0)
            MaterialBanner(
              content: Text(
                '$_pendingReceivedCount pending contact request${_pendingReceivedCount == 1 ? '' : 's'}',
              ),
              actions: [
                TextButton(onPressed: () {}, child: const Text('View')),
              ],
            ),
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
          Expanded(child: _buildList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_contact_fab',
        onPressed: _addContact,
        tooltip: 'Add contact',
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  Widget _buildList() {
    final list = _filteredContacts;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No contacts match "$_searchQuery"'
                  : 'No contacts yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
      ),
      itemBuilder: (context, index) {
        final contact = list[index].contact;
        final request = _openRequestsByPeer[contact.peerAccountId];
        return ContactTile(
          contact: contact,
          request: request,
          onTap: () => _startConversation(contact),
          onAccept: request != null
              ? () => _acceptRequest(contact, request)
              : null,
          onReject: request != null
              ? () => _rejectRequest(contact, request)
              : null,
          onCancel: request != null
              ? () => _cancelRequest(contact, request)
              : null,
          onRemove: () => _removeContact(contact),
        );
      },
    );
  }
}

class _ContactSearchEntry {
  _ContactSearchEntry(this.contact)
    : searchText =
          '${contact.nickname.toLowerCase()} ${contact.peerAccountId.toLowerCase()}';

  final RemoteContact contact;
  final String searchText;
}
