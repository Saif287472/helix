import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/features/phone_book.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// How people are shown (AGENTS.md product rules): the phone-book name, then
/// the nickname the user gave them, then their number, then `~Helix name`.
/// A profile name and, last of all, a short id are fallbacks so a row is
/// never blank.
abstract final class PersonNaming {
  static String displayName(PersonRow person) {
    String? nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s;
    return nonEmpty(person.phonebookName) ??
        nonEmpty(person.nickname) ??
        nonEmpty(person.phoneNumber) ??
        (nonEmpty(person.helixName) == null ? null : '~${person.helixName}') ??
        nonEmpty(person.profileName) ??
        'Helix user ${person.accountId.substring(0, person.accountId.length < 8 ? person.accountId.length : 8)}';
  }
}

/// The result of matching the phone book against the server.
final class PhoneBookSyncResult {
  const PhoneBookSyncResult({
    required this.checked,
    required this.found,
    required this.remainingToday,
  });

  final int checked;
  final int found;

  /// How many more numbers the daily discovery budget allows (5,000/day).
  final int remainingToday;
}

/// People: discovery, profiles, names, blocks, presence.
///
/// **Discovery** never uploads the address book: each number is hashed on
/// the device (`HMAC-SHA256(salt, E.164)`, lower-case hex) and the server
/// answers which hashes belong to accounts that allow discovery by phone.
/// **Profiles** are encrypted with the owner's profile key (CRYPTO_V2.md §9);
/// the key arrives inside the owner's messages, so only people the owner
/// has messaged can read it.
final class PeopleService {
  PeopleService(this._ctx, this._outbox, {PhoneBook? phoneBook})
    : _phoneBook = phoneBook ?? const EmptyPhoneBook();

  final EngineContext _ctx;
  final OutboxService _outbox;
  final PhoneBook _phoneBook;

  HelixDb get _db => _ctx.db;

  Future<PersonRow?> person(String account) => _db.peopleDao.byAccount(account);

  Stream<PersonRow?> watchPerson(String account) =>
      _db.peopleDao.watchByAccount(account);

  /// Everyone this device knows, in display order.
  Future<List<PersonRow>> list() => _db.peopleDao.all();

  Stream<List<PersonRow>> watchAll() => _db.peopleDao.watchAll();

  /// People whose names, nicknames, `~Helix name` or numbers contain
  /// [query]; blocked people excluded.
  Future<List<PersonRow>> search(String query, {int limit = 50}) =>
      _db.peopleDao.search(query, limit: limit);

  String displayName(PersonRow person) => PersonNaming.displayName(person);

  // ------------------------------------------------------------ discovery

  /// Matches the phone book against the server and stores the people found
  /// (with their phone-book names). Costs one discovery-budget unit per
  /// number.
  Future<PhoneBookSyncResult> syncPhoneBook() async {
    final entries = await _phoneBook.entries();
    final byHash = <String, ({String name, String number})>{};
    final salt = await _discoverySalt();
    for (final entry in entries) {
      for (final number in entry.numbers) {
        byHash[_hash(salt, number)] = (name: entry.name, number: number);
      }
    }
    final queries = byHash.keys.toList();
    var found = 0;
    var remaining = 0;
    for (var i = 0; i < queries.length; i += DiscoverRequest.maxBatch) {
      final batch = queries.skip(i).take(DiscoverRequest.maxBatch).toList();
      final response = await _ctx.api.people.discover(
        DiscoverRequest(phoneHashes: batch),
      );
      remaining = response.remainingToday;
      final now = _ctx.now();
      await _db.transaction(() async {
        for (final match in response.matches) {
          final known = byHash[match.phoneHash];
          if (known == null) continue;
          found++;
          await _db.peopleDao.upsertPerson(
            PeopleCompanion.insert(
              accountId: match.account,
              phoneHash: Value(match.phoneHash),
              phoneNumber: Value(known.number),
              phonebookName: Value(known.name),
              updatedAt: now,
            ),
          );
        }
      });
    }
    return PhoneBookSyncResult(
      checked: queries.length,
      found: found,
      remainingToday: remaining,
    );
  }

  /// Looks up one phone number (E.164). Returns the person, or null when no
  /// account with that number allows discovery by phone.
  Future<PersonRow?> findByNumber(String e164) async {
    final hash = _hash(await _discoverySalt(), e164);
    final response = await _ctx.api.people.discover(
      DiscoverRequest(phoneHashes: [hash]),
    );
    final match = response.matches
        .where((m) => m.phoneHash == hash)
        .firstOrNull;
    if (match == null) return null;
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(
        accountId: match.account,
        phoneHash: Value(hash),
        phoneNumber: Value(e164),
        updatedAt: _ctx.now(),
      ),
    );
    return _db.peopleDao.byAccount(match.account);
  }

  /// Looks up `~name` (exact match; null if there is none or it is hidden).
  Future<PersonRow?> findByHelixName(String name) async {
    try {
      final found = await _ctx.api.people.findByName(name);
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: found.account,
          helixName: Value(found.name),
          updatedAt: _ctx.now(),
        ),
      );
      return _db.peopleDao.byAccount(found.account);
    } on ApiException catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
  }

  Future<String> _discoverySalt() async {
    final cached = await _db.settingsDao.get(EngineState.discoverySalt);
    if (cached != null) return cached;
    final salt = encodeBytes((await _ctx.api.people.discoverySalt()).salt);
    await _db.settingsDao.set(EngineState.discoverySalt, salt, now: _ctx.now());
    return salt;
  }

  /// `lowercase hex(HMAC-SHA256(salt, E.164))` (the people module's
  /// contract).
  static String _hash(String saltBase64, String e164) {
    final mac = hashes.Hmac(
      hashes.sha256,
      decodeBytes(saltBase64),
    ).convert(utf8.encode(e164));
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The discovery hash of [e164] under [salt] (tests and other hosts).
  static String discoveryHash(List<int> salt, String e164) =>
      _hash(encodeBytes(salt), e164);

  // ------------------------------------------------------------- profiles

  /// Reads and decrypts [account]'s profile when this device has its
  /// profile key. Returns the new name, or null when there is nothing to
  /// show yet (no key, no profile, or no newer version).
  Future<String?> refreshProfile(String account) async {
    final person = await _db.peopleDao.byAccount(account);
    final key = person?.profileKey;
    if (person == null || key == null) return null;
    final EncryptedProfile profile;
    try {
      profile = await _ctx.api.people.profile(account);
    } on ApiException catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
    if (person.profileVersion != null &&
        profile.version <= person.profileVersion!) {
      return person.profileName;
    }
    try {
      final plain = await SealedBlobCipher.profile.open(
        secret: key,
        blob: profile.ciphertext,
        aad: SealedBlobCipher.profileAad(account, profile.version),
      );
      final content = ProfileContent.fromJson(
        JsonReader.decode(utf8.decode(plain)),
      );
      await _db.settingsDao.set(
        _aboutSetting(account),
        content.about,
        now: _ctx.now(),
      );
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: account,
          profileName: Value(content.name),
          profileVersion: Value(profile.version),
          updatedAt: _ctx.now(),
        ),
      );
      return content.name;
    } on CryptoV2Exception {
      return null; // A stale key: the owner rotated it; a newer message
      // brings the new one.
    } on FormatException {
      return null;
    }
  }

  /// The "about" line from [account]'s decrypted profile, as of the last
  /// [refreshProfile] (null when there is none).
  Future<String?> aboutOf(String account) =>
      _db.settingsDao.get(_aboutSetting(account));

  Stream<String?> watchAbout(String account) =>
      _db.settingsDao.watch(_aboutSetting(account));

  static Setting<String?> _aboutSetting(String account) =>
      Setting<String?>('people.about:$account', null);

  /// Publishes this account's name and about line, encrypted with the
  /// profile key (created on first use).
  Future<void> setOwnProfile({required String name, String? about}) async {
    final self = _ctx.identity;
    final row = (await _db.accountDao.current())!;
    final key = row.profileKey ?? newSymmetricKey(_ctx.random);
    final version = row.profileVersion + 1;
    final blob = await SealedBlobCipher.profile.seal(
      secret: key,
      plaintext: utf8.encode(
        jsonEncode(ProfileContent(name: name, about: about).toJson()),
      ),
      aad: SealedBlobCipher.profileAad(self.accountId, version),
      random: _ctx.random,
    );
    await _ctx.api.people.setOwnProfile(
      EncryptedProfile(version: version, ciphertext: blob),
    );
    await _db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: row.accountId,
        deviceId: row.deviceId,
        serverDomain: row.serverDomain,
        registeredAt: row.registeredAt,
        profileKey: Value(key),
        profileVersion: Value(version),
        profileName: Value(name),
      ),
    );
  }

  // ---------------------------------------------------- names and blocks

  /// Gives [account] a nickname (null removes it), keeps this account's
  /// other devices in sync, and writes the name into the phone's contacts
  /// when the person has a number there.
  Future<void> setNickname(String account, String? nickname) async {
    final trimmed = nickname?.trim();
    final value = trimmed == null || trimmed.isEmpty ? null : trimmed;
    final person = await _db.peopleDao.byAccount(account);
    await _db.transaction(() async {
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: account,
          nickname: Value(value),
          updatedAt: _ctx.now(),
        ),
      );
      final self = _ctx.identity.accountId;
      await _outbox.enqueueContent(
        content: ContentMessage(
          id: _ctx.ids.next(),
          sentAt: _ctx.now(),
          conversation: DirectConversation(to: self),
          body: ContactSyncBody(
            entries: [ContactSyncEntry(account: account, nickname: value)],
          ),
        ),
        audience: [self],
        urgent: false,
      );
    });
    final number = person?.phoneNumber;
    if (value != null && number != null) {
      // The phone-book name outranks the nickname, so when the phone took
      // the new name it is also the name shown here; otherwise the old
      // phone-book name would hide the rename until the next sync.
      if (await _phoneBook.saveName(number, value)) {
        await _db.peopleDao.upsertPerson(
          PeopleCompanion.insert(
            accountId: account,
            phonebookName: Value(value),
            updatedAt: _ctx.now(),
          ),
        );
      }
    }
  }

  /// Blocks [account]: the server drops its messages and calls, and so does
  /// this device.
  Future<void> block(String account) async {
    await _ctx.api.people.block(account);
    await _db.peopleDao.setBlocked(account, true, now: _ctx.now());
  }

  Future<void> unblock(String account) async {
    await _ctx.api.people.unblock(account);
    await _db.peopleDao.setBlocked(account, false, now: _ctx.now());
  }

  /// Replaces the local blocked flags with the server's list (after
  /// signing in on a new device).
  Future<void> syncBlocks() async {
    final blocked = (await _ctx.api.people.blocks()).accounts.toSet();
    final now = _ctx.now();
    await _db.transaction(() async {
      for (final account in await _db.peopleDao.blockedAccounts()) {
        if (!blocked.contains(account)) {
          await _db.peopleDao.setBlocked(account, false, now: now);
        }
      }
      for (final account in blocked) {
        await _db.peopleDao.setBlocked(account, true, now: now);
      }
    });
  }

  /// Reports [account] to the server's operators (spam, abuse,
  /// impersonation, other). A report carries no message content; [note] is
  /// the reporter's own words (at most [ReportRequest.maxNoteLength]).
  Future<void> report(
    String account,
    ReportCategory category, {
    String? note,
  }) async {
    final trimmed = note?.trim();
    await _ctx.api.people.report(
      ReportRequest(
        account: account,
        category: category,
        note: trimmed == null || trimmed.isEmpty
            ? null
            : trimmed.length <= ReportRequest.maxNoteLength
            ? trimmed
            : trimmed.substring(0, ReportRequest.maxNoteLength),
      ),
    );
  }

  Future<PresenceResponse> presence(String account) =>
      _ctx.api.people.presence(account);

  // -------------------------------------------------------------- trust

  /// The 60-digit safety number for the chat with [account], or null when
  /// no identity key is pinned yet.
  Future<SafetyNumber?> safetyNumber(String account) async {
    final pinned = (await _db.peopleDao.byAccount(account))?.identityKey;
    if (pinned == null) return null;
    final self = _ctx.identity;
    return SafetyNumber.compute(
      localAccount: self.accountId,
      localIdentityKey: self.accountKey.publicKey,
      remoteAccount: account,
      remoteIdentityKey: pinned,
    );
  }

  /// The user compared safety numbers (or scanned the code).
  Future<void> setVerified(String account, {required bool verified}) =>
      _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: account,
          identityVerified: Value(verified),
          updatedAt: _ctx.now(),
        ),
      );

  /// Devices of [account] with their trust state (CRYPTO_V2.md §2): a
  /// device is `trusted` while its certificate verifies under the pinned
  /// identity key and `stale` after a key change until it is seen again.
  Future<List<PersonDeviceRow>> devicesOf(String account) =>
      _db.peopleDao.devicesOf(account, includeStale: true);
}
