import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_failures.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What tapping a person in the search does.
enum PeopleSearchMode {
  /// Open (or start) the conversation. The Chats tab.
  chats,

  /// Start a voice call, with a button for video. The Calls tab.
  calls,
}

/// People search, for the Chats and Calls tabs to mount under their search
/// field. There is no Contacts tab: this is where a person is found.
///
/// ```dart
/// // The tab owns the field and the text; this draws the results.
/// HelixSearchField(controller: c, onChanged: setState...,
///     onSubmitted: (text) => PeopleSearchPanel.submit(ref, text));
/// PeopleSearchPanel(query: c.text, mode: PeopleSearchMode.chats)
/// ```
///
/// With nothing typed it lists the people the user already knows on Helix
/// (the phone's contacts that have accounts, and anyone they named), after
/// asking - once, with an explanation - to read the contacts. Typing filters
/// people and groups on this device as you type, with no network. A phone
/// number or `~name` is looked up on the server **only when the person asks**
/// (the "Find" row, or the keyboard's search key), because each number lookup
/// spends one of 5,000 daily lookups and tells the server which number was
/// asked about.
///
/// A search result opens the chat (Chats) or places a call (Calls); a long
/// press opens the person's contact info.
class PeopleSearchPanel extends ConsumerWidget {
  const PeopleSearchPanel({
    super.key,
    required this.query,
    this.mode = PeopleSearchMode.chats,
    this.embedded = false,
  });

  /// What the search box holds.
  final String query;
  final PeopleSearchMode mode;

  /// Drawn inside another scrolling list (the Chats search puts it between the
  /// chat and message results): the rows are a plain column that does not
  /// scroll, and nothing is drawn while it loads.
  final bool embedded;

  /// The keyboard's search key: run the network lookup the text asks for (a
  /// number or a `~name`). Nothing else on screen needs it.
  static void submit(WidgetRef ref, String text) {
    final parsed = PeopleQuery.parse(
      text,
      callingCode: ref.read(ownCallingCodeProvider).value,
    );
    ref.read(peopleLookupProvider.notifier).lookUp(parsed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(peopleSearchProvider(query));
    final parsed = PeopleQuery.parse(
      query,
      callingCode: ref.watch(ownCallingCodeProvider).value,
    );
    final lookup = ref.watch(peopleLookupProvider);
    final permission = ref.watch(contactsPermissionProvider).value;
    final sync = ref.watch(phoneBookSyncProvider);

    return results.when(
      loading: () =>
          embedded ? const SizedBox.shrink() : const HelixChatListSkeleton(),
      error: (_, _) => embedded
          ? const SizedBox.shrink()
          : const HelixErrorState(
              message: 'People could not be loaded. Open the app again to try.',
            ),
      data: (found) {
        final answered =
            lookup.status != LookupStatus.idle && lookup.answers(parsed);
        final rows = <_Row>[
          if (parsed.isBrowse) ...[
            if (permission != null &&
                permission != ContactsPermission.granted &&
                permission != ContactsPermission.unsupported)
              _Row.permission(permission),
            if (permission == ContactsPermission.granted) _Row.refresh(sync),
          ],
          if (parsed.intent == SearchIntent.phone || parsed.canLookUp)
            _Row.lookupPrompt(parsed),
          // A person the lookup found is stored at once, so the list below
          // shows them too; the answer row is for what the list cannot show.
          if (answered &&
              !(lookup.person != null &&
                  found.people.any(
                    (p) => p.accountId == lookup.person!.accountId,
                  )))
            _Row.lookupResult(lookup),
          if (found.groups.isNotEmpty) ...[
            const _Row.header('Groups'),
            for (final group in found.groups) _Row.group(group),
          ],
          if (found.people.isNotEmpty) ...[
            _Row.header(parsed.isBrowse ? 'People on Helix' : 'People'),
            for (final person in found.people) _Row.person(person),
          ],
          if (found.isEmpty && !(answered && lookup.person != null))
            _Row.empty(parsed),
        ];
        if (embedded) {
          return Column(
            children: [for (final row in rows) _RowView(row: row, mode: mode)],
          );
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) =>
              _RowView(row: rows[index], mode: mode),
        );
      },
    );
  }
}

enum _Kind {
  header,
  permission,
  refresh,
  lookupPrompt,
  lookupResult,
  group,
  person,
  empty,
}

final class _Row {
  const _Row._(
    this.kind, {
    this.title,
    this.permission,
    this.sync,
    this.query,
    this.lookup,
    this.group,
    this.person,
  });

  const _Row.header(String title) : this._(_Kind.header, title: title);
  const _Row.permission(ContactsPermission permission)
    : this._(_Kind.permission, permission: permission);
  const _Row.refresh(PhoneBookSyncState sync)
    : this._(_Kind.refresh, sync: sync);
  const _Row.lookupPrompt(PeopleQuery query)
    : this._(_Kind.lookupPrompt, query: query);
  const _Row.lookupResult(LookupState lookup)
    : this._(_Kind.lookupResult, lookup: lookup);
  const _Row.group(GroupSummary group) : this._(_Kind.group, group: group);
  const _Row.person(PersonName person) : this._(_Kind.person, person: person);
  const _Row.empty(PeopleQuery query) : this._(_Kind.empty, query: query);

  final _Kind kind;
  final String? title;
  final ContactsPermission? permission;
  final PhoneBookSyncState? sync;
  final PeopleQuery? query;
  final LookupState? lookup;
  final GroupSummary? group;
  final PersonName? person;
}

class _RowView extends ConsumerWidget {
  const _RowView({required this.row, required this.mode});

  final _Row row;
  final PeopleSearchMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (row.kind) {
      case _Kind.header:
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            HelixSpace.md,
            HelixSpace.md,
            HelixSpace.md,
            HelixSpace.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              row.title!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      case _Kind.permission:
        return _PermissionCard(permission: row.permission!);
      case _Kind.refresh:
        return _RefreshTile(sync: row.sync!);
      case _Kind.lookupPrompt:
        return _LookupPrompt(query: row.query!);
      case _Kind.lookupResult:
        return _LookupResult(lookup: row.lookup!, mode: mode);
      case _Kind.group:
        final group = row.group!;
        return HelixSettingsTile(
          icon: Icons.group_outlined,
          iconColor: Theme.of(context).colorScheme.primary,
          title: group.title,
          subtitle: 'Group',
          onTap: () => ref.read(peopleActionsProvider).openGroup(group),
        );
      case _Kind.person:
        return PersonResultTile(person: row.person!, mode: mode);
      case _Kind.empty:
        final query = row.query!;
        return query.isBrowse
            ? const _Notice(
                icon: Icons.people_outline,
                title: 'Nobody yet',
                message:
                    'Type a phone number or a ~Helix name to find someone.',
              )
            : _Notice(
                icon: Icons.search_off,
                title: 'No matches',
                message: 'Nobody you know matches "${query.raw}".',
              );
    }
  }
}

/// A person in a search result, with the tap behaviour of [mode].
class PersonResultTile extends ConsumerWidget {
  const PersonResultTile({super.key, required this.person, required this.mode});

  final PersonName person;
  final PeopleSearchMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(peopleActionsProvider);
    Future<void> call(bool video) async {
      final failure = await actions.startCall(person.accountId, video: video);
      if (failure != null && context.mounted) {
        showHelixSnackBar(context, failure);
      }
    }

    return HelixPersonTile(
      person: person.toItem(),
      onTap: () => mode == PeopleSearchMode.chats
          ? actions.openChat(person.accountId)
          : call(false),
      onLongPress: () => context.push(PeoplePaths.person(person.accountId)),
      trailing: mode == PeopleSearchMode.calls
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.call),
                  tooltip: 'Voice call ${person.display}',
                  onPressed: () => call(false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Video call ${person.display}',
                  onPressed: () => call(true),
                ),
              ],
            )
          : null,
    );
  }
}

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard({required this.permission});

  final ContactsPermission permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final forever = permission == ContactsPermission.permanentlyDenied;
    return Padding(
      padding: const EdgeInsets.all(HelixSpace.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: HelixRadius.card,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.contacts_outlined, color: scheme.primary),
                  ),
                  const SizedBox(width: HelixSpace.sm),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Find your contacts on Helix',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HelixSpace.xs),
              const Text(
                'Helix compares your contacts with its server using scrambled '
                'numbers, so it can show you who is already here. Your '
                'contacts and their phone numbers never leave this phone, and '
                'you can still message anyone by their number or ~Helix name.',
              ),
              const SizedBox(height: HelixSpace.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: () {
                    final controller = ref.read(
                      contactsPermissionProvider.notifier,
                    );
                    if (forever) {
                      controller.openSettings();
                    } else {
                      controller.request();
                    }
                  },
                  child: Text(forever ? 'Open settings' : 'Allow contacts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshTile extends ConsumerWidget {
  const _RefreshTile({required this.sync});

  final PhoneBookSyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = switch (sync.status) {
      PhoneBookStatus.syncing => 'Checking your contacts...',
      PhoneBookStatus.budgetExhausted =>
        'Today\'s limit for checking contacts is used up. Helix will try '
            'again tomorrow.',
      PhoneBookStatus.failed =>
        'Your contacts could not be checked. Helix will try again later.',
      PhoneBookStatus.synced when sync.found == 1 => '1 contact is on Helix.',
      PhoneBookStatus.synced => '${sync.found} contacts are on Helix.',
      _ => 'Check which of your contacts are on Helix.',
    };
    final busy = sync.status == PhoneBookStatus.syncing;
    return HelixSettingsTile(
      icon: Icons.sync,
      iconColor: Theme.of(context).colorScheme.primary,
      title: 'Refresh contacts',
      subtitle: subtitle,
      onTap: busy
          ? null
          : () => ref.read(phoneBookSyncProvider.notifier).syncNow(),
    );
  }
}

class _LookupPrompt extends ConsumerWidget {
  const _LookupPrompt({required this.query});

  final PeopleQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.intent == SearchIntent.phone && query.e164 == null) {
      return const Padding(
        padding: EdgeInsets.all(HelixSpace.md),
        child: Text(
          'To find someone by number, type the whole number, starting with '
          'the country code, like +880 1711 000001.',
        ),
      );
    }
    if (!query.canLookUp) return const SizedBox.shrink();
    final phone = query.intent == SearchIntent.phone;
    final title = phone
        ? 'Find ${PhoneNumbers.display(query.e164!)} on Helix'
        : 'Find ~${query.helixName} on Helix';
    return HelixSettingsTile(
      icon: phone ? Icons.dialpad : Icons.alternate_email,
      iconColor: Theme.of(context).colorScheme.primary,
      title: title,
      subtitle: phone
          ? 'Only a scrambled version of the number is sent.'
          : null,
      onTap: () => ref.read(peopleLookupProvider.notifier).lookUp(query),
    );
  }
}

class _LookupResult extends ConsumerWidget {
  const _LookupResult({required this.lookup, required this.mode});

  final LookupState lookup;
  final PeopleSearchMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (lookup.status) {
      case LookupStatus.idle:
        return const SizedBox.shrink();
      case LookupStatus.searching:
        return Semantics(
          liveRegion: true,
          label: 'Looking',
          child: const Padding(
            padding: EdgeInsets.all(HelixSpace.md),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: HelixSpace.sm),
                Text('Looking on Helix...'),
              ],
            ),
          ),
        );
      case LookupStatus.found:
        return PersonResultTile(person: lookup.person!, mode: mode);
      case LookupStatus.notFound:
        return const _Notice(
          icon: Icons.person_off_outlined,
          title: 'Not on Helix',
          message:
              'Nobody on Helix matches that, or they do not let people find '
              'them this way.',
        );
      case LookupStatus.self:
        return const _Notice(
          icon: Icons.person_outline,
          title: 'That is you',
          message: 'This is your own account.',
        );
      case LookupStatus.failed:
        final (title, message) = switch (lookup.failure) {
          PeopleFailure.rateLimited => (
            'Too many lookups',
            'You have looked up as many numbers as Helix allows today. Try '
                'again tomorrow.',
          ),
          PeopleFailure.offline => (
            'No connection',
            'Check your connection and try again.',
          ),
          _ => (
            'Could not look this up',
            'Something went wrong. Try again in a moment.',
          ),
        };
        return _Notice(
          icon: Icons.error_outline,
          title: title,
          message: message,
          live: true,
        );
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    this.live = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: live,
      container: true,
      label: '$title. $message',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: HelixSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: HelixSpace.xxs),
                    Text(
                      message,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
