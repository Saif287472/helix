import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/features/people/application/people_failures.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';

/// The clock the people feature reads. A provider so a test can move time.
final peopleClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Where the address-book permission stands, and asking for it.
///
/// Asking is always the person's decision, after the explanation the screen
/// shows ("Helix checks your contacts on this phone and sends only scrambled
/// numbers"), never a surprise dialog on launch.
final contactsPermissionProvider =
    AsyncNotifierProvider<ContactsPermissionController, ContactsPermission>(
      ContactsPermissionController.new,
    );

final class ContactsPermissionController
    extends AsyncNotifier<ContactsPermission> {
  @override
  Future<ContactsPermission> build() =>
      ref.read(contactsAccessProvider).permission();

  /// Re-reads the permission (after the person came back from settings).
  Future<void> refresh() async {
    state = AsyncData(await ref.read(contactsAccessProvider).permission());
  }

  /// Shows the system dialog when it may be shown. When it is granted, the
  /// address book is matched at once.
  Future<ContactsPermission> request() async {
    final access = ref.read(contactsAccessProvider);
    final result = await access.request();
    state = AsyncData(result);
    if (result == ContactsPermission.granted) {
      await ref.read(phoneBookSyncProvider.notifier).syncNow();
    }
    return result;
  }

  /// Opens the app's page in the system settings, for a refusal that cannot
  /// be undone from inside the app.
  Future<void> openSettings() =>
      ref.read(contactsAccessProvider).openSettings();
}

enum PhoneBookStatus {
  /// Nothing running.
  idle,
  syncing,

  /// Matched; [PhoneBookSyncState.found] people were found.
  synced,

  /// Today's discovery budget is used up; it comes back tomorrow.
  budgetExhausted,

  /// No permission to read the address book.
  needsPermission,

  /// Offline or a server error; the next resume tries again.
  failed,
}

final class PhoneBookSyncState {
  const PhoneBookSyncState({
    this.status = PhoneBookStatus.idle,
    this.found = 0,
    this.checked = 0,
    this.lastSyncAt,
  });

  final PhoneBookStatus status;

  /// People found by the last sync, and numbers it checked.
  final int found;
  final int checked;
  final DateTime? lastSyncAt;

  PhoneBookSyncState copyWith({
    PhoneBookStatus? status,
    int? found,
    int? checked,
    DateTime? lastSyncAt,
  }) => PhoneBookSyncState(
    status: status ?? this.status,
    found: found ?? this.found,
    checked: checked ?? this.checked,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );
}

/// Matches the phone's address book against the server, politely.
///
/// **What leaves the phone:** salted hashes of numbers, in batches, through
/// the engine (`PeopleService.syncPhoneBook`). Raw numbers and names never do.
///
/// **How often:** discovery costs one unit of a 5,000-a-day budget per
/// number, and the engine sends the whole address book each time, so this is
/// deliberately rare - at most once every [minInterval] by itself (or
/// [changedInterval] after the address book changed), never again on a day
/// the last sync left less budget than it spent, and never without the
/// permission. The person can always ask for a refresh themselves
/// ([syncNow]).
final phoneBookSyncProvider =
    NotifierProvider<PhoneBookSyncController, PhoneBookSyncState>(
      PhoneBookSyncController.new,
    );

final class PhoneBookSyncController extends Notifier<PhoneBookSyncState> {
  static const minInterval = Duration(hours: 12);
  static const changedInterval = Duration(hours: 1);

  @override
  PhoneBookSyncState build() => const PhoneBookSyncState();

  /// Syncs when it is time: the host calls this on start, on resume, on a
  /// timer and when the address book changes.
  Future<void> syncIfDue({bool addressBookChanged = false}) async {
    if (state.status == PhoneBookStatus.syncing) return;
    final access = ref.read(contactsAccessProvider);
    if (await access.permission() != ContactsPermission.granted) return;
    final PeopleGateway gateway;
    try {
      final ready = await ref.read(peopleGatewayProvider.future);
      gateway = ready;
    } on Object {
      return; // No runtime yet.
    }
    final log = await gateway.readSyncLog();
    if (log != null) {
      final now = ref.read(peopleClockProvider)().toUtc();
      final age = now.difference(log.at);
      final wait = addressBookChanged ? changedInterval : minInterval;
      if (age < wait) return;
      final sameDay =
          now.year == log.at.year &&
          now.month == log.at.month &&
          now.day == log.at.day;
      // The server's budget is per day: do not start what the last sync
      // showed cannot finish.
      if (sameDay && log.remainingToday < log.checked) return;
    }
    await syncNow();
  }

  /// Matches the address book now.
  Future<void> syncNow() async {
    if (state.status == PhoneBookStatus.syncing) return;
    final access = ref.read(contactsAccessProvider);
    if (await access.permission() != ContactsPermission.granted) {
      state = state.copyWith(status: PhoneBookStatus.needsPermission);
      return;
    }
    state = state.copyWith(status: PhoneBookStatus.syncing);
    final now = ref.read(peopleClockProvider);
    PeopleGateway? gateway;
    try {
      final ready = await ref.read(peopleGatewayProvider.future);
      gateway = ready;
      // Bare national numbers in the address book (`01711…`) are read in the
      // country of this account's own number.
      ref.read(phoneCountryProvider).setFromOwnNumber(await ready.ownNumber());
      final result = await ready.syncPhoneBook();
      final at = now().toUtc();
      await ready.writeSyncLog(
        PhoneBookSyncLog(
          at: at,
          checked: result.checked,
          remainingToday: result.remainingToday,
        ),
      );
      state = PhoneBookSyncState(
        status: PhoneBookStatus.synced,
        found: result.found,
        checked: result.checked,
        lastSyncAt: at,
      );
    } on Object catch (error) {
      if (PeopleFailure.of(error) == PeopleFailure.rateLimited) {
        // Remember that today is spent, so nothing retries until tomorrow.
        await gateway?.writeSyncLog(
          PhoneBookSyncLog(at: now().toUtc(), checked: 1, remainingToday: 0),
        );
        state = state.copyWith(status: PhoneBookStatus.budgetExhausted);
      } else {
        state = state.copyWith(status: PhoneBookStatus.failed);
      }
    }
  }
}
