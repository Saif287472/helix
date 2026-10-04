import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/shared/navigation/conversation_seams.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show PersonRow;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReportCategory;

/// Whether the keys behind a chat have been checked.
enum TrustState {
  /// Nothing has been exchanged with this person yet, so there is no key to
  /// check.
  noKey,

  /// A key is pinned and nobody has compared safety numbers.
  unverified,

  /// The safety numbers were compared (or a code was scanned).
  verified,

  /// Their key changed after it was pinned, and has not been verified since.
  /// The chat keeps working, but the change deserves a look.
  keyChanged,
}

/// A person as the contact info screen needs them: the name (the product's
/// naming order), the trust state, and what can be done.
final class ContactPerson {
  const ContactPerson({
    required this.name,
    required this.trust,
    this.numberLabel,
    this.keyChangedAt,
    this.keyStamp = 0,
  });

  /// Someone this device has no row for yet.
  factory ContactPerson.unknown(String accountId) => ContactPerson(
    name: PersonName.unknown(accountId),
    trust: TrustState.noKey,
  );

  factory ContactPerson.fromRow(PersonRow row) {
    final key = row.identityKey;
    final TrustState trust;
    if (key == null) {
      trust = TrustState.noKey;
    } else if (row.identityVerified) {
      trust = TrustState.verified;
    } else if (row.identityChangedAt != null) {
      trust = TrustState.keyChanged;
    } else {
      trust = TrustState.unverified;
    }
    return ContactPerson(
      name: PersonName.fromRow(row),
      numberLabel: row.phoneNumber == null
          ? null
          : PhoneNumbers.display(row.phoneNumber!),
      trust: trust,
      keyChangedAt: row.identityChangedAt,
      keyStamp: key == null ? 0 : Object.hashAll(key),
    );
  }

  final PersonName name;

  /// Their number set out for reading (`+880 1711000001`).
  final String? numberLabel;
  final TrustState trust;
  final DateTime? keyChangedAt;

  /// Changes when the pinned key does, so the safety number is recomputed.
  final int keyStamp;

  /// Whether Helix knows this person's number, which is what lets a rename be
  /// written to the phone's contacts.
  bool get hasNumber => name.phoneNumber != null;
}

/// The person on the contact info screen, live. Null while there is no row
/// (a person this device has never heard of).
final contactPersonProvider = StreamProvider.autoDispose
    .family<ContactPerson?, String>((ref, accountId) async* {
      final gateway = await ref.watch(peopleGatewayProvider.future);
      yield* gateway
          .watchPerson(accountId)
          .map((row) => row == null ? null : ContactPerson.fromRow(row));
    });

/// Their "about" line (from their encrypted profile), live.
final contactAboutProvider = StreamProvider.autoDispose.family<String?, String>(
  (ref, accountId) async* {
    final gateway = await ref.watch(peopleGatewayProvider.future);
    yield* gateway.watchAbout(accountId);
  },
);

/// The direct chat's mute and disappearing state.
final class ContactChatSettings {
  const ContactChatSettings({this.muteLabel, this.disappearingSeconds});

  /// Null when notifications are on; otherwise when they come back ("Always"
  /// or "Until 14:30").
  final String? muteLabel;

  /// Null or 0 is off.
  final int? disappearingSeconds;

  bool get muted => muteLabel != null;

  /// The label for a mute that ends at [until], seen at [now].
  static String? labelFor(DateTime? until, DateTime now) {
    if (until == null || !until.isAfter(now)) return null;
    if (until.difference(now) > const Duration(days: 365 * 10)) return 'Always';
    final local = until.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final sameDay =
        local.year == now.toLocal().year &&
        local.month == now.toLocal().month &&
        local.day == now.toLocal().day;
    final time = '${two(local.hour)}:${two(local.minute)}';
    return sameDay
        ? 'Until $time'
        : 'Until ${two(local.day)}/${two(local.month)}/${two(local.year % 100)} $time';
  }
}

final contactChatProvider = StreamProvider.autoDispose
    .family<ContactChatSettings, String>((ref, accountId) async* {
      final gateway = await ref.watch(peopleGatewayProvider.future);
      yield* gateway
          .watchDirectChat(accountId)
          .map(
            (chat) => ContactChatSettings(
              muteLabel: ContactChatSettings.labelFor(
                chat?.mutedUntil,
                ref.read(peopleClockProvider)(),
              ),
              disappearingSeconds: chat?.disappearingSeconds,
            ),
          );
    });

/// The groups both of you are in.
final commonGroupsProvider = StreamProvider.autoDispose
    .family<List<GroupSummary>, String>((ref, accountId) async* {
      final gateway = await ref.watch(peopleGatewayProvider.future);
      yield* gateway.watchCommonGroups(accountId);
    });

/// The safety number for the chat, recomputed when their key changes. Null
/// until a key is pinned.
final safetyNumberProvider = FutureProvider.autoDispose
    .family<SafetyNumberData?, String>((ref, accountId) async {
      // The key's stamp is what changes on a key change; depending on it
      // recomputes the number.
      ref.watch(
        contactPersonProvider(accountId).select((v) => v.value?.keyStamp),
      );
      final gateway = await ref.watch(peopleGatewayProvider.future);
      return gateway.safetyNumber(accountId);
    });

/// How long a chat stays muted.
enum MuteFor {
  eightHours('8 hours', Duration(hours: 8)),
  oneWeek('1 week', Duration(days: 7)),
  always('Always', Duration(days: 365 * 100));

  const MuteFor(this.label, this.duration);

  final String label;
  final Duration duration;
}

/// The disappearing-message timers offered.
enum DisappearAfter {
  off('Off', null),
  day('24 hours', 24 * 3600),
  week('7 days', 7 * 24 * 3600),
  ninety('90 days', 90 * 24 * 3600);

  const DisappearAfter(this.label, this.seconds);

  final String label;
  final int? seconds;

  static DisappearAfter of(int? seconds) {
    for (final value in values) {
      if ((value.seconds ?? 0) == (seconds ?? 0)) return value;
    }
    return DisappearAfter.off;
  }
}

/// Why a person is reported (the server's categories, in words).
enum ReportReason {
  spam('Spam', ReportCategory.spam),
  abuse('Abuse or harassment', ReportCategory.abuse),
  impersonation('Pretending to be someone else', ReportCategory.impersonation),
  other('Something else', ReportCategory.other);

  const ReportReason(this.label, this.category);

  final String label;
  final ReportCategory category;
}

/// A report as the person filled it in.
final class PersonReport {
  const PersonReport({required this.reason, this.note});

  final ReportReason reason;
  final String? note;
}

/// What a rename did.
enum RenameOutcome {
  /// The name is saved in Helix, and in the phone's contacts too.
  savedEverywhere,

  /// Saved in Helix only; nothing was expected of the phone (no number, or
  /// the nickname was cleared).
  savedInHelix,

  /// Saved in Helix; the phone has no permission yet, and the person can be
  /// asked for it.
  needsPhonePermission,

  /// Saved in Helix; the phone refused the write.
  phoneRefused,
}

/// The things the contact info screen can do. One class so the screen holds no
/// engine call and every action is testable against a fake gateway.
final contactInfoActionsProvider = Provider<ContactInfoActions>(
  ContactInfoActions.new,
);

final class ContactInfoActions {
  ContactInfoActions(this._ref);

  final Ref _ref;

  Future<PeopleGateway> get _gateway => _ref.read(peopleGatewayProvider.future);

  /// Reads their profile (name and about) when this device has their key.
  /// Best effort: offline and "no key yet" are both quiet.
  Future<void> refreshProfile(String accountId) async {
    try {
      await (await _gateway).refreshProfile(accountId);
    } on Object {
      // The profile is a nicety; the screen already shows what is stored.
    }
  }

  /// Gives them [nickname] (null or blank removes it). The engine syncs the
  /// name to this account's other devices and, when it knows their number,
  /// writes it to the phone's contacts - creating the contact if there is
  /// none. The phone-book name outranks the nickname, which is why the
  /// engine also updates the stored phone-book name when the phone took it.
  Future<RenameOutcome> rename(String accountId, String? nickname) async {
    final gateway = await _gateway;
    final trimmed = nickname?.trim();
    final name = trimmed == null || trimmed.isEmpty ? null : trimmed;
    await gateway.setNickname(accountId, name);
    if (name == null) return RenameOutcome.savedInHelix;
    final row = await gateway.watchPerson(accountId).first;
    if (row?.phoneNumber == null) return RenameOutcome.savedInHelix;
    if (row?.phonebookName == name) return RenameOutcome.savedEverywhere;
    final access = _ref.read(contactsAccessProvider);
    if (!access.isSupported) return RenameOutcome.savedInHelix;
    return switch (await access.permission()) {
      ContactsPermission.granted => RenameOutcome.phoneRefused,
      ContactsPermission.unsupported => RenameOutcome.savedInHelix,
      _ => RenameOutcome.needsPhonePermission,
    };
  }

  /// After the person agreed to let Helix write to their contacts: asks the
  /// system for the permission and, if given, saves [name] there.
  Future<RenameOutcome> savePhoneName(String accountId, String name) async {
    final granted = await _ref
        .read(contactsPermissionProvider.notifier)
        .request();
    if (granted != ContactsPermission.granted) {
      return RenameOutcome.phoneRefused;
    }
    return rename(accountId, name);
  }

  Future<void> setVerified(String accountId, {required bool verified}) async =>
      (await _gateway).setVerified(accountId, verified: verified);

  Future<void> block(String accountId) async =>
      (await _gateway).block(accountId);

  Future<void> unblock(String accountId) async =>
      (await _gateway).unblock(accountId);

  /// Tells the server's operators about this account. No message content is
  /// sent, only the account, the reason and the person's own note.
  Future<void> report(String accountId, PersonReport report) async =>
      (await _gateway).report(
        accountId,
        report.reason.category,
        note: report.note,
      );

  Future<void> mute(String accountId, MuteFor? duration) async {
    final now = _ref.read(peopleClockProvider)();
    await (await _gateway).setMutedUntil(
      accountId,
      duration == null ? null : now.add(duration.duration),
    );
  }

  Future<void> setDisappearing(String accountId, DisappearAfter after) async =>
      (await _gateway).setDisappearing(accountId, after.seconds);

  Future<void> openChat(String accountId) async {
    final conversationId = await (await _gateway).openChat(accountId);
    await _ref.read(conversationSeamsProvider).openChat(conversationId);
  }

  Future<void> openGroup(GroupSummary group) =>
      _ref.read(conversationSeamsProvider).openChat(group.conversationId);

  /// Opens the shared media of the chat with them. False when that screen is
  /// not available yet.
  Future<bool> openSharedMedia(String accountId) =>
      _ref.read(conversationSeamsProvider).openSharedMedia('direct:$accountId');

  /// False when calling is not available yet.
  Future<bool> startCall(String accountId, {required bool video}) =>
      _ref.read(conversationSeamsProvider).startCall(accountId, video: video);
}
