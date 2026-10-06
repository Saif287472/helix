import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/src/envelope.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// One sealed payload for one device.
final class DevicePayload {
  const DevicePayload({required this.device, required this.payload});

  final String device;
  final Uint8List payload;

  JsonMap toJson() => {'device': device, 'payload': encodeBytes(payload)};

  factory DevicePayload.fromJson(JsonReader json) => DevicePayload(
    device: json.nonEmpty('device'),
    payload: json.bytes('payload'),
  );
}

/// All payloads for one account. The server requires a payload for every
/// active device of the account (except the sending device itself), so a
/// sender can never silently miss a device; otherwise `device_list_stale`.
final class Recipient {
  const Recipient({required this.account, required this.devices});

  /// Account id, or `id@domain` for an account on another server.
  final String account;
  final List<DevicePayload> devices;

  JsonMap toJson() => {
    'account': account,
    'devices': [for (final d in devices) d.toJson()],
  };

  factory Recipient.fromJson(JsonReader json) => Recipient(
    account: json.nonEmpty('account'),
    devices: json.objects('devices', DevicePayload.fromJson),
  );
}

/// `POST /v1/messages`: pairwise delivery. One request carries the payloads
/// for the peer's devices and the sender's own other devices.
final class SendMessageRequest {
  const SendMessageRequest({
    required this.id,
    required this.recipients,
    this.urgent = true,
    this.ephemeral = false,
  });

  /// At most this many sealed bytes per device payload.
  static const maxPayloadBytes = 256 * 1024;

  /// Client-chosen UUIDv7, used as the delivery id of every resulting
  /// envelope and as the idempotency key.
  final String id;
  final List<Recipient> recipients;

  /// Push-wake offline devices (false for receipts and similar).
  final bool urgent;

  /// Deliver only to devices online right now; never stored (typing).
  final bool ephemeral;

  JsonMap toJson() => {
    'id': id,
    'recipients': [for (final r in recipients) r.toJson()],
    'urgent': urgent,
    'ephemeral': ephemeral,
  };

  factory SendMessageRequest.fromJson(JsonReader json) => SendMessageRequest(
    id: json.nonEmpty('id'),
    recipients: json.objects('recipients', Recipient.fromJson),
    urgent: json.flag('urgent', orElse: true),
    ephemeral: json.flag('ephemeral'),
  );
}

final class SendMessageResponse {
  const SendMessageResponse({required this.acceptedAt, this.replayed = false});

  final DateTime acceptedAt;

  /// The same request id was already accepted; nothing was sent again.
  final bool replayed;

  JsonMap toJson() => {
    'accepted_at': toWireTime(acceptedAt),
    if (replayed) 'replayed': true,
  };

  factory SendMessageResponse.fromJson(JsonReader json) => SendMessageResponse(
    acceptedAt: json.time('accepted_at'),
    replayed: json.flag('replayed'),
  );
}

/// `GET /v1/mailbox?after=<seq>&limit=<n>`: stored envelopes for this device,
/// oldest first.
final class MailboxPage {
  const MailboxPage({
    required this.envelopes,
    required this.lastSeq,
    required this.more,
  });

  final List<Envelope> envelopes;

  /// Highest `seq` currently in the mailbox (0 when empty).
  final int lastSeq;
  final bool more;

  JsonMap toJson() => {
    'envelopes': [for (final e in envelopes) e.toJson()],
    'last_seq': lastSeq,
    'more': more,
  };

  factory MailboxPage.fromJson(JsonReader json) => MailboxPage(
    envelopes: json.objects('envelopes', Envelope.fromJson),
    lastSeq: json.integer('last_seq'),
    more: json.boolean('more'),
  );
}

/// `POST /v1/mailbox/ack`: cumulative, like the realtime `ack` frame.
final class AckRequest {
  const AckRequest({required this.seq});

  final int seq;

  JsonMap toJson() => {'seq': seq};

  factory AckRequest.fromJson(JsonReader json) =>
      AckRequest(seq: json.integer('seq'));
}

final class AckResponse {
  const AckResponse({required this.deleted});

  final int deleted;

  JsonMap toJson() => {'deleted': deleted};

  factory AckResponse.fromJson(JsonReader json) =>
      AckResponse(deleted: json.integer('deleted'));
}

/// `POST /v1/groups/{group_id}/messages`: one sender-key ciphertext that the
/// server fans out to every member device, plus pairwise
/// [distributions] for member devices that lack the sender's current key.
final class GroupMessageRequest {
  const GroupMessageRequest({
    required this.id,
    required this.payload,
    required this.devicesDigest,
    this.distributions = const [],
    this.urgent = true,
    this.ephemeral = false,
  });

  final String id;

  /// A `SenderKeyMessage` (CRYPTO_V2.md §7).
  final Uint8List payload;

  /// [membersDigest] of the member devices the sender believes exist. If it
  /// does not match the server's view the request fails with
  /// `device_list_stale` listing the current devices, so a new device can
  /// never miss the sender key.
  final Uint8List devicesDigest;
  final List<Recipient> distributions;
  final bool urgent;
  final bool ephemeral;

  JsonMap toJson() => {
    'id': id,
    'payload': encodeBytes(payload),
    'devices_digest': encodeBytes(devicesDigest),
    'distributions': [for (final r in distributions) r.toJson()],
    'urgent': urgent,
    'ephemeral': ephemeral,
  };

  factory GroupMessageRequest.fromJson(JsonReader json) => GroupMessageRequest(
    id: json.nonEmpty('id'),
    payload: json.bytes('payload'),
    devicesDigest: json.bytes('devices_digest'),
    distributions: json.optObjects('distributions', Recipient.fromJson),
    urgent: json.flag('urgent', orElse: true),
    ephemeral: json.flag('ephemeral'),
  );
}

/// SHA-256 over the sorted `account:device` lines of every member device
/// (one per line, `\n`-terminated). Both sides compute it the same way.
Uint8List membersDigest(Map<String, Iterable<String>> devicesByAccount) {
  final lines = <String>[
    for (final entry in devicesByAccount.entries)
      for (final device in entry.value) '${entry.key}:$device',
  ]..sort();
  final buffer = StringBuffer();
  for (final line in lines) {
    buffer
      ..write(line)
      ..write('\n');
  }
  return Uint8List.fromList(
    crypto.sha256.convert(utf8.encode(buffer.toString())).bytes,
  );
}
