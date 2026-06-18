import 'dart:async';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';

class GroupMessageRouterImpl {
  GroupMessageRouterImpl({
    required this._repository,
    required this._gateway,
    required this._localFingerprint,
    required this._onReceipt,
  });

  final GroupRepository _repository;
  final GroupSignalingGateway _gateway;
  final String Function() _localFingerprint;
  final void Function(GroupMessageReceipt receipt) _onReceipt;

  static const _uuid = Uuid();

  List<String> forwardingTargetsFor(
    GroupSnapshot group,
    GroupMessageFrame frame,
  ) {
    if (group.hostFingerprint != _localFingerprint()) {
      return const [];
    }
    return group.members
        .map((m) => m.fingerprint)
        .where((fp) => fp != _localFingerprint())
        .where((fp) => fp != frame.senderFingerprint)
        .where((fp) => !group.banned.contains(fp))
        .toList()
      ..sort();
  }

  Future<GroupMessageFrame> sendGroupPayload({
    required String groupId,
    required Uint8List encryptedPayload,
  }) async {
    final group = _repository.loadGroup(groupId);
    if (group == null) throw ArgumentError('Unknown groupId');

    final frame = GroupMessageFrame(
      groupId: groupId,
      messageId: _uuid.v4(),
      senderFingerprint: _localFingerprint(),
      epoch: group.epoch,
      membershipVersion: group.membershipVersion,
      sentAt: DateTime.now().millisecondsSinceEpoch,
      encryptedPayload: encryptedPayload,
    );

    await _sendOrForward(group, frame);
    _onReceipt(
      GroupMessageReceipt(
        groupId: groupId,
        messageId: frame.messageId,
        senderFingerprint: _localFingerprint(),
        encryptedPayload: encryptedPayload,
      ),
    );
    return frame;
  }

  Future<void> _sendOrForward(
    GroupSnapshot group,
    GroupMessageFrame frame,
  ) async {
    final lf = _localFingerprint();
    if (group.hostFingerprint == lf) {
      await _broadcastMessage(group, frame);
      return;
    }
    await _gateway.sendMessage(group.hostFingerprint, frame);
  }

  Future<void> _broadcastMessage(
    GroupSnapshot group,
    GroupMessageFrame frame, {
    String? exceptFingerprint,
  }) async {
    for (final target in forwardingTargetsFor(group, frame)) {
      if (target == exceptFingerprint) continue;
      try {
        await _gateway.sendMessage(target, frame);
      } catch (_) {}
    }
  }

  Future<void> broadcastControl(
    GroupSnapshot group,
    GroupControlFrame frame, {
    String? exceptFingerprint,
  }) async {
    final lf = _localFingerprint();
    final targets =
        group.members
            .map((m) => m.fingerprint)
            .where((fp) => fp != lf)
            .where((fp) => fp != exceptFingerprint)
            .where((fp) => !group.banned.contains(fp))
            .toList()
          ..sort();
    for (final target in targets) {
      try {
        await _gateway.sendControl(target, frame);
      } catch (_) {}
    }
  }
}
