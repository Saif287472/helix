import 'dart:async';

import 'package:helix_groups/application/lan_lobby_server.dart';
import 'package:helix_groups/domain/lobby_constants.dart';

/// Orchestrates the two-phase graceful host transfer.
///
/// Returns the new host fingerprint and TCP port on success, or null if
/// all candidates were unreachable (caller should leave without handoff).
Future<({String newHostFp, int newPort})?> runGracefulHandoff({
  required LanLobbyServer server,
  required String         sid,
  required int            currentGen,
  required String         localFp,
  required List<String>   memberFps,
}) async {
  final candidates = memberFps.where((fp) => fp != localFp).toList()..sort();
  if (candidates.isEmpty) return null;

  for (final candidate in candidates) {
    final result = await _attemptHandoff(
      server:     server,
      sid:        sid,
      currentGen: currentGen,
      localFp:    localFp,
      candidate:  candidate,
    );
    if (result != null) return result;
  }
  return null;
}

Future<({String newHostFp, int newPort})?> _attemptHandoff({
  required LanLobbyServer server,
  required String         sid,
  required int            currentGen,
  required String         localFp,
  required String         candidate,
}) async {
  final nextGen = currentGen + 1;

  // Phase 1: ask the candidate to open its server.
  server.sendToFp(candidate, {
    'v':          kLobbyProtocolVersion,
    't':          kFtHostXferPrepare,
    'sid':        sid,
    'nextGen':    nextGen,
    'nextHostFp': candidate,
  });

  // Phase 2: wait for HTR from the candidate.
  try {
    final ready = await server.clientFrames
        .where((e) =>
            e.fp == candidate &&
            e.frame['t'] == kFtHostXferReady &&
            e.frame['sid'] == sid &&
            e.frame['nextGen'] == nextGen)
        .map((e) => e.frame)
        .first
        .timeout(kLobbyHandoffReadyTimeout);

    final newPort = ready['port'] as int?;
    if (newPort == null || newPort <= 0) return null;

    // Phase 3: commit to all clients.
    server.broadcastFrame({
      'v':          kLobbyProtocolVersion,
      't':          kFtHostXferCommit,
      'sid':        sid,
      'nextHostFp': candidate,
      'port':       newPort,
      'nextGen':    nextGen,
    });

    return (newHostFp: candidate, newPort: newPort);
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

/// Called by the candidate when it receives HOST_XFER_PREPARE.
/// Opens a [LanLobbyServer] and sends HOST_XFER_READY back via the client.
Future<LanLobbyServer?> acceptHandoffPrepare({
  required String  sid,
  required int     nextGen,
  required void Function(Map<String, dynamic>) sendToHost,
}) async {
  try {
    final newServer = LanLobbyServer();
    await newServer.open(sid: sid, gen: nextGen);

    sendToHost({
      'v':       kLobbyProtocolVersion,
      't':       kFtHostXferReady,
      'sid':     sid,
      'nextGen': nextGen,
      'port':    newServer.port,
    });

    return newServer;
  } catch (_) {
    return null;
  }
}
