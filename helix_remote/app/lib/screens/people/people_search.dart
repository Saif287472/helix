import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:share_plus/share_plus.dart';

/// What the user picked someone for.
enum PersonAction { chat, voiceCall, videoCall }

/// Whether a search reads like a phone number (so "Message +880…" is offered).
bool looksLikePhoneNumber(String query) {
  final digits = query.replaceAll(RegExp(r'[^\d]'), '');
  return digits.length >= 6 &&
      RegExp(r'^[\d\s+()\-.]+$').hasMatch(query.trim());
}

String _initials(String name) {
  final clean = name.replaceAll('~', '').trim();
  if (clean.isEmpty || clean.startsWith('+')) return '#';
  final parts = clean.split(RegExp(r'\s+'));
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts[1].characters.first : '';
  return (first + second).toUpperCase();
}

/// Round initials avatar used by the people lists.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.radius = 22});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = HelixColorTokens.avatarPalette;
    final color = palette[name.hashCode.abs() % palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: ExcludeSemantics(
        child: Text(
          _initials(name),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The people part of a search: a "Message/Call this number" row when the
/// query is a number, the people who match, and phone contacts not on Helix
/// yet (to invite). Shared by the new-chat/new-call picker and the search in
/// the Chats and Calls tabs.
class PeopleSearchResults extends StatefulWidget {
  const PeopleSearchResults({
    super.key,
    required this.root,
    required this.messagingService,
    required this.query,
    required this.onPick,
    this.forCalls = false,
    this.excludeAccountIds = const {},
    this.showHeader = true,
    this.showInvites = true,
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;
  final String query;
  final bool forCalls;
  final Set<String> excludeAccountIds;
  final bool showHeader;
  final bool showInvites;
  final void Function(RemotePerson person, PersonAction action) onPick;

  @override
  State<PeopleSearchResults> createState() => _PeopleSearchResultsState();
}

class _PeopleSearchResultsState extends State<PeopleSearchResults> {
  bool _lookingUp = false;

  RemoteMessagingService get _ms => widget.messagingService;

  Future<void> _useNumber(String number, PersonAction action) async {
    if (_lookingUp) return;
    setState(() => _lookingUp = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final person = await widget.root.findPersonByPhone(number);
      if (!mounted) return;
      if (person != null) {
        widget.onPick(person, action);
        return;
      }
      final normalized = RemoteAccountValidation.normalizePhoneNumber(number);
      final invite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not on Helix'),
          content: Text('$normalized is not using Helix yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Invite'),
            ),
          ],
        ),
      );
      if (invite == true) await _invite(normalized);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not look up that number. Check your connection and try '
            'again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _invite(String name) => SharePlus.instance.share(
    ShareParams(
      text:
          'Hey $name, I use Helix for private, encrypted messages and calls. '
          'Get the app and message me there!',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = widget.query.trim();
    final lower = query.toLowerCase();
    final digits = query.replaceAll(RegExp(r'[^\d]'), '');
    final people = _ms
        .people()
        .where((p) => !widget.excludeAccountIds.contains(p.accountId))
        .where(
          (p) =>
              lower.isEmpty ||
              p.searchText.contains(lower) ||
              (digits.length >= 3 &&
                  (p.phoneNumber ?? '')
                      .replaceAll(RegExp(r'[^\d]'), '')
                      .contains(digits)),
        )
        .toList();
    final invites = widget.showInvites
        ? _ms
              .unmatchedPhoneContacts()
              .where(
                (name) => lower.isEmpty || name.toLowerCase().contains(lower),
              )
              .take(lower.isEmpty ? 50 : 20)
              .toList()
        : const <String>[];
    final isNumber = looksLikePhoneNumber(query);
    final number = RemoteAccountValidation.normalizePhoneNumber(query);
    final numberKnown = people.any((p) => p.phoneNumber == number);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isNumber && !numberKnown)
          ListTile(
            key: const ValueKey('use-number'),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                widget.forCalls ? Icons.call : Icons.chat,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            title: Text(widget.forCalls ? 'Call $number' : 'Message $number'),
            subtitle: const Text('Not in your contacts'),
            trailing: _lookingUp
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () => _useNumber(
              query,
              widget.forCalls ? PersonAction.voiceCall : PersonAction.chat,
            ),
          ),
        if (people.isNotEmpty && widget.showHeader)
          header(lower.isEmpty ? 'Contacts on Helix' : 'Contacts'),
        for (final person in people)
          _PersonTile(
            person: person,
            forCalls: widget.forCalls,
            onPick: (action) => widget.onPick(person, action),
          ),
        if (invites.isNotEmpty) header('Invite to Helix'),
        for (final name in invites)
          ListTile(
            leading: PersonAvatar(name: name),
            title: Text(name),
            trailing: TextButton(
              onPressed: () => _invite(name),
              child: const Text('Invite'),
            ),
          ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.forCalls,
    required this.onPick,
  });

  final RemotePerson person;
  final bool forCalls;
  final void Function(PersonAction action) onPick;

  @override
  Widget build(BuildContext context) {
    final subtitle = person.isUnsaved
        ? (person.name == person.phoneNumber
              ? person.helixLabel
              : person.phoneNumber)
        : (person.phoneNumber ?? person.helixLabel);
    return ListTile(
      leading: PersonAvatar(name: person.name),
      title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () =>
          onPick(forCalls ? PersonAction.voiceCall : PersonAction.chat),
      trailing: forCalls
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Voice call ${person.name}',
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => onPick(PersonAction.voiceCall),
                ),
                IconButton(
                  tooltip: 'Video call ${person.name}',
                  icon: const Icon(Icons.videocam_outlined),
                  onPressed: () => onPick(PersonAction.videoCall),
                ),
              ],
            )
          : null,
    );
  }
}
