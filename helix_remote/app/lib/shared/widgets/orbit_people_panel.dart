import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_failures.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:orbit_ui/orbit_ui.dart' hide PhoneBookStatus;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// The people panel's model for [text] (`contracts/home.md`): the people and
/// groups that match, the look-up of a number or `~name`, and the phone's
/// contacts card. Shared by Home's searches and the people search page.
PeoplePanelModel orbitPeoplePanelModel(
  WidgetRef ref,
  String text,
  PeopleSearchMode mode,
) {
  // People search runs only while something is typed, as the old Home's
  // panel did: an empty field reads nothing from the people feature.
  if (text.trim().isEmpty) return PeoplePanelModel(mode: mode);
  final query = PeopleQuery.parse(
    text,
    callingCode: ref.read(ownCallingCodeProvider).asData?.value,
  );
  final resultsAsync = ref.watch(peopleSearchProvider(text));
  final results = resultsAsync.value;
  final permission = ref.watch(contactsPermissionProvider).asData?.value;
  final sync = ref.watch(phoneBookSyncProvider);
  final lookupState = ref.watch(peopleLookupProvider);

  ContactsCard contactsCard;
  if (permission == null ||
      permission == ContactsPermission.unsupported ||
      permission == ContactsPermission.granted) {
    contactsCard = permission == ContactsPermission.granted
        ? ContactsCard.refresh
        : ContactsCard.hidden;
  } else if (permission == ContactsPermission.permanentlyDenied) {
    contactsCard = ContactsCard.openSettings;
  } else {
    contactsCard = ContactsCard.ask;
  }
  if (permission == ContactsPermission.granted) {
    contactsCard = ContactsCard.refresh;
  }
  if (permission != ContactsPermission.granted &&
      permission != ContactsPermission.permanentlyDenied &&
      permission != ContactsPermission.denied &&
      permission != ContactsPermission.notAsked) {
    contactsCard = ContactsCard.hidden;
  }

  orbit.PhoneBookStatus refreshStatus;
  switch (sync.status) {
    case PhoneBookStatus.syncing:
      refreshStatus = orbit.PhoneBookStatus.checking;
      break;
    case PhoneBookStatus.budgetExhausted:
      refreshStatus = orbit.PhoneBookStatus.limit;
      break;
    case PhoneBookStatus.failed:
      refreshStatus = orbit.PhoneBookStatus.failed;
      break;
    case PhoneBookStatus.synced:
      refreshStatus = orbit.PhoneBookStatus.done;
      break;
    default:
      refreshStatus = orbit.PhoneBookStatus.idle;
  }

  LookupPrompt prompt;
  if (query.helixName != null) {
    final name = query.raw.startsWith('~') ? query.raw : '~${query.helixName}';
    prompt = FindName(name);
  } else if (query.intent == SearchIntent.phone) {
    if (query.e164 == null) {
      prompt = const NeedFullNumber();
    } else {
      prompt = FindNumber(PhoneNumbers.display(query.e164!));
    }
  } else {
    prompt = const NoLookup();
  }

  LookupView lookupView;
  switch (lookupState.status) {
    case LookupStatus.idle:
      lookupView = LookupView.idle;
      break;
    case LookupStatus.searching:
      lookupView = LookupView.searching;
      break;
    case LookupStatus.notFound:
      lookupView = LookupView.notFound;
      break;
    case LookupStatus.self:
      lookupView = LookupView.self;
      break;
    case LookupStatus.failed:
      switch (lookupState.failure) {
        case PeopleFailure.rateLimited:
          lookupView = LookupView.rateLimited;
          break;
        case PeopleFailure.offline:
          lookupView = LookupView.offline;
          break;
        default:
          lookupView = LookupView.failed;
      }
      break;
    case LookupStatus.found:
      lookupView = LookupView.idle;
      break;
  }

  final groups = [
    for (final g in results?.groups ?? const <GroupSummary>[])
      PanelGroup(
        groupId: g.id,
        chatId: g.conversationId,
        title: g.title,
        avatar: HelixAvatarModel(
          name: g.title,
          isGroup: true,
          colorIndex: HelixAvatarModel.colorIndexFor(g.id),
        ),
      ),
  ];
  final people = [
    for (final p in results?.people ?? const <PersonName>[])
      HelixPersonItem(
        id: p.accountId,
        names: p.tileNames,
        image: p.image,
        about: null,
        online: false,
        blocked: p.blocked,
        verified: p.verified,
      ),
  ];

  PanelEmpty empty;
  if (results != null && results.isEmpty && lookupView == LookupView.idle) {
    if (query.isBrowse) {
      empty = PanelEmpty.nobodyYet;
    } else if (prompt is NoLookup) {
      empty = PanelEmpty.noMatches;
    } else {
      empty = PanelEmpty.none;
    }
  } else {
    empty = PanelEmpty.none;
  }
  if (results != null &&
      results.people.isEmpty &&
      results.groups.isEmpty &&
      !query.isBrowse) {
    // avoid nobodyYet for searches
  }

  return PeoplePanelModel(
    query: text,
    mode: mode,
    status: resultsAsync.isLoading
        ? ListStatus.loading
        : resultsAsync.hasError
        ? ListStatus.failed
        : ListStatus.ready,
    contacts: contactsCard,
    refresh: refreshStatus,
    found: sync.found,
    lookupPrompt: prompt,
    lookup: lookupView,
    groups: groups,
    people: people,
    empty: empty,
  );
}
