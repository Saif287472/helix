import 'dart:convert';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// `outbox_ops.kind` values of the group pipeline (the others are in
/// `OutboxKinds`).
abstract final class GroupOutboxKinds {
  /// Encrypt `content` once under this device's sender key and post it to
  /// the group (`POST /v1/groups/{id}/messages`).
  static const sendGroupContent = 'send_group_content';

  /// Make a new group master key for the group's current epoch, re-seal the
  /// state under it and hand the key to every member (CRYPTO_V2.md §9).
  static const groupRekey = 'group_rekey';
}

/// The plaintext of a `send_group_content` op: written with the optimistic
/// row, encrypted when the op is sent.
final class SendGroupContentPayload {
  const SendGroupContentPayload({
    required this.groupId,
    required this.content,
    this.urgent = true,
    this.redistribute = const [],
  });

  final String groupId;
  final ContentMessage content;
  final bool urgent;

  /// Devices that reported they cannot read this sender's messages
  /// (§13a): the sender key is sent to them again with this send.
  final List<DeviceAddress> redistribute;

  String encode() => jsonEncode({
    'group_id': groupId,
    'content': content.toJson(),
    'urgent': urgent,
    if (redistribute.isNotEmpty)
      'redistribute': [for (final d in redistribute) d.toJson()],
  });

  static SendGroupContentPayload decode(String payload) {
    final json = JsonReader.decode(payload);
    return SendGroupContentPayload(
      groupId: json.nonEmpty('group_id'),
      content: ContentMessage.fromJson(json.object('content')),
      urgent: json.flag('urgent', orElse: true),
      redistribute: json.optObjects('redistribute', DeviceAddress.fromJson),
    );
  }
}

/// The payload of a `group_rekey` op.
final class GroupRekeyPayload {
  const GroupRekeyPayload({required this.groupId});

  final String groupId;

  String encode() => jsonEncode({'group_id': groupId});

  static GroupRekeyPayload decode(String payload) => GroupRekeyPayload(
    groupId: JsonReader.decode(payload).nonEmpty('group_id'),
  );
}

/// What the outbox worker asks of the group pipeline.
abstract interface class GroupOutbox {
  /// Sends one group content message. Throws what the API throws, plus
  /// `GroupException` when this device is no longer in the group.
  Future<void> sendContent(SendGroupContentPayload payload, String requestId);

  /// Rotates the group master key of the group's current epoch.
  Future<void> rekey(GroupRekeyPayload payload);
}
