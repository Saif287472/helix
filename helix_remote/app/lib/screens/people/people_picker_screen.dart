import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/add_contact_screen.dart';
import 'package:helix_remote/screens/people/people_search.dart';
import 'package:helix_remote/services/phone_contacts_service.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Who the picker returned, and what for.
class PeoplePickerResult {
  const PeoplePickerResult(this.person, this.action);

  final RemotePerson person;
  final PersonAction action;
}

/// "New chat" / "New call": everyone reachable, searchable by name or
/// number, with any number typed in usable directly - no contact request,
/// no need to save the number first.
class PeoplePickerScreen extends StatefulWidget {
  const PeoplePickerScreen({
    super.key,
    required this.root,
    required this.messagingService,
    this.forCalls = false,
    this.phoneContacts = const DevicePhoneContactsService(),
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;
  final bool forCalls;
  final PhoneContactsService phoneContacts;

  /// Opens the picker; resolves to the pick, or null when dismissed.
  static Future<PeoplePickerResult?> open(
    BuildContext context, {
    required RemoteCompositionRoot root,
    required RemoteMessagingService messagingService,
    bool forCalls = false,
  }) => Navigator.of(context).push<PeoplePickerResult>(
    MaterialPageRoute(
      builder: (_) => PeoplePickerScreen(
        root: root,
        messagingService: messagingService,
        forCalls: forCalls,
      ),
    ),
  );

  @override
  State<PeoplePickerScreen> createState() => _PeoplePickerScreenState();
}

class _PeoplePickerScreenState extends State<PeoplePickerScreen> {
  final _search = TextEditingController();
  StreamSubscription<RemoteSyncChange>? _changes;
  bool _syncing = false;
  String? _status;

  RemoteMessagingService get _ms => widget.messagingService;

  @override
  void initState() {
    super.initState();
    _changes = _ms.changes.listen((change) {
      if (change.affects(RemoteSyncChangeArea.contacts) && mounted) {
        setState(() {});
      }
    });
    // Keep the phone book fresh without making the user ask: once a day,
    // and on first use (which is when the permission is asked for).
    final last = _ms.unmatchedPhoneContactsSyncedAt();
    final stale =
        last == null ||
        DateTime.now().millisecondsSinceEpoch - last >
            const Duration(hours: 24).inMilliseconds;
    if (stale) unawaited(_syncPhoneBook(quiet: last != null));
    unawaited(widget.root.refreshPeopleProfiles());
  }

  @override
  void dispose() {
    _changes?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _syncPhoneBook({bool quiet = false}) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      if (!quiet) _status = 'Checking your phone contacts…';
    });
    try {
      final permission = await widget.phoneContacts.requestPermission();
      if (permission != PhoneContactsPermissionResult.granted) {
        if (mounted) {
          setState(
            () => _status =
                'Allow access to contacts to see who is on Helix. You can '
                'still type any number.',
          );
        }
        return;
      }
      final phoneBook = await widget.phoneContacts.loadContacts();
      final result = await widget.root.syncPhoneContacts(phoneBook);
      if (mounted) {
        setState(
          () => _status = result.isPartial
              ? 'Some contacts will be checked later.'
              : null,
        );
      }
    } catch (_) {
      if (mounted && !quiet) {
        setState(() => _status = 'Could not check your contacts right now.');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _scanOrLink() async {
    final accountId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AddContactScreen(
          root: widget.root,
          messagingService: _ms,
          initialTab: 2,
        ),
      ),
    );
    if (accountId == null || !mounted) return;
    _pick(
      _ms.person(accountId),
      widget.forCalls ? PersonAction.voiceCall : PersonAction.chat,
    );
  }

  void _pick(RemotePerson person, PersonAction action) {
    Navigator.of(context).pop(PeoplePickerResult(person, action));
  }

  @override
  Widget build(BuildContext context) {
    final count = _ms.people().where((p) => !p.isUnsaved).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.forCalls ? 'New call' : 'New chat'),
            Text(
              '$count ${count == 1 ? 'contact' : 'contacts'} on Helix',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh contacts',
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _syncing ? null : _syncPhoneBook,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const ValueKey('people-search'),
              controller: _search,
              autofocus: false,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'Search name or number',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _status!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (_search.text.isEmpty)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: const Icon(Icons.qr_code_scanner),
                    ),
                    title: const Text('Scan QR code or paste a link'),
                    onTap: _scanOrLink,
                  ),
                PeopleSearchResults(
                  root: widget.root,
                  messagingService: _ms,
                  query: _search.text,
                  forCalls: widget.forCalls,
                  onPick: _pick,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
