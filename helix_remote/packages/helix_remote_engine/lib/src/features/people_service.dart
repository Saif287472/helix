import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  /// The largest profile photo this device publishes or keeps. A 256 px
  /// square PNG is well under it; the server's own `persistent` limit is
  /// 5 MiB, so a bigger pointer is refused rather than downloaded.
  static const maxPhotoBytes = 512 * 1024;

  /// How often a profile that is not there yet is looked for again: one
  /// request per person per day, not one per message.
  static const _profileRetry = Duration(days: 1);

  /// Reads and decrypts [account]'s profile when this device has its
  /// profile key. Returns the new name, or null when there is nothing to
  /// show yet (no key, no profile, or no newer version).
  ///
  /// The photo the profile points at is fetched with it: its bytes go to the
  /// people row, which is what every avatar in the app draws. A picture that
  /// cannot be had never fails the read - the pointer is kept and tried again
  /// on the next refresh.
  Future<String?> refreshProfile(String account) async {
    final person = await _db.peopleDao.byAccount(account);
    final key = person?.profileKey;
    if (person == null || key == null) return null;
    final EncryptedProfile profile;
    try {
      profile = await _ctx.api.people.profile(account);
    } on ApiException catch (e) {
      if (e.code == ErrorCode.notFound) {
        await _db.settingsDao.set(
          _lookedSetting(account),
          _ctx.now().millisecondsSinceEpoch,
          now: _ctx.now(),
        );
        return null;
      }
      rethrow;
    }
    if (person.profileVersion != null &&
        profile.version <= person.profileVersion!) {
      if (person.avatarBlob == null) {
        // The name is known; only a photo whose fetch failed is tried again.
        final stored = await _db.settingsDao.get(_photoSetting(account));
        await _keepPhoto(account, _storedPhoto(stored));
      }
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
      final photo = _photoOf(content.avatar);
      await _db.settingsDao.set(
        _photoSetting(account),
        photo == null ? null : jsonEncode(photo.toJson()),
        now: _ctx.now(),
      );
      final bytes = photo == null ? null : await _downloadPhoto(photo);
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: account,
          profileName: Value(content.name),
          profileVersion: Value(profile.version),
          // A picture that could not be fetched this time keeps the one this
          // device has; a profile with no picture clears it.
          avatarBlob: _avatarColumn(bytes, hadPhoto: photo != null),
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

  /// [account] sent a profile-key update, or this device has never read their
  /// profile and a message just brought their key: the profile (name, about
  /// and photo) is worth a read now. At most one request per person per day
  /// until it lands.
  Future<bool> profileNeedsRead(String account) async {
    final person = await _db.peopleDao.byAccount(account);
    if (person == null || person.profileKey == null) return false;
    if (person.profileVersion != null) return false;
    final looked = await _db.settingsDao.get(_lookedSetting(account));
    if (looked == null) return true;
    return _ctx.now().difference(
          DateTime.fromMillisecondsSinceEpoch(looked, isUtc: true),
        ) >
        _profileRetry;
  }

  /// Writes the photo of [pointer] (fetched, checked and decrypted) into the
  /// people row, or does nothing when it cannot be had.
  Future<void> _keepPhoto(String account, MediaPointer? pointer) async {
    if (pointer == null) return;
    final bytes = await _downloadPhoto(pointer);
    if (bytes == null) return;
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(
        accountId: account,
        avatarBlob: Value(bytes),
        updatedAt: _ctx.now(),
      ),
    );
  }

  static Value<Uint8List?> _avatarColumn(
    Uint8List? bytes, {
    required bool hadPhoto,
  }) {
    if (!hadPhoto) return const Value(null);
    return bytes == null ? const Value.absent() : Value(bytes);
  }

  /// The photo the server holds for [pointer], or null when it cannot be
  /// fetched, is bigger than the pointer says, or does not hash to its
  /// digest. Never throws: a profile read is not failed by a picture.
  Future<Uint8List?> _downloadPhoto(MediaPointer pointer) async {
    if (pointer.size <= 0 || pointer.size > maxPhotoBytes) return null;
    try {
      final download = await _ctx.api.media.download(
        pointer.id,
        maxBytes: AttachmentCrypto.ciphertextLength(pointer.size),
      );
      final plain = await AttachmentCrypto.decryptBytes(
        download.bytes,
        pointer.key,
        digest: pointer.digest,
      );
      return plain.length == pointer.size ? plain : null;
    } on Object {
      return null;
    }
  }

  /// The pointer a profile carries, or null when there is none or it is not a
  /// pointer this version understands (a newer client must not fail the read).
  static MediaPointer? _photoOf(JsonMap? json) {
    if (json == null) return null;
    try {
      return MediaPointer.fromJson(JsonReader(json));
    } on Object {
      return null;
    }
  }

  static MediaPointer? _storedPhoto(Object? stored) {
    if (stored is! String || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      return decoded is JsonMap ? _photoOf(decoded) : null;
    } on Object {
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

  /// The profile's photo pointer, kept so a failed fetch can be retried
  /// without reading the profile again (and, for this account, so a later
  /// name-only save republishes the same picture).
  static Setting<String?> _photoSetting(String account) =>
      Setting<String?>('people.photo:$account', null);

  /// When a profile that was not there was last looked for (epoch ms).
  static Setting<int?> _lookedSetting(String account) =>
      Setting<int?>('people.looked:$account', null);

  /// Publishes this account's name, about line and photo, encrypted with the
  /// profile key (created on first use).
  ///
  /// The server keeps the highest version. A device whose count started
  /// again (a new install signed in with the password, an account registered
  /// again on its number) is behind a profile it cannot read: the server
  /// says `version_conflict`, and the profile is published again just above
  /// the server's version, so what the person typed is what is saved.
  ///
  /// [photoBytes] is a picture this device publishes: it is encrypted with a
  /// fresh key, stored as a `persistent` media object and carried in the
  /// profile as a pointer, so only someone who can read the profile (a person
  /// this account messaged) can fetch it. Omit it to keep the picture already
  /// published; [clearPhoto] takes it away. Either way the object the profile
  /// used before is deleted.
  Future<void> setOwnProfile({
    required String name,
    String? about,
    List<int>? photoBytes,
    bool clearPhoto = false,
  }) async {
    final self = _ctx.identity;
    final row = (await _db.accountDao.current())!;
    final key = row.profileKey ?? newSymmetricKey(_ctx.random);
    final previous = await _ownPhoto(self.accountId, key);
    final photo = photoBytes == null
        ? (clearPhoto ? null : previous)
        : await _uploadPhoto(photoBytes);
    Future<void> publish(int version) async {
      final blob = await SealedBlobCipher.profile.seal(
        secret: key,
        plaintext: utf8.encode(
          jsonEncode(
            ProfileContent(
              name: name,
              about: about,
              avatar: photo?.toJson(),
            ).toJson(),
          ),
        ),
        aad: SealedBlobCipher.profileAad(self.accountId, version),
        random: _ctx.random,
      );
      await _ctx.api.people.setOwnProfile(
        EncryptedProfile(version: version, ciphertext: blob),
      );
    }

    var version = row.profileVersion + 1;
    try {
      await publish(version);
    } on ApiException catch (e) {
      if (e.code != ErrorCode.versionConflict) rethrow;
      version = (await _ctx.api.people.profile(self.accountId)).version + 1;
      await publish(version);
    }
    await _db.settingsDao.set(
      _photoSetting(self.accountId),
      photo == null ? null : jsonEncode(photo.toJson()),
      now: _ctx.now(),
    );
    if ((previous?.id ?? '') != (photo?.id ?? '')) await _dropPhoto(previous);
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
    try {
      // The operator console's copy (ADR-030); contacts read the profile.
      await _ctx.api.people.setOwnName(name);
    } on Object {
      // Best effort: the profile itself is saved.
    }
  }

  /// The photo this account's profile carries now: the pointer this device
  /// published (kept so a name-only save does not quietly drop the picture),
  /// or - on an install that has never published from it - the one already on
  /// the server.
  Future<MediaPointer?> _ownPhoto(String account, List<int>? profileKey) async {
    final remembered = _storedPhoto(
      await _db.settingsDao.get(_photoSetting(account)),
    );
    if (remembered != null) return remembered;
    final key = profileKey;
    if (key == null) return null;
    try {
      final profile = await _ctx.api.people.profile(account);
      final plain = await SealedBlobCipher.profile.open(
        secret: key,
        blob: profile.ciphertext,
        aad: SealedBlobCipher.profileAad(account, profile.version),
      );
      return _photoOf(
        ProfileContent.fromJson(JsonReader.decode(utf8.decode(plain))).avatar,
      );
    } on Object {
      return null; // Offline, or a profile this key cannot open.
    }
  }

  /// Encrypts a profile photo with a fresh key and stores it as this account's
  /// `persistent` object. [maxPhotoBytes] is checked here as well as by the
  /// app: a pointer this device publishes must be one it would download.
  Future<MediaPointer> _uploadPhoto(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'profile photo size');
    }
    final key = AttachmentCrypto.newKey(_ctx.random);
    final sealed = await AttachmentCrypto.encryptBytes(
      bytes,
      key,
      random: _ctx.random,
    );
    final target = await _ctx.api.media.createUpload(
      CreateUploadRequest(
        size: sealed.ciphertext.length,
        kind: MediaKind.persistent,
      ),
    );
    await _ctx.api.media.upload(target, sealed.ciphertext);
    return MediaPointer(
      id: target.mediaId,
      key: key,
      digest: sealed.digest,
      size: bytes.length,
      mime: 'image/png',
    );
  }

  /// Withdraws a photo the account no longer publishes. Best effort: an object
  /// left behind goes with the account, and the `persistent` quota of 50 MiB
  /// holds many changes.
  Future<void> _dropPhoto(MediaPointer? previous) async {
    if (previous == null) return;
    try {
      await _ctx.api.media.delete(previous.id);
    } on Object {
      // The pointer is out of the profile, so nobody can read it again.
    }
  }

  /// Tells the server this account's own number and name once (after a
  /// sign-in, and once on a device that signed in before the server kept
  /// them), for the operator console (ADR-030). A failure is tried again on
  /// the next start; a number the server will not take is not.
  Future<void> reportForConsole() async {
    if (await _db.settingsDao.get(EngineState.consoleDetailsReported)) return;
    final row = await _db.accountDao.current();
    if (row == null) return;
    try {
      final phone = row.phoneNumber;
      if (phone != null && phone.isNotEmpty) {
        await _ctx.api.identity.setPhoneNumber(phone);
      }
      final name = row.profileName;
      if (name != null && name.isNotEmpty) {
        await _ctx.api.people.setOwnName(name);
      }
    } on ApiException catch (e) {
      if (e.code != ErrorCode.invalidField) return;
    } on Object {
      return;
    }
    await _db.settingsDao.set(
      EngineState.consoleDetailsReported,
      true,
      now: _ctx.now(),
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

  /// Whether [account] has blocked this account (the server told this device:
  /// REST_V2.md, blocks). Its messages are not delivered and its calls are
  /// refused until it unblocks.
  Future<bool> blocksMe(String account) =>
      _db.settingsDao.get(PersonState.blocksMe(account));

  Stream<bool> watchBlocksMe(String account) =>
      _db.settingsDao.watch(PersonState.blocksMe(account));

  /// Blocks [account]: the server drops its messages and calls (and tells
  /// it so), and so does this device.
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
