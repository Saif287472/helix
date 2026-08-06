import 'package:helix_remote/services/app_logger.dart';
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
import 'package:share_plus/share_plus.dart';

part 'contacts/widgets.dart';

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

  /// Phone-book contacts that had a valid number but matched no Helix
  /// account - i.e. not registered on this server (yet).
  ///
  /// Read from storage, not from the last sync's return value. Holding it
  /// in state alone meant leaving the tab threw the list away and it had to
  /// be re-synced by hand to see it again. Names that have since joined are
  /// not accumulated: every complete sync rewrites the stored list, so
  /// someone who joined drops out of it on the next refresh.
  List<String> _unmatchedPhoneBookNames = const [];
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<RemoteSyncChange>? _changeSub;

  PhoneContactsService get _phoneContactsService =>
      widget.phoneContactsService ?? const DevicePhoneContactsService();

  /// How stale the stored "not on Helix yet" list may get before opening
  /// the tab quietly refreshes it.
  static const Duration _unmatchedRefreshInterval = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _changeSub = widget.messagingService.changes.listen(_onRemoteChange);
    _reload();
    // Post-frame, not inline: _runContactsSync() calls setState before its
    // first await, so starting it here directly would mark the element
    // dirty while it is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoRefresh();
    });
  }

  /// Rebuilds the stored list in the background when it has gone stale, so
  /// someone who joined Helix stops being offered an Invite button without
  /// anyone having to press sync.
  ///
  /// Gated on a previous complete sync (`syncedAt != null`). That is what
  /// proves contacts permission was granted before, so re-requesting it
  /// returns immediately rather than raising a dialog the user did not ask
  /// for. Without the gate, merely opening this tab would prompt for access
  /// to the phone book.
  ///
  /// Affordable because the server caches match results against a
  /// phone-book fingerprint: an unchanged phone book re-syncs without
  /// spending any of the daily discovery budget.
  void _maybeAutoRefresh() {
    final syncedAt = widget.messagingService.unmatchedPhoneContactsSyncedAt();
    if (syncedAt == null) return;
    final age = DateTime.now().millisecondsSinceEpoch - syncedAt;
    if (age < _unmatchedRefreshInterval.inMilliseconds) return;
    unawaited(_runContactsSync());
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
      final unmatched = widget.messagingService.unmatchedPhoneContacts();
      if (mounted) {
        setState(() {
          _contacts = entries;
          _openRequestsByPeer = openRequestsByPeer;
          _pendingReceivedCount = pendingReceivedCount;
          _unmatchedPhoneBookNames = unmatched;
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
      final result = await widget.root.syncPhoneContacts(phoneBook);
      if (!mounted) return;
      // The unmatched list is not taken from the result: a complete sync has
      // already written it to storage, and _reload() below reads it back
      // from there. A partial sync deliberately writes nothing, so the
      // previous list stays rather than being replaced by a view that
      // cannot tell "not on Helix" from "never looked up".
      final matchCount = result.matches.length;
      final unmatchedCount = result.unmatchedNames.length;
      // recordPhoneContactMatches() (called inside syncPhoneContacts) emits
      // a contacts-area change, which _onRemoteChange picks up and reloads -
      // this just adds the status message on top of that reload.
      // A sync stopped by the server's daily discovery budget is a partial
      // success, not a failure: the matches found so far are already
      // applied, so say what got done and when the rest can run, rather
      // than reporting a count that looks complete.
      _reload(
        statusText: result.isPartial
            ? '$matchCount on Helix so far — the rest will sync '
                  '${_retryWhen(result.retryAfter)}'
            : matchCount == 0 && unmatchedCount == 0
            ? 'No phone contacts found on Helix'
            : '$matchCount on Helix, $unmatchedCount not yet',
      );
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Contacts sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncingContacts = false);
    }
  }

  /// Human phrasing for when a budget-limited sync can continue. "tomorrow"
  /// rather than a timestamp because the window is a rolling 24h and the
  /// exact minute is not something a user acts on.
  String _retryWhen(Duration? retryAfter) {
    if (retryAfter == null) return 'later';
    if (retryAfter.inHours >= 1) return 'in ${retryAfter.inHours}h';
    if (retryAfter.inMinutes >= 1) return 'in ${retryAfter.inMinutes} min';
    return 'shortly';
  }

  /// Shares a generic invite message via the OS share sheet (SMS, WhatsApp,
  /// email, etc. - whatever the user picks). It deliberately doesn't embed
  /// a working invite link or code: this server is invite-gated and only an
  /// admin can mint invite codes (via the admin console's Invites tab) -
  /// a regular account has no API access to generate one itself.
  Future<void> _inviteContact(String name) async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            "Hey $name, I'm using Helix Remote - it's private, "
            'self-hosted messaging. Ask me for an invite and download the '
            'app to join!',
      ),
    );
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
    } catch (e) {
      AppLogger.instance.warn('contacts', 'sync failed: \$e');
    }
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

  /// Unmatched phone-book names, filtered by the search query rather than
  /// hidden by it.
  ///
  /// These used to disappear entirely as soon as anything was typed, on the
  /// grounds that they are not Helix contacts. But searching for someone in
  /// order to invite them is one of the main reasons to look here at all,
  /// and with a long list scrolling is not a substitute.
  List<String> get _unmatchedForDisplay {
    if (_searchQuery.isEmpty) return _unmatchedPhoneBookNames;
    final q = _searchQuery.toLowerCase();
    return _unmatchedPhoneBookNames
        .where((name) => name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Widget _buildList() {
    final list = _filteredContacts;
    final suggestions = _phoneBookSuggestions;
    final unmatched = _unmatchedForDisplay;
    if (list.isEmpty && suggestions.isEmpty && unmatched.isEmpty) {
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
    if (unmatched.isNotEmpty) {
      items.add(_buildSectionHeader('Not on Helix yet'));
      for (final name in unmatched) {
        items.add(
          _NotOnHelixTile(name: name, onInvite: () => _inviteContact(name)),
        );
      }
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
