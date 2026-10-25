import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
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
  // With nothing typed the panel browses: the people this device knows and the
  // phone's contacts card, as `contracts/home.md` and the Orbit panel draw it
  // (the card has no place once a search is running).
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
    prompt = FindName('~${query.helixName}');
  } else if (query.intent == SearchIntent.phone) {
    if (query.e164 == null) {
      prompt = const NeedFullNumber();
    } else {
      prompt = FindNumber(PhoneNumbers.display(query.e164!));
    }
  } else {
    prompt = const NoLookup();
  }

  // An answer belongs to the text it was found for: once the field holds
  // something else, it says nothing (a stale "Not on Orbit" would otherwise
  // sit under a number that is on Orbit).
  final answered = lookupState.answers(query);
  LookupView lookupView;
  switch (answered ? lookupState.status : LookupStatus.idle) {
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

  // The chat you keep your own notes in is an entry point here, the same way
  // WhatsApp's "Message yourself" sits in the contact list. The Calls tab has
  // no such row: there is nobody to call there.
  final selfPerson = mode == PeopleSearchMode.calls
      ? null
      : ref.watch(selfPersonProvider);

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
    self: selfPerson == null
        ? null
        : PanelSelf(
            accountId: selfPerson.accountId,
            title: noteToSelfTitle,
            avatar: selfPerson.avatar,
          ),
    empty: empty,
  );
}
