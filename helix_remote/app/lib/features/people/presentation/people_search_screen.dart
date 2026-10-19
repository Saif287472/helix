import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/orbit_people_panel.dart';
import 'package:helix_remote/shared/widgets/people_search_panel.dart'
    show PeopleSearchMode;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the standalone people search, the field over the same people
/// panel the Chats and Calls searches draw (`contracts/home.md`), for
/// everything else that needs "pick a person": a `helix://contact` link, a
/// "new chat" button, a "new call" button.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key, this.mode = PeopleSearchMode.chats});

  final PeopleSearchMode mode;

  @override
  ConsumerState<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final people = ref.read(peopleActionsProvider);
    final calls = widget.mode == PeopleSearchMode.calls;
    return orbit.PeopleSearchScreen(
      model: orbit.PeopleSearchModel(
        panel: orbitPeoplePanelModel(
          ref,
          _query,
          calls ? orbit.PeopleSearchMode.calls : orbit.PeopleSearchMode.chats,
        ),
      ),
      actions: orbit.PeopleSearchActions(
        panel: orbit.PeoplePanelActions(
          onQueryChanged: (text) => setState(() => _query = text),
          // The keyboard's search key: the network look-up of a number or a
          // `~name`.
          onLookUp: () {
            final parsed = PeopleQuery.parse(
              _query,
              callingCode: ref.read(ownCallingCodeProvider).value,
            );
            ref.read(peopleLookupProvider.notifier).lookUp(parsed);
          },
          onAllowContacts: () async {
            await ref.read(contactsPermissionProvider.notifier).request();
          },
          onOpenContactsSettings: () =>
              ref.read(contactsPermissionProvider.notifier).openSettings(),
          onRefreshContacts: () =>
              ref.read(phoneBookSyncProvider.notifier).syncNow(),
          onOpenPerson: (id) async {
            if (calls) return people.startCall(id, video: false);
            await people.openChat(id);
            return null;
          },
          onCallPerson: (id, {required video}) =>
              people.startCall(id, video: video),
          onOpenContactInfo: (id) => context.push(PeoplePaths.person(id)),
          onOpenGroup: (groupId) =>
              people.openGroup(GroupSummary(id: groupId, title: '')),
        ),
      ),
    );
  }
}
