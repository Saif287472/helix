import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';

/// What a mailbox envelope carries, as far as the server knows. Everything
/// users exchange is inside [EnvelopeKind.message] or
/// [EnvelopeKind.groupMessage] payloads, which the server cannot read.
enum EnvelopeKind implements WireEnum {
  /// A pairwise `SealedMessage` (CRYPTO_V2.md §8) from another device.
  message('message'),

  /// A `SenderKeyMessage` for a group, fanned out by the server.
  groupMessage('group_message'),

  /// A call signal (offer, answer, ICE, hangup), sealed pairwise. Delivered
  /// live only; offers to offline devices also become pending calls.
  callSignal('call_signal'),

  /// Server-generated: a group's roster or roles changed.
  rosterChange('roster_change'),

  /// Server-generated: an account added or removed a device.
  deviceListChange('device_list_change'),

  /// Server-generated: an account's identity key (AIK) changed.
  keyChange('key_change'),

  /// Server-generated: something happened to this account (new sign-in,
  /// device revoked, suspension).
  accountSignal('account_signal'),

  /// Server-generated: this device should upload more one-time prekeys.
  prekeysLow('prekeys_low'),

  /// A kind this client does not know yet. Acked and ignored.
  unknown('unknown');

  const EnvelopeKind(this.wire);

  @override
  final String wire;

  bool get isServerGenerated => switch (this) {
    message || groupMessage || callSignal || unknown => false,
    _ => true,
  };
}

/// The sending device of a user-originated envelope.
final class EnvelopeSender {
  const EnvelopeSender({required this.account, required this.device});

  final String account;
  final String device;

  JsonMap toJson() => {'account': account, 'device': device};

  factory EnvelopeSender.fromJson(JsonReader json) => EnvelopeSender(
    account: json.nonEmpty('account'),
    device: json.nonEmpty('device'),
  );

  @override
  bool operator ==(Object other) =>
      other is EnvelopeSender &&
      other.account == account &&
      other.device == device;

  @override
  int get hashCode => Object.hash(account, device);
}

/// One delivery to one device.
///
/// Stored envelopes have a per-device [seq] (allocated by the server, strictly
/// increasing, with gaps allowed) and stay in the mailbox until the device
/// acks a `seq` at or above theirs. Ephemeral envelopes (typing, call
/// signals) have no [seq]: they are never stored and never acked.
final class Envelope {
  const Envelope({
    required this.id,
    required this.kind,
    required this.sentAt,
    this.seq,
    this.from,
    this.groupId,
    this.callId,
    this.payload,
    this.data,
    this.urgent = false,
  });

  /// Server-assigned delivery id (UUIDv7). The same send request gives every
  /// recipient device the same [id], so a device can de-duplicate replays.
  final String id;
  final EnvelopeKind kind;

  /// When the server accepted it.
  final DateTime sentAt;

  final int? seq;

  /// Null for server-generated kinds (and reserved for sealed sender).
  final EnvelopeSender? from;

  /// Set for [EnvelopeKind.groupMessage] and [EnvelopeKind.rosterChange].
  final String? groupId;

  /// Set for [EnvelopeKind.callSignal].
  final String? callId;

  /// Opaque sealed bytes for user-originated kinds.
  final Uint8List? payload;

  /// Plain JSON body for server-generated kinds (see the `*Event` classes).
  final JsonMap? data;

  /// The sender asked for a push wake-up if the device is offline.
  final bool urgent;

  bool get isEphemeral => seq == null;

  JsonMap toJson() => compact({
    'id': id,
    'kind': kind.wire,
    'sent_at': toWireTime(sentAt),
    'seq': seq,
    'from': from?.toJson(),
    'group_id': groupId,
    'call_id': callId,
    'payload': payload == null ? null : encodeBytes(payload!),
    'data': data,
    if (urgent) 'urgent': true,
  });

  factory Envelope.fromJson(JsonReader json) {
    final rawData = json.raw('data');
    return Envelope(
      id: json.nonEmpty('id'),
      kind: json.enumValue(
        'kind',
        EnvelopeKind.values,
        orElse: EnvelopeKind.unknown,
      ),
      sentAt: json.time('sent_at'),
      seq: json.optInt('seq'),
      from: json.has('from')
          ? EnvelopeSender.fromJson(json.object('from'))
          : null,
      groupId: json.optString('group_id'),
      callId: json.optString('call_id'),
      payload: json.optBytes('payload'),
      data: rawData == null ? null : JsonReader.of(rawData, path: 'data').json,
      urgent: json.flag('urgent'),
    );
  }
}

/// [EnvelopeKind.rosterChange] data.
enum RosterChangeKind implements WireEnum {
  created('created'),
  added('added'),
  removed('removed'),
  left('left'),
  roleChanged('role_changed'),
  settingsChanged('settings_changed'),
  stateChanged('state_changed'),
  deleted('deleted'),
  unknown('unknown');

  const RosterChangeKind(this.wire);

  @override
  final String wire;
}

final class RosterChangeEvent {
  const RosterChangeEvent({
    required this.groupId,
    required this.change,
    required this.epoch,
    this.actor,
    this.members = const [],
  });

  final String groupId;
  final RosterChangeKind change;

  /// Group epoch after the change (CRYPTO_V2.md §9).
  final int epoch;
  final String? actor;

  /// Accounts the change is about (added, removed, role changed).
  final List<String> members;

  JsonMap toJson() => compact({
    'group_id': groupId,
    'change': change.wire,
    'epoch': epoch,
    'actor': actor,
    'members': members,
  });

  factory RosterChangeEvent.fromJson(JsonReader json) => RosterChangeEvent(
    groupId: json.nonEmpty('group_id'),
    change: json.enumValue(
      'change',
      RosterChangeKind.values,
      orElse: RosterChangeKind.unknown,
    ),
    epoch: json.integer('epoch'),
    actor: json.optString('actor'),
    members: json.optStrings('members'),
  );
}

/// [EnvelopeKind.deviceListChange] data.
final class DeviceListChangeEvent {
  const DeviceListChangeEvent({required this.account});

  final String account;

  JsonMap toJson() => {'account': account};

  factory DeviceListChangeEvent.fromJson(JsonReader json) =>
      DeviceListChangeEvent(account: json.nonEmpty('account'));
}

/// [EnvelopeKind.keyChange] data.
final class KeyChangeEvent {
  const KeyChangeEvent({required this.account, required this.identityKey});

  final String account;

  /// The new AIK public key (Ed25519, 32 bytes).
  final Uint8List identityKey;

  JsonMap toJson() => {
    'account': account,
    'identity_key': encodeBytes(identityKey),
  };

  factory KeyChangeEvent.fromJson(JsonReader json) => KeyChangeEvent(
    account: json.nonEmpty('account'),
    identityKey: json.bytes('identity_key'),
  );
}

/// [EnvelopeKind.accountSignal] data.
enum AccountSignalKind implements WireEnum {
  newSignIn('new_sign_in'),
  deviceRevoked('device_revoked'),
  signedOut('signed_out'),
  suspended('suspended'),
  unsuspended('unsuspended'),
  passwordChanged('password_changed'),
  unknown('unknown');

  const AccountSignalKind(this.wire);

  @override
  final String wire;
}

final class AccountSignalEvent {
  const AccountSignalEvent({
    required this.signal,
    required this.at,
    this.device,
    this.deviceName,
  });

  final AccountSignalKind signal;
  final DateTime at;

  /// The device the signal is about (the new or revoked device).
  final String? device;
  final String? deviceName;

  JsonMap toJson() => compact({
    'signal': signal.wire,
    'at': toWireTime(at),
    'device': device,
    'device_name': deviceName,
  });

  factory AccountSignalEvent.fromJson(JsonReader json) => AccountSignalEvent(
    signal: json.enumValue(
      'signal',
      AccountSignalKind.values,
      orElse: AccountSignalKind.unknown,
    ),
    at: json.time('at'),
    device: json.optString('device'),
    deviceName: json.optString('device_name'),
  );
}

/// [EnvelopeKind.prekeysLow] data.
final class PrekeysLowEvent {
  const PrekeysLowEvent({required this.remaining});

  final int remaining;

  JsonMap toJson() => {'remaining': remaining};

  factory PrekeysLowEvent.fromJson(JsonReader json) =>
      PrekeysLowEvent(remaining: json.integer('remaining'));
}
