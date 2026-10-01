import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';

/// `GET /v1/people/discovery-salt`. Phone hashes are
/// `lowercase hex(HMAC-SHA256(key = salt, message = E.164 number))`, a
/// single pass (v1 advertised 10,000 iterations it never used; v2 says what
/// it does). The salt is per server and not secret; it only stops hashes
/// being reused across servers. Matching stays an accepted oracle (T-5).
final class DiscoverySalt {
  const DiscoverySalt({required this.salt, required this.version});

  static const algorithm = 'hmac-sha256';

  final Uint8List salt;
  final int version;

  JsonMap toJson() => {
    'salt': encodeBytes(salt),
    'algorithm': algorithm,
    'version': version,
  };

  factory DiscoverySalt.fromJson(JsonReader json) {
    if (json.string('algorithm') != algorithm) {
      throw ProtocolFormatException('unsupported discovery hash');
    }
    return DiscoverySalt(
      salt: json.bytes('salt'),
      version: json.integer('version'),
    );
  }
}

/// `POST /v1/people/discover`.
final class DiscoverRequest {
  const DiscoverRequest({required this.phoneHashes, this.fullSync = false});

  static const maxBatch = 1000;

  final List<String> phoneHashes;

  /// The client is sending its whole address book (it may then drop matches
  /// it no longer has).
  final bool fullSync;

  JsonMap toJson() => {'phone_hashes': phoneHashes, 'full_sync': fullSync};

  factory DiscoverRequest.fromJson(JsonReader json) => DiscoverRequest(
    phoneHashes: json.strings('phone_hashes'),
    fullSync: json.flag('full_sync'),
  );
}

final class DiscoverMatch {
  const DiscoverMatch({required this.phoneHash, required this.account});

  final String phoneHash;
  final String account;

  JsonMap toJson() => {'phone_hash': phoneHash, 'account': account};

  factory DiscoverMatch.fromJson(JsonReader json) => DiscoverMatch(
    phoneHash: json.nonEmpty('phone_hash'),
    account: json.nonEmpty('account'),
  );
}

final class DiscoverResponse {
  const DiscoverResponse({required this.matches, required this.remainingToday});

  final List<DiscoverMatch> matches;

  /// Hashes this account may still look up today (daily budget).
  final int remainingToday;

  JsonMap toJson() => {
    'matches': [for (final m in matches) m.toJson()],
    'remaining_today': remainingToday,
  };

  factory DiscoverResponse.fromJson(JsonReader json) => DiscoverResponse(
    matches: json.objects('matches', DiscoverMatch.fromJson),
    remainingToday: json.integer('remaining_today'),
  );
}

/// `GET /v1/people/by-name/{name}` (only names whose owner allows it).
final class FindByNameResponse {
  const FindByNameResponse({required this.account, required this.name});

  final String account;
  final String name;

  JsonMap toJson() => {'account': account, 'name': name};

  factory FindByNameResponse.fromJson(JsonReader json) => FindByNameResponse(
    account: json.nonEmpty('account'),
    name: json.nonEmpty('name'),
  );
}

/// `GET /v1/people/{account}/profile` and `PUT /v1/profile`. The profile
/// (display name, about, avatar pointer) is encrypted with the owner's
/// profile key (CRYPTO_V2.md §9); the server stores ciphertext only.
final class EncryptedProfile {
  const EncryptedProfile({
    required this.version,
    required this.ciphertext,
    this.account,
    this.updatedAt,
  });

  static const maxBytes = 16 * 1024;

  /// Set in responses.
  final String? account;

  /// Increases with every change; part of the AEAD associated data.
  final int version;
  final Uint8List ciphertext;
  final DateTime? updatedAt;

  JsonMap toJson() => compact({
    'account': account,
    'version': version,
    'ciphertext': encodeBytes(ciphertext),
    'updated_at': updatedAt == null ? null : toWireTime(updatedAt!),
  });

  factory EncryptedProfile.fromJson(JsonReader json) => EncryptedProfile(
    account: json.optString('account'),
    version: json.integer('version'),
    ciphertext: json.bytes('ciphertext'),
    updatedAt: json.optTime('updated_at'),
  );
}

/// The decrypted profile (inside [EncryptedProfile.ciphertext]).
final class ProfileContent {
  const ProfileContent({required this.name, this.about, this.avatar});

  final String name;
  final String? about;

  /// A `MediaPointer` JSON object (persistent media).
  final JsonMap? avatar;

  JsonMap toJson() => compact({'name': name, 'about': about, 'avatar': avatar});

  factory ProfileContent.fromJson(JsonReader json) => ProfileContent(
    name: json.string('name'),
    about: json.optString('about'),
    avatar: json.optObject('avatar')?.json,
  );
}

/// `GET /v1/people/{account}/presence`, filtered by the owner's settings.
final class PresenceResponse {
  const PresenceResponse({
    required this.account,
    required this.online,
    this.lastSeenAt,
  });

  final String account;
  final bool online;

  /// Minute granularity; null when hidden.
  final DateTime? lastSeenAt;

  JsonMap toJson() => compact({
    'account': account,
    'online': online,
    'last_seen_at': lastSeenAt == null ? null : toWireTime(lastSeenAt!),
  });

  factory PresenceResponse.fromJson(JsonReader json) => PresenceResponse(
    account: json.nonEmpty('account'),
    online: json.boolean('online'),
    lastSeenAt: json.optTime('last_seen_at'),
  );
}

/// `GET /v1/people/blocks`.
final class BlockList {
  const BlockList({required this.accounts});

  final List<String> accounts;

  JsonMap toJson() => {'accounts': accounts};

  factory BlockList.fromJson(JsonReader json) =>
      BlockList(accounts: json.strings('accounts'));
}

enum Audience implements WireEnum {
  everyone('everyone'),
  contacts('contacts'),
  nobody('nobody');

  const Audience(this.wire);

  @override
  final String wire;
}

/// `GET`/`PUT /v1/people/privacy`. "Contacts" means the accounts the user
/// uploaded with `PUT /v1/people/contacts` (their phone-book matches).
final class PrivacySettings {
  const PrivacySettings({
    this.discoverableByPhone = true,
    this.discoverableByName = true,
    this.lastSeen = Audience.everyone,
    this.online = Audience.everyone,
    this.groupAdd = Audience.everyone,
  });

  final bool discoverableByPhone;
  final bool discoverableByName;
  final Audience lastSeen;
  final Audience online;

  /// Who may add this account to a group directly (others need an invite
  /// link).
  final Audience groupAdd;

  JsonMap toJson() => {
    'discoverable_by_phone': discoverableByPhone,
    'discoverable_by_name': discoverableByName,
    'last_seen': lastSeen.wire,
    'online': online.wire,
    'group_add': groupAdd.wire,
  };

  factory PrivacySettings.fromJson(JsonReader json) => PrivacySettings(
    discoverableByPhone: json.boolean('discoverable_by_phone'),
    discoverableByName: json.boolean('discoverable_by_name'),
    lastSeen: json.enumValue('last_seen', Audience.values),
    online: json.enumValue('online', Audience.values),
    groupAdd: json.enumValue('group_add', Audience.values),
  );
}

/// `PUT /v1/people/contacts`: replaces the account's contact list (used only
/// for [Audience.contacts] checks).
final class SetContactsRequest {
  const SetContactsRequest({required this.accounts});

  static const maxContacts = 5000;

  final List<String> accounts;

  JsonMap toJson() => {'accounts': accounts};

  factory SetContactsRequest.fromJson(JsonReader json) =>
      SetContactsRequest(accounts: json.strings('accounts'));
}

enum ReportCategory implements WireEnum {
  spam('spam'),
  abuse('abuse'),
  impersonation('impersonation'),
  other('other');

  const ReportCategory(this.wire);

  @override
  final String wire;
}

/// `POST /v1/people/reports`. Carries no message content.
final class ReportRequest {
  const ReportRequest({
    required this.account,
    required this.category,
    this.note,
  });

  static const maxNoteLength = 500;

  final String account;
  final ReportCategory category;
  final String? note;

  JsonMap toJson() =>
      compact({'account': account, 'category': category.wire, 'note': note});

  factory ReportRequest.fromJson(JsonReader json) => ReportRequest(
    account: json.nonEmpty('account'),
    category: json.enumValue(
      'category',
      ReportCategory.values,
      orElse: ReportCategory.other,
    ),
    note: json.optString('note'),
  );
}

final class ReportResponse {
  const ReportResponse({required this.reportId});

  final String reportId;

  JsonMap toJson() => {'report_id': reportId};

  factory ReportResponse.fromJson(JsonReader json) =>
      ReportResponse(reportId: json.nonEmpty('report_id'));
}
