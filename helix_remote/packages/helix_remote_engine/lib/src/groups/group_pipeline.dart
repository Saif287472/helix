import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/groups/group_inbound.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_ops.dart';
import 'package:helix_remote_engine/src/groups/group_rekey.dart';
import 'package:helix_remote_engine/src/groups/group_roster.dart';
import 'package:helix_remote_engine/src/groups/group_sender.dart';
import 'package:helix_remote_engine/src/groups/group_trust.dart';
import 'package:helix_remote_engine/src/groups/groups_service.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:helix_remote_engine/src/messaging/apply.dart';
import 'package:helix_remote_engine/src/messaging/inbound.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';

/// The group code of one engine, wired together: the key stores, the roster
/// copy, the sender and rekey work the outbox worker runs ([GroupOutbox]),
/// the inbound half ([inbound]) and the user-facing [service].
final class GroupPipeline implements GroupOutbox {
  GroupPipeline({
    required EngineContext ctx,
    required PeerDirectory peers,
    required PairwiseCrypto crypto,
    required OutboxService outbox,
    required ContentApplier applier,
    required InboundHooks hooks,
  }) {
    keyring = GroupKeyring(ctx);
    senderKeys = DbSenderKeyStore(ctx);
    trust = GroupTrust(ctx);
    roster = GroupRosterSync(ctx, keyring, peers, senderKeys, trust);
    keys = GroupKeyDistributor(ctx, keyring, outbox, roster, trust);
    sender = GroupMessageSender(ctx, peers, crypto, senderKeys, roster);
    inbound = GroupInbound(
      ctx,
      roster,
      senderKeys,
      keyring,
      keys,
      applier,
      outbox,
      hooks,
    );
    service = GroupsService(
      ctx,
      roster,
      keyring,
      keys,
      senderKeys,
      outbox,
      trust,
    );
  }

  late final GroupKeyring keyring;
  late final DbSenderKeyStore senderKeys;
  late final GroupTrust trust;
  late final GroupRosterSync roster;
  late final GroupKeyDistributor keys;
  late final GroupMessageSender sender;
  late final GroupInbound inbound;
  late final GroupsService service;

  @override
  Future<void> sendContent(SendGroupContentPayload payload, String requestId) =>
      sender.send(
        groupId: payload.groupId,
        requestId: requestId,
        content: payload.content,
        urgent: payload.urgent,
        redistribute: payload.redistribute,
      );

  @override
  Future<void> rekey(GroupRekeyPayload payload) => keys.rekey(payload.groupId);
}
