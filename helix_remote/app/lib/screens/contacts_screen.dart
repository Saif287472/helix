import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/add_contact_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote/services/phone_contacts_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.messagingService,
    required this.root,
    this.phoneContactsService,
  });

  final RemoteMessagingService messagingService;
  final RemoteCompositionRoot root;

  /// Overridable for tests; defaults to the real OS phone-book reader.
  final PhoneContactsService? phoneContactsService;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<_ContactSearchEntry> _contacts = [];
  Map<String, RemoteContactRequest> _openRequestsByPeer = const {};
  int _pendingReceivedCount = 0;
  bool _loaded = false;
  bool _showSearch = false;
  bool _syncingContacts = false;
  bool _syncBannerDismissed = false;
  String _searchQuery = '';
  String? _statusText;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<RemoteSyncChange>? _changeSub;

  PhoneContactsService get _phoneContactsService =>
      widget.phoneContactsService ?? const DevicePhoneContactsService();

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
          .map(
            (contact) => _ContactSearchEntry(
              contact,
              phoneBookName: widget.messagingService.phoneBookNameFor(
                contact.peerAccountId,
              ),
            ),
          )
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

  /// Matched phone-book contacts that aren't a Helix contact (in any
  /// status) yet - shown as suggestions at the top of the list. Sourced
  /// from the persisted phone-book overrides table, so a match survives
  /// app restarts rather than only lasting until the next sync.
  List<_PhoneBookSuggestion> get _phoneBookSuggestions {
    if (_searchQuery.isNotEmpty) return const [];
    final knownPeerIds = _contacts.map((e) => e.contact.peerAccountId).toSet();
    final overrides = widget.messagingService.phoneContactOverrides();
    return overrides.entries
        .where((e) => !knownPeerIds.contains(e.key))
        .map(
          (e) => _PhoneBookSuggestion(accountId: e.key, phoneBookName: e.value),
        )
        .toList(growable: false);
  }

  Future<void> _runContactsSync() async {
    if (_syncingContacts) return;
    setState(() {
      _syncingContacts = true;
      _syncBannerDismissed = true;
    });
    try {
      final permission = await _phoneContactsService.requestPermission();
      if (permission != PhoneContactsPermissionResult.granted) {
        if (mounted) {
          setState(() {
            _syncingContacts = false;
            _statusText = 'Contacts permission not granted';
          });
        }
        return;
      }
      final phoneBook = await _phoneContactsService.loadContacts();
      final matches = await widget.root.syncPhoneContacts(phoneBook);
      if (!mounted) return;
      // recordPhoneContactMatches() (called inside syncPhoneContacts) emits
      // a contacts-area change, which _onRemoteChange picks up and reloads -
      // this just adds the status message on top of that reload.
      _reload(
        statusText: matches.isEmpty
            ? 'No phone contacts found on Helix'
            : '${matches.length} phone contact${matches.length == 1 ? '' : 's'} found on Helix',
      );
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Contacts sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncingContacts = false);
    }
  }

  Future<void> _addFromPhoneBook(_PhoneBookSuggestion suggestion) async {
    try {
      widget.messagingService.sendContactRequest(
        peerAccountId: suggestion.accountId,
        nickname: suggestion.phoneBookName,
      );
      _reload(
        statusText: 'Contact request sent to ${suggestion.phoneBookName}',
      );
    } catch (e) {
      _reload(statusText: '$e');
    }
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
            icon: _syncingContacts
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : Icon(Icons.contacts_outlined, color: cs.onPrimary),
            onPressed: _syncingContacts ? null : _runContactsSync,
            tooltip: 'Sync phone contacts',
          ),
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
          if (!_syncBannerDismissed && !_syncingContacts)
            MaterialBanner(
              content: const Text(
                'Find contacts already on Helix? Phone numbers are hashed '
                'before comparison and never sent in the clear.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _syncBannerDismissed = true),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: _runContactsSync,
                  child: const Text('Sync contacts'),
                ),
              ],
            ),
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
    final suggestions = _phoneBookSuggestions;
    if (list.isEmpty && suggestions.isEmpty) {
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

    final items = <Widget>[];
    if (suggestions.isNotEmpty) {
      items.add(_buildSectionHeader('From your phone book'));
      for (final suggestion in suggestions) {
        items.add(
          _PhoneBookSuggestionTile(
            suggestion: suggestion,
            onAdd: () => _addFromPhoneBook(suggestion),
          ),
        );
      }
      if (list.isNotEmpty) items.add(_buildSectionHeader('Contacts'));
    }
    for (final entry in list) {
      items.add(_buildContactTile(entry));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
      ),
      itemBuilder: (context, index) => items[index],
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: cs.primary),
      ),
    );
  }

  Widget _buildContactTile(_ContactSearchEntry entry) {
    final contact = entry.contact;
    final request = _openRequestsByPeer[contact.peerAccountId];
    final override = entry.phoneBookName;
    final displayContact = (override != null && override.isNotEmpty)
        ? RemoteContact(
            peerAccountId: contact.peerAccountId,
            nickname: override,
            status: contact.status,
          )
        : contact;
    return ContactTile(
      contact: displayContact,
      request: request,
      onTap: () => _startConversation(contact),
      onAccept: request != null ? () => _acceptRequest(contact, request) : null,
      onReject: request != null ? () => _rejectRequest(contact, request) : null,
      onCancel: request != null ? () => _cancelRequest(contact, request) : null,
      onRemove: () => _removeContact(contact),
    );
  }
}

class _PhoneBookSuggestion {
  const _PhoneBookSuggestion({
    required this.accountId,
    required this.phoneBookName,
  });

  final String accountId;
  final String phoneBookName;
}

class _PhoneBookSuggestionTile extends StatelessWidget {
  const _PhoneBookSuggestionTile({
    required this.suggestion,
    required this.onAdd,
  });

  final _PhoneBookSuggestion suggestion;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial = suggestion.phoneBookName.isEmpty
        ? '?'
        : suggestion.phoneBookName.substring(0, 1).toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Text(
          initial,
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        suggestion.phoneBookName,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text('Found via phone contacts'),
      trailing: FilledButton(onPressed: onAdd, child: const Text('Add')),
    );
  }
}

class _ContactSearchEntry {
  _ContactSearchEntry(this.contact, {this.phoneBookName})
    : searchText =
          '${contact.nickname.toLowerCase()} '
          '${contact.peerAccountId.toLowerCase()} '
          '${(phoneBookName ?? '').toLowerCase()}';

  final RemoteContact contact;
  final String? phoneBookName;
  final String searchText;
}
