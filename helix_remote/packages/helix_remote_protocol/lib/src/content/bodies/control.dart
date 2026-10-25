part of '../bodies.dart';

/// The bodies that carry protocol state rather than a message: typing, group
/// and profile keys, decryption failures, resends and own-device contact sync
/// (CONTENT_V2.md §4).

enum TypingState implements WireEnum {
  started('started'),
  stopped('stopped');

  const TypingState(this.wire);

  @override
  final String wire;
}

final class TypingBody extends ContentBody {
  const TypingBody({required this.state});

  static const typeName = 'typing';

  final TypingState state;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'state': state.wire};

  factory TypingBody.fromJson(JsonReader json) =>
      TypingBody(state: json.enumValue('state', TypingState.values));
}

final class SenderKeyDistributionBody extends ContentBody {
  const SenderKeyDistributionBody({
    required this.groupId,
    required this.distributionId,
    required this.iteration,
    required this.chainKey,
    required this.signingKey,
  });

  static const typeName = 'sender_key_distribution';

  final String groupId;
  final String distributionId;
  final int iteration;
  final Uint8List chainKey;

  /// Ed25519 public key.
  final Uint8List signingKey;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'group_id': groupId,
    'dist_id': distributionId,
    'iteration': iteration,
    'chain_key': encodeBytes(chainKey),
    'signing_key': encodeBytes(signingKey),
  };

  factory SenderKeyDistributionBody.fromJson(JsonReader json) =>
      SenderKeyDistributionBody(
        groupId: json.id('group_id'),
        distributionId: json.id('dist_id'),
        iteration: json.intIn('iteration', 0, ContentLimits.maxCounter),
        chainKey: json.bytesOf('chain_key', ContentLimits.keyBytes),
        signingKey: json.bytesOf('signing_key', ContentLimits.keyBytes),
      );
}

final class GroupKeyBody extends ContentBody {
  const GroupKeyBody({
    required this.groupId,
    required this.epoch,
    required this.key,
  });

  static const typeName = 'group_key';

  final String groupId;
  final int epoch;
  final Uint8List key;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'group_id': groupId,
    'epoch': epoch,
    'key': encodeBytes(key),
  };

  factory GroupKeyBody.fromJson(JsonReader json) => GroupKeyBody(
    groupId: json.id('group_id'),
    epoch: json.intIn('epoch', 0, ContentLimits.maxCounter),
    key: json.bytesOf('key', ContentLimits.keyBytes),
  );
}

final class ProfileKeyUpdateBody extends ContentBody {
  const ProfileKeyUpdateBody({required this.key, required this.version});

  static const typeName = 'profile_key_update';

  final Uint8List key;
  final int version;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'key': encodeBytes(key), 'version': version};

  factory ProfileKeyUpdateBody.fromJson(JsonReader json) =>
      ProfileKeyUpdateBody(
        key: json.bytesOf('key', ContentLimits.keyBytes),
        version: json.intIn('version', 0, ContentLimits.maxCounter),
      );
}

final class DecryptionErrorBody extends ContentBody {
  const DecryptionErrorBody({
    required this.messageId,
    required this.senderDevice,
  });

  static const typeName = 'decryption_error';

  /// Envelope delivery id of the message that failed.
  final String messageId;
  final String senderDevice;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'message_id': messageId, 'sender_device': senderDevice};

  factory DecryptionErrorBody.fromJson(JsonReader json) => DecryptionErrorBody(
    messageId: json.id('message_id'),
    senderDevice: json.id('sender_device'),
  );
}

final class ResendRequestBody extends ContentBody {
  const ResendRequestBody({required this.ids});

  static const typeName = 'resend_request';

  final List<String> ids;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'ids': ids};

  factory ResendRequestBody.fromJson(JsonReader json) => ResendRequestBody(
    ids: json.ids('ids', maxItems: ContentLimits.maxIdsPerReceipt),
  );
}

final class ContactSyncEntry {
  const ContactSyncEntry({required this.account, this.nickname});

  final String account;
  final String? nickname;

  JsonMap toJson() => compact({'account': account, 'nickname': nickname});

  factory ContactSyncEntry.fromJson(JsonReader json) => ContactSyncEntry(
    account: json.id('account'),
    nickname: json.optName('nickname'),
  );
}

/// Own devices only: renames made on another device.
final class ContactSyncBody extends ContentBody {
  const ContactSyncBody({required this.entries});

  static const typeName = 'contact_sync';

  final List<ContactSyncEntry> entries;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'entries': [for (final e in entries) e.toJson()],
  };

  factory ContactSyncBody.fromJson(JsonReader json) => ContactSyncBody(
    entries: json.many(
      'entries',
      ContactSyncEntry.fromJson,
      maxItems: ContentLimits.maxContactEntries,
    ),
  );
}
