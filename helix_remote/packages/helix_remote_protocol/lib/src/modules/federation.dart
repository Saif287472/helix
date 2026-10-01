import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/src/ids.dart';
import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/calls.dart';
import 'package:helix_remote_protocol/src/modules/messaging.dart';

/// An account id as it crosses servers: a bare UUID for an account on the
/// server being talked to, `<uuid>@<domain>` for an account elsewhere. The
/// domain is the home server's authority (`host` or `host:port`),
/// lowercase.
final class AccountAddress {
  const AccountAddress._(this.id, this.domain);

  /// The account's UUID.
  final String id;

  /// The home server, or null for "this server".
  final String? domain;

  static final RegExp _domain = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*(?::[0-9]{1,5})?$',
  );

  static bool isValidDomain(String domain) =>
      domain.length <= 253 && _domain.hasMatch(domain);

  /// Parses [value]; null if it is neither a UUID nor `uuid@domain`.
  static AccountAddress? tryParse(String value) {
    final at = value.indexOf('@');
    if (at < 0) {
      return Uuid.isValid(value) ? AccountAddress._(value, null) : null;
    }
    final id = value.substring(0, at);
    final domain = value.substring(at + 1).toLowerCase();
    if (!Uuid.isValid(id) || !isValidDomain(domain)) return null;
    return AccountAddress._(id, domain);
  }

  static AccountAddress local(String id) => AccountAddress._(id, null);

  static AccountAddress remote(String id, String domain) =>
      AccountAddress._(id, domain.toLowerCase());

  bool get isRemote => domain != null;

  /// The address as seen from [localDomain]: bare when it lives there.
  AccountAddress relativeTo(String localDomain) =>
      domain == localDomain ? AccountAddress._(id, null) : this;

  /// The address as written on [fromDomain]'s wire, qualified with
  /// [homeDomain] when bare.
  String qualified(String homeDomain) => '$id@${domain ?? homeDomain}';

  @override
  String toString() => domain == null ? id : '$id@$domain';

  @override
  bool operator ==(Object other) =>
      other is AccountAddress && other.id == id && other.domain == domain;

  @override
  int get hashCode => Object.hash(id, domain);
}

/// The bytes a server signs for an S2S request (Ed25519, header
/// `x-helix-s2s-signature`, base64url):
/// `helix-s2s-v1|<server>|<timestamp ms>|<METHOD>|<path?query>|<base64url(sha256(body))>`.
List<int> s2sSigningInput({
  required String server,
  required int timestampMs,
  required String method,
  required String pathAndQuery,
  required List<int> body,
}) => utf8.encode(
  [
    'helix-s2s-v1',
    server,
    '$timestampMs',
    method.toUpperCase(),
    pathAndQuery,
    encodeBytes(crypto.sha256.convert(body).bytes),
  ].join('|'),
);

/// Allowed clock difference between two servers.
const s2sMaxSkew = Duration(minutes: 5);

/// `POST /v1/s2s/messages`: one send's payloads for the receiving server's
/// devices. [sender] is qualified with the calling server's domain, which
/// must match the signature; recipients are that server's own accounts.
final class S2SMessageBatch {
  const S2SMessageBatch({
    required this.id,
    required this.sender,
    required this.senderDevice,
    required this.recipients,
    this.urgent = true,
    this.ephemeral = false,
  });

  final String id;
  final String sender;
  final String senderDevice;
  final List<Recipient> recipients;
  final bool urgent;
  final bool ephemeral;

  JsonMap toJson() => {
    'id': id,
    'sender': sender,
    'sender_device': senderDevice,
    'recipients': [for (final r in recipients) r.toJson()],
    'urgent': urgent,
    'ephemeral': ephemeral,
  };

  factory S2SMessageBatch.fromJson(JsonReader json) => S2SMessageBatch(
    id: json.nonEmpty('id'),
    sender: json.nonEmpty('sender'),
    senderDevice: json.nonEmpty('sender_device'),
    recipients: json.objects('recipients', Recipient.fromJson),
    urgent: json.flag('urgent', orElse: true),
    ephemeral: json.flag('ephemeral'),
  );
}

/// `POST /v1/s2s/calls/{call_id}/signals`: a call signal for the receiving
/// server's devices. Answers with a [CallSignalResponse].
final class S2SCallSignal {
  const S2SCallSignal({
    required this.sender,
    required this.senderDevice,
    required this.signal,
  });

  final String sender;
  final String senderDevice;
  final CallSignalRequest signal;

  JsonMap toJson() => {
    'sender': sender,
    'sender_device': senderDevice,
    'signal': signal.toJson(),
  };

  factory S2SCallSignal.fromJson(JsonReader json) => S2SCallSignal(
    sender: json.nonEmpty('sender'),
    senderDevice: json.nonEmpty('sender_device'),
    signal: CallSignalRequest.fromJson(json.object('signal')),
  );
}
