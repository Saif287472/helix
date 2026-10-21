import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

/// One account signed in on this device: its own database file, keystore key,
/// attachments and picture, all named after [id] (see [AppPaths]).
///
/// No password and no session token is in here: the session lives in the
/// account's own encrypted database.
final class AccountSlot {
  const AccountSlot({
    required this.id,
    required this.server,
    this.signedIn = false,
    this.e164 = '',
    this.name = '',
    this.lastUsed,
  });

  /// Local to this device; never sent anywhere.
  final String id;

  /// The server URL, as typed by [Uri.toString].
  final String server;

  /// False while the sign-in that made this slot is still running. Only
  /// signed-in slots are written to the keystore.
  final bool signedIn;

  /// The account's number, when sign-in knew it (a linked device may not).
  final String e164;

  /// The account's name, when known.
  final String name;

  final DateTime? lastUsed;

  Uri get serverUrl => Uri.parse(server);

  AccountSlot copyWith({
    String? server,
    bool? signedIn,
    String? e164,
    String? name,
    DateTime? lastUsed,
  }) => AccountSlot(
    id: id,
    server: server ?? this.server,
    signedIn: signedIn ?? this.signedIn,
    e164: e164 ?? this.e164,
    name: name ?? this.name,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  static AccountSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final server = json['s'];
    if (id is! String || server is! String) return null;
    final at = json['at'];
    return AccountSlot(
      id: id,
      server: server,
      signedIn: true,
      e164: json['n'] is String ? json['n'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      lastUsed: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    's': server,
    if (e164.isNotEmpty) 'n': e164,
    if (name.isNotEmpty) 'name': name,
    if (lastUsed != null) 'at': lastUsed!.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountSlot &&
      other.id == id &&
      other.server == server &&
      other.signedIn == signedIn &&
      other.e164 == e164 &&
      other.name == name &&
      other.lastUsed == lastUsed;

  @override
  int get hashCode => Object.hash(id, server, signedIn, e164, name, lastUsed);
}

/// The app lock, a setting of the device rather than of one account: it
/// covers every account here. It goes with the last signed-in account.
final class DeviceLock {
  const DeviceLock({required this.enabled, required this.relockAfterSeconds});

  final bool enabled;
  final int relockAfterSeconds;

  static DeviceLock? fromJson(Object? json) {
    if (json is! Map) return null;
    final on = json['on'];
    final after = json['after'];
    if (on is! bool || after is! int) return null;
    return DeviceLock(enabled: on, relockAfterSeconds: after);
  }

  Map<String, Object?> toJson() => {'on': enabled, 'after': relockAfterSeconds};

  @override
  bool operator ==(Object other) =>
      other is DeviceLock &&
      other.enabled == enabled &&
      other.relockAfterSeconds == relockAfterSeconds;

  @override
  int get hashCode => Object.hash(enabled, relockAfterSeconds);
}

/// The accounts on this device, the one on screen, and the app lock that
/// covers them all.
final class AccountSlots {
  const AccountSlots({this.active, this.slots = const [], this.lock});

  /// The id of the account the app shows, or null on sign-in.
  final String? active;

  final List<AccountSlot> slots;

  /// Null until the lock was first set or read on this device (a device from
  /// before several accounts kept it in the account's own database).
  final DeviceLock? lock;

  AccountSlot? get current => active == null ? null : byId(active!);

  AccountSlot? byId(String id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  /// The signed-in accounts, most recently used first.
  List<AccountSlot> get signedIn {
    final list = slots.where((s) => s.signedIn).toList();
    list.sort((a, b) {
      final at = a.lastUsed?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastUsed?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return list;
  }

  /// What a notification for account [id] calls it: nothing on a device with
  /// one account, else its name, else the end of its number.
  String? notificationLabel(String id) {
    if (signedIn.length < 2) return null;
    final slot = byId(id);
    if (slot == null) return null;
    if (slot.name.isNotEmpty) return slot.name;
    final digits = slot.e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return null;
    return 'Number ending ${digits.substring(digits.length - 4)}';
  }

  /// [slot] in place of the one with its id, or added.
  AccountSlots put(AccountSlot slot, {String? active}) =>
      _with(active ?? this.active, [
        for (final s in slots)
          if (s.id != slot.id) s,
        slot,
      ]);

  /// Without the slot [id]; the active one becomes null if it was [id].
  AccountSlots without(String id) => _with(active == id ? null : active, [
    for (final s in slots)
      if (s.id != id) s,
  ]);

  AccountSlots activate(String? id) => _with(id, slots);

  /// [slots] with [active]; the lock is kept while one of them is signed in.
  AccountSlots _with(String? active, List<AccountSlot> slots) => AccountSlots(
    active: active,
    slots: slots,
    lock: slots.any((s) => s.signedIn) ? lock : null,
  );

  /// Only the signed-in slots, and none on screen.
  AccountSlots signedInOnly() => _with(null, [
    for (final s in slots)
      if (s.signedIn) s,
  ]);

  AccountSlots withLock(DeviceLock lock) =>
      AccountSlots(active: active, slots: slots, lock: lock);

  /// An id for a new slot: the first account's while no slot holds it (so a
  /// one-account device keeps the old file names), a random one after that.
  String newId(Random random) {
    if (byId(AppPaths.firstAccount) == null) return AppPaths.firstAccount;
    const digits = '0123456789abcdef';
    String next() =>
        List.generate(16, (_) => digits[random.nextInt(16)]).join();
    var id = next();
    while (byId(id) != null) {
      id = next();
    }
    return id;
  }

  @override
  bool operator ==(Object other) =>
      other is AccountSlots &&
      other.active == active &&
      other.lock == lock &&
      _sameSlots(other.slots, slots);

  static bool _sameSlots(List<AccountSlot> a, List<AccountSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(active, lock, Object.hashAll(slots));
}

/// The signed-in accounts and the one last on screen, in the keystore (the
/// numbers in it are personal data).
///
/// A device from before several accounts kept only the server it was signed
/// in to; [load] turns that into the first account and forgets the old entry.
final class AccountSlotStore {
  AccountSlotStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const keystoreKey = 'helix_remote_accounts';
  static const legacyServerKey = 'helix_remote_server_url';

  final FlutterSecureStorage _storage;

  Future<AccountSlots> load() async {
    final raw = await _storage.read(key: keystoreKey);
    if (raw != null && raw.isNotEmpty) return _decode(raw);
    final legacy = await _storage.read(key: legacyServerKey);
    if (legacy == null || legacy.isEmpty) return const AccountSlots();
    final migrated = AccountSlots(
      active: AppPaths.firstAccount,
      slots: [
        AccountSlot(id: AppPaths.firstAccount, server: legacy, signedIn: true),
      ],
    );
    await save(migrated);
    await _storage.delete(key: legacyServerKey);
    return migrated;
  }

  /// Writes the signed-in slots, the active one if it is signed in, and the
  /// lock. With none signed in the entry goes, the lock with it.
  Future<void> save(AccountSlots accounts) async {
    final kept = [
      for (final s in accounts.slots)
        if (s.signedIn) s,
    ];
    if (kept.isEmpty) {
      await _storage.delete(key: keystoreKey);
      return;
    }
    final active = accounts.current?.signedIn == true ? accounts.active : null;
    await _storage.write(
      key: keystoreKey,
      value: jsonEncode({
        'active': ?active,
        'accounts': [for (final s in kept) s.toJson()],
        'lock': ?accounts.lock?.toJson(),
      }),
    );
  }

  static AccountSlots _decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const AccountSlots();
      final list = json['accounts'];
      final slots = <AccountSlot>[
        if (list is List)
          for (final item in list) ?AccountSlot.fromJson(item),
      ];
      final active = json['active'];
      final known = slots.any((s) => s.id == active);
      return AccountSlots(
        active: known ? active as String : null,
        slots: slots,
        lock: slots.isEmpty ? null : DeviceLock.fromJson(json['lock']),
      );
    } on FormatException {
      // Never written by this code: as good as no accounts.
      return const AccountSlots();
    }
  }
}
