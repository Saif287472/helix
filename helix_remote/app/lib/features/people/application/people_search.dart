import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_failures.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/shared/navigation/conversation_seams.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show SetHelixNameRequest;
import 'package:helix_remote_ui/helix_remote_ui.dart' show HelixNameSource;

/// What a search box holds, read the way a person meant it.
enum SearchIntent {
  /// Nothing typed: everyone this device knows.
  browse,

  /// A name, or part of a number.
  text,

  /// Written as a phone number.
  phone,

  /// `~name`.
  helixName,
}

/// The text in a people search box, understood.
///
/// - `~sam` looks up the Helix name `sam`.
/// - `01711-000001` or `+880 1711 000001` is a phone number; it is turned into
///   E.164 (a leading `0` is read in the country of **this account's own
///   number**, so a typed local number finds the right person) for the one
///   discovery lookup.
/// - anything else is a name, searched among the people and groups already on
///   this device. A name that could also be a Helix name can be looked up
///   with one tap.
final class PeopleQuery {
  const PeopleQuery._({
    required this.raw,
    required this.intent,
    this.e164,
    this.helixName,
    this.digits = '',
    this.text = '',
  });

  /// The text as typed, trimmed.
  final String raw;
  final SearchIntent intent;

  /// For [SearchIntent.phone]: the number as E.164, or null when what was
  /// typed cannot be one yet (too short, or no country to read it in).
  final String? e164;

  /// For [SearchIntent.helixName], and for a text that could be a Helix name:
  /// the name without `~`, lower case.
  final String? helixName;

  /// The digits of a number search, without leading zeros: matched against
  /// numbers already stored, so `01711` finds `+8801711000001`.
  final String digits;

  /// The lower-case text to match names against.
  final String text;

  bool get isBrowse => intent == SearchIntent.browse;

  /// Whether a network lookup can answer this query.
  bool get canLookUp =>
      (intent == SearchIntent.phone && e164 != null) || helixName != null;

  factory PeopleQuery.parse(String input, {String? callingCode}) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const PeopleQuery._(raw: '', intent: SearchIntent.browse);
    }
    if (raw.startsWith('~')) {
      final name = raw.substring(1).trim().toLowerCase();
      return PeopleQuery._(
        raw: raw,
        intent: SearchIntent.helixName,
        helixName: SetHelixNameRequest.pattern.hasMatch(name) ? name : null,
        text: name,
      );
    }
    if (PhoneNumbers.looksLikeNumber(raw)) {
      final digits = raw
          .replaceAll(RegExp(r'\D'), '')
          .replaceFirst(RegExp(r'^0+'), '');
      return PeopleQuery._(
        raw: raw,
        intent: SearchIntent.phone,
        e164: PhoneNumbers.normalize(
          raw,
          defaultCallingCode: callingCode,
          guessNational: true,
        ),
        digits: digits,
      );
    }
    final lower = raw.toLowerCase();
    return PeopleQuery._(
      raw: raw,
      intent: SearchIntent.text,
      helixName: SetHelixNameRequest.pattern.hasMatch(lower) ? lower : null,
      text: lower,
    );
  }
}

/// The country calling code of this account's own number, which is how a
/// number typed without one is read. Also fed to the address-book adapter.
final ownCallingCodeProvider = FutureProvider<String?>((ref) async {
  final gateway = await ref.watch(peopleGatewayProvider.future);
  final number = await gateway.ownNumber();
  ref.read(phoneCountryProvider).setFromOwnNumber(number);
  return number == null ? null : PhoneNumbers.callingCodeOf(number);
});

/// This account's own id, so a search never offers you yourself.
final selfAccountIdProvider = Provider<String?>(
  (ref) => ref.watch(peopleGatewayProvider).value?.selfAccountId,
);

/// What a search found among the people and groups this device already
/// knows. Pure and synchronous: it filters the in-memory directory, so typing
/// costs no query and no network.
final class PeopleSearchResults {
  const PeopleSearchResults({this.people = const [], this.groups = const []});

  final List<PersonName> people;
  final List<GroupSummary> groups;

  bool get isEmpty => people.isEmpty && groups.isEmpty;
}

/// Filters [directory] (and [groups]) by [query]. Blocked people never show;
/// neither does [selfId]. With nothing typed, everyone with a name the person
/// would recognise (a phone-book name or nickname, or a profile name) is
/// listed, and strangers who only share a group with the user are not.
PeopleSearchResults searchPeople(
  PeopleDirectory directory,
  List<GroupSummary> groups,
  PeopleQuery query, {
  String? selfId,
}) {
  bool known(PersonName p) =>
      p.source != HelixNameSource.unknown || p.profileName != null;

  bool matches(PersonName p) {
    switch (query.intent) {
      case SearchIntent.browse:
        return known(p);
      case SearchIntent.helixName:
        return query.text.isNotEmpty &&
            (p.helixName?.toLowerCase().contains(query.text) ?? false);
      case SearchIntent.phone:
        final number = p.phoneNumber;
        return query.digits.isNotEmpty &&
            number != null &&
            number.replaceAll(RegExp(r'\D'), '').contains(query.digits);
      case SearchIntent.text:
        bool hit(String? value) =>
            value != null && value.toLowerCase().contains(query.text);
        return hit(p.names.phoneBookName) ||
            hit(p.names.nickname) ||
            hit(p.profileName) ||
            hit(p.helixName) ||
            hit(p.phoneNumber) ||
            hit(p.display);
    }
  }

  final people = [
    for (final person in directory.all)
      if (!person.blocked && person.accountId != selfId && matches(person))
        person,
  ]..sort((a, b) => a.display.toLowerCase().compareTo(b.display.toLowerCase()));

  final matchingGroups = query.intent == SearchIntent.text
      ? [
          for (final group in groups)
            if (group.title.toLowerCase().contains(query.text)) group,
        ]
      : const <GroupSummary>[];
  return PeopleSearchResults(people: people, groups: matchingGroups);
}

/// The groups this account is in, live.
final groupsProvider = StreamProvider<List<GroupSummary>>((ref) async* {
  final gateway = await ref.watch(peopleGatewayProvider.future);
  yield* gateway.watchGroups();
});

/// The search results for a text, live: the directory and the groups, filtered.
/// Keyed by the raw text, which is what a search box holds.
final peopleSearchProvider = Provider.autoDispose
    .family<AsyncValue<PeopleSearchResults>, String>((ref, text) {
      final directory = ref.watch(peopleDirectoryProvider);
      final groups = ref.watch(groupsProvider).value ?? const <GroupSummary>[];
      final callingCode = ref.watch(ownCallingCodeProvider).value;
      final self = ref.watch(selfAccountIdProvider);
      return directory.whenData(
        (value) => searchPeople(
          value,
          groups,
          PeopleQuery.parse(text, callingCode: callingCode),
          selfId: self,
        ),
      );
    });

// ------------------------------------------------------------------ lookup

enum LookupStatus {
  idle,
  searching,
  found,

  /// Nobody on Helix has this number, or they do not let people find them by
  /// it (the server does not say which, on purpose).
  notFound,

  /// The number is this account's own.
  self,
  failed,
}

/// The outcome of one network lookup, for the query it answered.
final class LookupState {
  const LookupState({
    this.status = LookupStatus.idle,
    this.query = '',
    this.person,
    this.failure,
  });

  final LookupStatus status;

  /// The text this answers; the screen ignores it once the text changes.
  final String query;
  final PersonName? person;
  final PeopleFailure? failure;

  bool answers(PeopleQuery current) => query == current.raw;
}

/// Looks one number or `~name` up on the server.
///
/// Never automatic: a number lookup spends one unit of the 5,000-a-day
/// discovery budget and tells the server which number was asked about, so it
/// runs when the person submits or taps the "Find" row, not on every key.
final peopleLookupProvider =
    NotifierProvider.autoDispose<PeopleLookupController, LookupState>(
      PeopleLookupController.new,
    );

final class PeopleLookupController extends Notifier<LookupState> {
  @override
  LookupState build() => const LookupState();

  void clear() => state = const LookupState();

  Future<void> lookUp(PeopleQuery query) async {
    if (!query.canLookUp) return;
    state = LookupState(status: LookupStatus.searching, query: query.raw);
    try {
      final gateway = await ref.read(peopleGatewayProvider.future);
      final row = query.intent == SearchIntent.phone
          ? await gateway.findByNumber(query.e164!)
          : await gateway.findByHelixName(query.helixName!);
      if (state.query != query.raw) return; // The text changed meanwhile.
      if (row == null) {
        state = LookupState(status: LookupStatus.notFound, query: query.raw);
      } else if (row.accountId == gateway.selfAccountId) {
        state = LookupState(status: LookupStatus.self, query: query.raw);
      } else {
        state = LookupState(
          status: LookupStatus.found,
          query: query.raw,
          person: PersonName.fromRow(row),
        );
      }
    } on Object catch (error) {
      if (state.query != query.raw) return;
      state = LookupState(
        status: LookupStatus.failed,
        query: query.raw,
        failure: PeopleFailure.of(error),
      );
    }
  }
}

// ----------------------------------------------------------------- actions

/// What tapping a person does, shared by the Chats and Calls searches.
final peopleActionsProvider = Provider<PeopleActions>(PeopleActions.new);

final class PeopleActions {
  PeopleActions(this._ref);

  final Ref _ref;

  /// Opens the chat with [accountId], creating it when there is none (anyone
  /// can message anyone who has not blocked them).
  Future<void> openChat(String accountId) async {
    final gateway = await _ref.read(peopleGatewayProvider.future);
    final conversationId = await gateway.openChat(accountId);
    await _ref.read(conversationSeamsProvider).openChat(conversationId);
  }

  Future<void> openGroup(GroupSummary group) =>
      _ref.read(conversationSeamsProvider).openChat(group.conversationId);

  /// Starts a call. False when calling is not available yet (the screen says
  /// so).
  Future<bool> startCall(String accountId, {required bool video}) =>
      _ref.read(conversationSeamsProvider).startCall(accountId, video: video);
}
