import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/app_blob_store.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/platform/flutter_media_processor.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/core/platform/saved_accounts.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform;

/// Opens the app's one live [HelixRuntime] for an account on a server.
///
/// This is the seam between the app and the engine. Everything above it works
/// with a runtime it was handed; tests and the widget suite replace this with
/// one backed by an in-memory database, so no test ever opens a real file,
/// a keystore or a socket.
abstract interface class RuntimeFactory {
  Future<HelixRuntime> open({required String account, required Uri serverUrl});
}

/// The real factory: keystore, encrypted file on disk, live network.
final class DeviceRuntimeFactory implements RuntimeFactory {
  DeviceRuntimeFactory({
    SecureKeyStore? keys,
    PhoneBook? phoneBook,
    Future<EngineConfig> Function()? config,
  }) : _keys = keys ?? SecureKeyStore(),
       _phoneBook = phoneBook ?? const DevicePhoneBook(),
       _config = config ?? _defaultEngineConfig;

  final SecureKeyStore _keys;
  final PhoneBook _phoneBook;
  final Future<EngineConfig> Function() _config;

  /// Used when no configuration is injected. The real device name comes from
  /// `engineConfigProvider`, which needs the platform plugin; this is the
  /// fallback for a host without one.
  static Future<EngineConfig> _defaultEngineConfig() async => engineConfigFor(
    deviceName: 'Helix device',
    platform: currentDevicePlatform,
  );

  @override
  Future<HelixRuntime> open({
    required String account,
    required Uri serverUrl,
  }) async {
    final file = await AppPaths.databaseFile(account);
    return HelixRuntime.open(
      account: account,
      dbFile: file,
      key: await _keys.keyFor(account, file),
      serverUrl: serverUrl,
      phoneBook: _phoneBook,
      config: await _config(),
      blobs: AppBlobStore(await AppPaths.attachmentCache(account)),
      mediaProcessor: FlutterMediaProcessor(),
      keys: _keys,
    );
  }
}

final runtimeFactoryProvider = Provider<RuntimeFactory>(
  (ref) => DeviceRuntimeFactory(
    phoneBook: DevicePhoneBook(
      access: ref.watch(contactsAccessProvider),
      country: ref.watch(phoneCountryProvider),
    ),
  ),
);

/// The country code bare national numbers are read in (the prefix of this
/// account's own number), shared by the address-book adapter the engine holds
/// and the people search. See [PhoneCountry].
final phoneCountryProvider = Provider<PhoneCountry>((ref) => PhoneCountry());

/// The keystore that holds each account's database key. Overridden in tests
/// so nothing writes to the platform.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);

/// The accounts on this device, in the keystore. Overridden in tests so
/// nothing writes to the platform.
final accountSlotStoreProvider = Provider<AccountSlotStore>(
  (ref) => AccountSlotStore(),
);

/// The sign-in page's remembered numbers, in the keystore. Overridden in
/// tests so nothing writes to the platform.
final savedAccountsStoreProvider = Provider<SavedAccountsStore>(
  (ref) => SavedAccountsStore(),
);

/// The numbers this device remembers, most recent first. Read when sign-in
/// shows the phone page; [savedAccountsProvider.notifier] keeps the list in
/// step with the store as it is remembered and forgotten.
final savedAccountsProvider =
    NotifierProvider<SavedAccountsNotifier, List<SavedAccountEntry>>(
      SavedAccountsNotifier.new,
    );

final class SavedAccountsNotifier extends Notifier<List<SavedAccountEntry>> {
  @override
  List<SavedAccountEntry> build() {
    _read();
    return const [];
  }

  Future<void> _read() async {
    final List<SavedAccountEntry> entries;
    try {
      entries = await ref.read(savedAccountsStoreProvider).load();
    } on Object {
      // No keystore on this host (tests): the page shows no saved accounts,
      // and nothing that types a number depends on the list.
      return;
    }
    if (ref.mounted) state = entries;
  }

  Future<void> remember(SavedAccountEntry entry) async {
    await ref.read(savedAccountsStoreProvider).remember(entry);
    state = [entry, ...state.where((e) => e.e164 != entry.e164)];
  }

  Future<void> forget(String e164) async {
    await ref.read(savedAccountsStoreProvider).forget(e164);
    state = state.where((e) => e.e164 != e164).toList();
  }
}

/// The accounts on this device and the one on screen.
///
/// Empty until [AccountsNotifier.restore] has read the keystore at start.
/// Sign-in makes a slot for the account it is signing in
/// ([AccountsNotifier.useServer]) and keeps it once that succeeds
/// ([AccountsNotifier.signedIn]); only then is it written to the keystore.
final accountsProvider = NotifierProvider<AccountsNotifier, AccountSlots>(
  AccountsNotifier.new,
);

final class AccountsNotifier extends Notifier<AccountSlots> {
  final _random = Random.secure();

  @override
  AccountSlots build() => const AccountSlots();

  /// Reads the accounts back and points the app at the one last on screen,
  /// or at [prefer] when that is a signed-in account (a notification of it
  /// started the app). Returns whether there was one to open.
  ///
  /// The folders of accounts the device no longer lists (a sign-in that
  /// never finished) are deleted with their keys first.
  Future<bool> restore({String? prefer}) async {
    var loaded = await ref.read(accountSlotStoreProvider).load();
    await _deleteUnlisted(loaded);
    final preferred = prefer == null ? null : loaded.byId(prefer);
    final switched =
        preferred != null &&
        preferred.signedIn &&
        preferred.id != loaded.active;
    if (switched) {
      loaded = loaded
          .put(preferred.copyWith(lastUsed: ref.read(clockProvider)()))
          .activate(preferred.id);
    }
    final current = loaded.current;
    // A remembered address that is not https (or not an address at all) is
    // not used: the device opens on sign-in rather than talking to it in the
    // clear.
    final uri = current == null ? null : Uri.tryParse(current.server);
    final usable =
        uri != null && uri.hasScheme && ServerPolicy.check(uri) == null;
    state = usable ? loaded : loaded.activate(null);
    if (usable && switched) {
      await ref.read(accountSlotStoreProvider).save(state);
    }
    return usable;
  }

  Future<void> _deleteUnlisted(AccountSlots listed) async {
    final List<String> folders;
    try {
      folders = await AppPaths.accountFolders();
    } on Object {
      return; // No app folder on this host.
    }
    for (final id in folders) {
      if (listed.byId(id) != null) continue;
      await AppPaths.wipeLocalFiles(id, includeDatabase: true);
      await AppPaths.deleteAccountFolder(id);
      try {
        await ref.read(secureKeyStoreProvider).forget(id);
      } on Object {
        // The files are gone, so the key guards nothing.
      }
    }
  }

  /// Points the app at [url] for the account being signed in, which tears the
  /// runtime down and opens a new one (see [runtimeProvider]).
  ///
  /// The slot is the one still signing in if there is one, so changing server
  /// halfway reuses its files. A signed-in account is never moved to another
  /// server: with one on screen, a new slot is made.
  ///
  /// Throws [InsecureServerUrl] for an address [ServerPolicy] refuses (not
  /// https, outside a debug build's development hosts), so nothing downstream
  /// ever builds a client for it.
  void useServer(Uri url) {
    final problem = ServerPolicy.check(url);
    if (problem != null) throw InsecureServerUrl(problem);
    final server = url.toString();
    final current = state.current;
    if (current != null && !current.signedIn) {
      if (current.server != server) {
        state = state.put(current.copyWith(server: server));
      }
      return;
    }
    AccountSlot? pending;
    for (final s in state.slots) {
      if (!s.signedIn) pending = s;
    }
    final slot =
        pending?.copyWith(server: server) ??
        AccountSlot(id: state.newId(_random), server: server);
    state = state.put(slot, active: slot.id);
  }

  /// "Add account": sign-in shows, and the accounts already signed in stay
  /// listed there to come back to.
  void addAccount() => leave();

  /// No account on screen: the next screen is sign-in on Helix Global. A
  /// slot whose sign-in never finished is dropped (its folder goes at the
  /// next start).
  void leave() => state = AccountSlots(
    slots: [
      for (final s in state.slots)
        if (s.signedIn) s,
    ],
  );

  /// The account on screen finished signing in: it is kept, and opened again
  /// at the next start.
  Future<void> signedIn({String e164 = '', String name = ''}) async {
    final current = state.current;
    if (current == null) return;
    state = state.put(
      current.copyWith(
        signedIn: true,
        e164: e164.isEmpty ? null : e164,
        name: name.isEmpty ? null : name,
        lastUsed: ref.read(clockProvider)(),
      ),
    );
    await ref.read(accountSlotStoreProvider).save(state);
  }

  /// Opens [id], a signed-in account, in place of the one on screen. A
  /// sign-in that had not finished is dropped.
  Future<void> switchTo(String id) async {
    final slot = state.byId(id);
    if (slot == null || !slot.signedIn) return;
    final now = ref.read(clockProvider)();
    state = AccountSlots(
      active: id,
      slots: [
        for (final s in state.slots)
          if (s.id == id) s.copyWith(lastUsed: now) else if (s.signedIn) s,
      ],
    );
    await ref.read(accountSlotStoreProvider).save(state);
  }

  /// The account on screen was signed out and its data wiped: it is no
  /// longer listed. The most recently used other account opens, or sign-in
  /// if there is none; returns the one opened.
  Future<String?> removeCurrent() async {
    final id = state.active;
    if (id == null) return null;
    var next = state.without(id);
    final other = next.signedIn.isEmpty ? null : next.signedIn.first;
    if (other != null) {
      next = next
          .put(other.copyWith(lastUsed: ref.read(clockProvider)()))
          .activate(other.id);
    }
    state = next;
    await ref.read(accountSlotStoreProvider).save(state);
    return other?.id;
  }

  /// Account [id], one not on screen, was signed out and its data wiped: it
  /// is no longer listed.
  Future<void> remove(String id) async {
    if (id == state.active || state.byId(id) == null) return;
    state = state.without(id);
    await ref.read(accountSlotStoreProvider).save(state);
  }

  /// Account [id] is no longer signed in here (the server revoked this
  /// device, or its session is gone): it leaves the list. If it is the one
  /// on screen it stays there for sign-in, which reuses its folder.
  Future<void> lost(String id) async {
    final slot = state.byId(id);
    if (slot == null || !slot.signedIn) return;
    state = id == state.active
        ? state.put(slot.copyWith(signedIn: false))
        : state.without(id);
    await ref.read(accountSlotStoreProvider).save(state);
  }

  /// What account [id] calls itself, as its own database says, so the lists
  /// show a number and a name even for an account that was linked or kept
  /// from before there were several.
  Future<void> describe(String id, {String? e164, String? name}) async {
    final slot = state.byId(id);
    if (slot == null || !slot.signedIn) return;
    final next = slot.copyWith(
      e164: e164 == null || e164.isEmpty ? null : e164,
      name: name == null || name.isEmpty ? null : name,
    );
    if (next == slot) return;
    state = state.put(next);
    await ref.read(accountSlotStoreProvider).save(state);
  }
}

/// The account on screen and its server, or null on sign-in. A record, so a
/// change elsewhere in the list does not reopen the runtime.
final activeAccountProvider = Provider<({String id, Uri server})?>((ref) {
  final current = ref.watch(accountsProvider).current;
  return current == null ? null : (id: current.id, server: current.serverUrl);
});

/// The server the account on screen talks to, or null on sign-in.
final serverUrlProvider = Provider<Uri?>(
  (ref) => ref.watch(activeAccountProvider)?.server,
);

/// Whether the accounts have been read back from the keystore yet.
///
/// The cold-start app lock needs it: before the read, "signed out" only means
/// "not looked yet", and a device with a saved session must not be treated as
/// a fresh sign-in.
enum SessionRestore {
  /// The keystore has not been read.
  pending,

  /// An account was remembered and the app was pointed at it.
  restored,

  /// Nothing remembered: a first install, a wipe or a sign-out.
  none,
}

final sessionRestoreProvider =
    NotifierProvider<SessionRestoreNotifier, SessionRestore>(
      SessionRestoreNotifier.new,
    );

class SessionRestoreNotifier extends Notifier<SessionRestore> {
  @override
  SessionRestore build() => SessionRestore.pending;

  void finish({required bool restored}) =>
      state = restored ? SessionRestore.restored : SessionRestore.none;
}

/// The live runtime, or the reason there is not one yet.
///
/// Watching this is how the app learns that the account or its server
/// changed: the old
/// runtime is closed by [runtimeProvider]'s `onDispose` before the new one
/// opens.
final runtimeProvider = FutureProvider<HelixRuntime>((ref) async {
  final active = ref.watch(activeAccountProvider);
  if (active == null) {
    throw const NoServerChosen();
  }
  final runtime = await ref
      .watch(runtimeFactoryProvider)
      .open(account: active.id, serverUrl: active.server);
  ref.onDispose(runtime.close);
  // Another engine took the database lease over (a push isolate while this
  // app was frozen). The old engine has stopped; opening a new runtime takes
  // the lease back, which either succeeds or surfaces EngineAlreadyRunning as
  // it already does for a second window.
  ref.onDispose(runtime.leaseLost.listen((_) => ref.invalidateSelf()).cancel);
  return runtime;
});

/// Thrown by [runtimeProvider] before a server is chosen. Sign-in is what
/// chooses one, so this is the normal "nobody is signed in" state rather than
/// a failure.
final class NoServerChosen implements Exception {
  const NoServerChosen();

  @override
  String toString() => 'no server has been chosen yet';
}

/// This device's name and platform, sent with registration so the account's
/// other devices can label it.
final engineConfigProvider = FutureProvider<EngineConfig>((ref) async {
  final platform = currentDevicePlatform;
  return engineConfigFor(
    deviceName: await _deviceName(platform),
    platform: platform,
  );
});

Future<String> _deviceName(DevicePlatform platform) async {
  final model = switch (platform) {
    DevicePlatform.android => await _androidModel(),
    DevicePlatform.windows => Platform.operatingSystemVersion,
    _ => null,
  };
  final label = model?.trim();
  if (label == null || label.isEmpty) return 'Helix device';
  return label.length <= 60 ? label : label.substring(0, 60);
}

Future<String?> _androidModel() async {
  try {
    return (await DeviceInfoPlugin().androidInfo).model;
  } on Object {
    // No plugin (tests, a platform without it): the generic name is fine.
    return null;
  }
}

/// `EngineConfig` for tests: short timers, and no wiping so a revocation can
/// be inspected.
EngineConfig testEngineConfig({EngineConfig? base}) =>
    (base ?? const EngineConfig()).copyWith(
      maintenanceInterval: const Duration(seconds: 30),
    );
