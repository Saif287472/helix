part of '../contacts_screen.dart';

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

/// A phone-book contact not (yet) registered on this Helix server, with an
/// action to invite them - the same "who's on Helix, who isn't" split
/// WhatsApp and the phone dialer app already show for their own contacts.
class _NotOnHelixTile extends StatelessWidget {
  const _NotOnHelixTile({required this.name, required this.onInvite});

  final String name;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.surfaceContainerHighest,
        child: Text(
          initial,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // No subtitle: these tiles only ever appear under the "Not on Helix
      // yet" section header, so a per-row "Not on Helix" repeated the
      // heading once for every contact and made a long list twice as tall
      // for no added information.
      title: Text(name, style: theme.textTheme.titleMedium),
      trailing: OutlinedButton(
        onPressed: onInvite,
        child: const Text('Invite'),
      ),
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
