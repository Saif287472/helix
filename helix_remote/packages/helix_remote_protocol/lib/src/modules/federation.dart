import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/src/envelope.dart';
import 'package:helix_remote_protocol/src/ids.dart';
import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/calls.dart';
import 'package:helix_remote_protocol/src/modules/groups.dart';
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

// ------------------------------------------------------------------ groups
//
// A group lives on its home server (where it was created), which keeps the
// roster. Every account id in these payloads is in the *receiving* server's
// frame: bare for that server's own accounts, `uuid@domain` otherwise.

/// `POST /v1/s2s/groups/{group_id}/actions`: a member on the calling server
/// acts on a group homed on the receiving server. [action] names the client
/// route ([S2SGroupAction.kinds]); [params] are its path parameters and
/// [body] its JSON body. Answered with [S2SGroupActionResult].
final class S2SGroupAction {
  const S2SGroupAction({
    required this.actor,
    required this.action,
    this.actorDevice,
    this.params = const {},
    this.body,
  });

  static const kinds = {
    'delete',
    'set_state',
    'set_settings',
    'add_members',
    'remove_member',
    'set_role',
    'ban',
    'unban',
    'create_link',
    'revoke_link',
    'preview',
    'join',
    'join_requests',
    'resolve_join',
    'send',
    // A member's server reports that member's current devices.
    'devices',
  };

  /// `uuid@<calling domain>`.
  final String actor;
  final String? actorDevice;
  final String action;
  final Map<String, String> params;
  final JsonMap? body;

  JsonMap toJson() => compact({
    'actor': actor,
    'actor_device': actorDevice,
    'action': action,
    'params': params,
    'body': body,
  });

  factory S2SGroupAction.fromJson(JsonReader json) {
    final params = json.optObject('params');
    return S2SGroupAction(
      actor: json.nonEmpty('actor'),
      actorDevice: json.optString('actor_device'),
      action: json.nonEmpty('action'),
      params: {
        if (params != null)
          for (final k in params.json.keys) k: params.string(k),
      },
      body: json.optObject('body')?.json,
    );
  }
}

/// The home server's answer to an action: the status and JSON body its own
/// route would have returned (errors in the usual error shape).
final class S2SGroupActionResult {
  const S2SGroupActionResult({required this.status, this.body});

  final int status;
  final JsonMap? body;

  JsonMap toJson() => compact({'status': status, 'body': body});

  factory S2SGroupActionResult.fromJson(JsonReader json) =>
      S2SGroupActionResult(
        status: json.integer('status'),
        body: json.optObject('body')?.json,
      );
}

/// `POST /v1/s2s/groups/{group_id}/sync`: the home server pushes the
/// current group (null once deleted) and the roster change to deliver to
/// [notify] (the receiver's accounts).
final class S2SGroupSync {
  const S2SGroupSync({
    required this.rosterVersion,
    this.group,
    this.event,
    this.notify = const [],
  });

  /// Increases with every change; older snapshots are ignored.
  final int rosterVersion;
  final Group? group;
  final RosterChangeEvent? event;
  final List<String> notify;

  JsonMap toJson() => compact({
    'roster_version': rosterVersion,
    'group': group?.toJson(),
    'event': event?.toJson(),
    'notify': notify,
  });

  factory S2SGroupSync.fromJson(JsonReader json) => S2SGroupSync(
    rosterVersion: json.integer('roster_version'),
    group: json.has('group') ? Group.fromJson(json.object('group')) : null,
    event: json.has('event')
        ? RosterChangeEvent.fromJson(json.object('event'))
        : null,
    notify: json.optStrings('notify'),
  );
}

/// The receiver's members of the group with their current devices, and
/// the accounts it refused to add (unknown, privacy or blocks).
final class S2SGroupSyncResponse {
  const S2SGroupSyncResponse({
    this.devices = const {},
    this.rejected = const [],
  });

  final Map<String, List<String>> devices;
  final List<String> rejected;

  JsonMap toJson() => {'devices': devices, 'rejected': rejected};

  factory S2SGroupSyncResponse.fromJson(JsonReader json) {
    final devices = json.optObject('devices');
    return S2SGroupSyncResponse(
      devices: {
        if (devices != null)
          for (final k in devices.json.keys) k: devices.strings(k),
      },
      rejected: json.optStrings('rejected'),
    );
  }
}

/// `POST /v1/s2s/groups/{group_id}/messages`: the home server fans a group
/// message out to the receiver's member [devices], with the pairwise
/// sender-key [distributions] for them.
final class S2SGroupMessage {
  const S2SGroupMessage({
    required this.id,
    required this.sender,
    required this.senderDevice,
    required this.payload,
    required this.devices,
    this.distributions = const [],
    this.urgent = true,
    this.ephemeral = false,
  });

  final String id;
  final String sender;
  final String senderDevice;
  final Uint8List payload;
  final List<String> devices;
  final List<DevicePayload> distributions;
  final bool urgent;
  final bool ephemeral;

  JsonMap toJson() => {
    'id': id,
    'sender': sender,
    'sender_device': senderDevice,
    'payload': encodeBytes(payload),
    'devices': devices,
    'distributions': [for (final d in distributions) d.toJson()],
    'urgent': urgent,
    'ephemeral': ephemeral,
  };

  factory S2SGroupMessage.fromJson(JsonReader json) => S2SGroupMessage(
    id: json.nonEmpty('id'),
    sender: json.nonEmpty('sender'),
    senderDevice: json.nonEmpty('sender_device'),
    payload: json.bytes('payload'),
    devices: json.strings('devices'),
    distributions: json.optObjects('distributions', DevicePayload.fromJson),
    urgent: json.flag('urgent', orElse: true),
    ephemeral: json.flag('ephemeral'),
  );
}

/// Group invite tokens name their group and home server:
/// `grp_<secret>.<group uuid>@<domain>` (the secret alone on servers
/// without federation). Null parts when the token has no such suffix.
({String? groupId, String? domain}) groupInviteTokenParts(String token) {
  final at = token.lastIndexOf('@');
  if (at < 0) return (groupId: null, domain: null);
  final domain = token.substring(at + 1).toLowerCase();
  final head = token.substring(0, at);
  final dot = head.lastIndexOf('.');
  if (dot < 0 || !AccountAddress.isValidDomain(domain)) {
    return (groupId: null, domain: null);
  }
  final groupId = head.substring(dot + 1);
  return Uuid.isValid(groupId)
      ? (groupId: groupId, domain: domain)
      : (groupId: null, domain: null);
}
