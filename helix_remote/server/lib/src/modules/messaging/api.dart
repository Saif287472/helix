import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Returns the recipients (of [recipients]) who have blocked [sender]. The
/// people module installs the real policy (Phase S4); until then nobody
/// is blocked.
typedef BlockPolicy =
    Future<Set<String>> Function(
      SqlSession db,
      String sender,
      Iterable<String> recipients,
    );

/// What to deliver. Server-generated kinds use [data]; user kinds carry a
/// sealed payload per device.
final class Delivery {
  const Delivery({
    required this.kind,
    this.id,
    this.from,
    this.groupId,
    this.callId,
    this.data,
    this.urgent = false,
  });

  final EnvelopeKind kind;

  /// Delivery id; a fresh UUIDv7 when null.
  final String? id;
  final EnvelopeSender? from;
  final String? groupId;
  final String? callId;
  final JsonMap? data;
  final bool urgent;
}

/// The messaging module's facade (ADR-026): mailbox delivery for every
/// other module (groups, calls, identity signals) and mailbox reads for the
/// realtime gateway.
abstract interface class MessagingApi {
  /// Stores an envelope for each device in [payloads] (device id → sealed
  /// payload, or null for server-generated kinds) inside [tx]. Devices are
  /// woken after commit; urgent deliveries push offline devices.
  Future<void> deliver(
    Tx tx,
    Map<String, Uint8List?> payloads,
    Delivery delivery,
  );

  /// Delivers to devices online now, without storing. Returns the devices
  /// it reached.
  Future<Set<String>> deliverEphemeral(
    Map<String, Uint8List?> payloads,
    Delivery delivery,
  );

  /// Checks [addressed] (account → device ids) against the active devices,
  /// ignoring the sending device. Throws `device_list_stale` if they differ.
  Future<void> checkDevices(
    SqlSession db,
    Map<String, Set<String>> addressed, {
    required String senderAccount,
    required String senderDevice,
  });

  Future<List<Envelope>> fetch(
    String deviceId, {
    required int after,
    required int limit,
  });

  /// Deletes envelopes up to and including [seq]; returns how many.
  Future<int> ack(String deviceId, int seq);

  Future<int> lastSeq(String deviceId);

  /// An ephemeral envelope parked for the realtime gateway.
  Future<Envelope?> takeEphemeral(String ref);

  void setBlockPolicy(BlockPolicy policy);

  /// Recipients (of [recipients]) who blocked [sender].
  Future<Set<String>> blockedBy(
    SqlSession db,
    String sender,
    Iterable<String> recipients,
  );
}

/// Bus topics the messaging module publishes and the realtime gateway reads.
abstract final class MailboxTopics {
  /// `{"d": [device ids]}`: these devices have new stored envelopes.
  static const wake = 'mailbox.wake';

  /// `{"d": device id, "r": ref}`: an ephemeral envelope for one device.
  static const ephemeral = 'realtime.ephemeral';
}
