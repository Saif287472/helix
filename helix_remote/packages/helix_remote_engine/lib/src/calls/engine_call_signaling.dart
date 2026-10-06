import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart' show HelixApiException;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/calls/call_signaling.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/messaging/sender.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// [CallSignaling] over the engine's own pipes: every signal is sealed per
/// recipient device by the pairwise session manager (the same sessions that
/// carry messages, CRYPTO_V2.md §4), posted to the `calls` API, and what
/// arrives is opened under the sender device's lock with the ratchet state
/// committed before anything is acted on.
///
/// Call signals are ephemeral: a signal that cannot be opened (no session, a
/// replay, a sender whose keys cannot be fetched) is dropped, never retried
/// and never turned into a visible "could not decrypt" row. Contents are
/// never logged or stored.
final class EngineCallSignaling implements CallSignaling {
  EngineCallSignaling(this._ctx, this._sender, this._crypto);

  final EngineContext _ctx;
  final MessageSender _sender;
  final PairwiseCrypto _crypto;

  /// Where opened signals go; set by the engine when the state machine is
  /// built.
  CallSignalSink? sink;

  @override
  Future<TurnCredentials?> turnCredentials() async {
    try {
      return await _ctx.api.calls.turnCredentials();
    } on HelixApiException {
      return null; // No relay on this server, or the limit: go direct.
    }
  }

  @override
  Future<CallSignalResponse> send(
    String callId,
    CallSignalPayload payload, {
    required String account,
    Set<String>? devices,
    Duration ttl = const Duration(seconds: 60),
  }) async {
    final response = await _sender.sendSealed<CallSignalResponse>(
      content: payload.encode(),
      accounts: [account],
      onlyDevices: devices,
      post: (recipients) => _ctx.api.calls.sendSignal(
        callId,
        CallSignalRequest(
          kind: payload.type.routedAs,
          recipients: recipients,
          ttl: ttl,
        ),
      ),
    );
    return response ?? const CallSignalResponse(delivered: [], pending: []);
  }

  @override
  Future<void> setState(String callId, CallState state) =>
      _ctx.api.calls.setState(callId, state);

  @override
  Future<List<PendingCall>> pending() async =>
      (await _ctx.api.calls.pending()).calls;

  @override
  Future<CallSignalPayload?> open(PendingCall call) {
    final DeviceAddress sender;
    try {
      sender = DeviceAddress(call.from.account, call.from.device);
    } on ArgumentError {
      return Future.value();
    }
    return _open(sender, call.payload);
  }

  /// A `call_signal` envelope from the socket. Sealed ones are opened and
  /// handed to the state machine; the server's own "answered or declined on
  /// another of your devices" notice (no payload) is honoured only when it
  /// names this account.
  Future<void> onEnvelope(Envelope envelope) async {
    final from = envelope.from;
    final callId = envelope.callId;
    final target = sink;
    if (from == null || callId == null || target == null) return;
    final bytes = envelope.payload;
    if (bytes == null) {
      if (from.account != _ctx.identity.accountId) return;
      final data = envelope.data;
      if (data == null) return;
      final JsonReader json;
      try {
        json = JsonReader(data);
        if (json.string('kind') != CallSignalKind.end.wire) return;
        target.onEndedElsewhere(
          callId,
          json.enumValue('state', CallState.values),
        );
      } on FormatException {
        // A notice this version cannot read is ignored.
      }
      return;
    }
    final DeviceAddress sender;
    try {
      sender = DeviceAddress(from.account, from.device);
    } on ArgumentError {
      return;
    }
    final signal = await _open(sender, bytes);
    if (signal == null || signal.callId != callId) return;
    // Not awaited: acting on a signal may take the network (a hang-up, the
    // candidates), and the inbound pipeline must not wait for it.
    unawaited(
      target
          .onSignal(from.account, from.device, signal)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<CallSignalPayload?> _open(
    DeviceAddress sender,
    Uint8List bytes,
  ) async {
    final SealedPayload sealed;
    try {
      sealed = SealedPayload.decode(bytes);
    } on FormatException {
      return null;
    }
    if (sealed is SenderKeyMessage) return null;
    try {
      return await _crypto.runLocked(sender, () async {
        final PairwiseDecryptResult result;
        try {
          result = await _crypto.decrypt(sender, sealed);
        } on CryptoV2Exception {
          return null;
        }
        final identity = _ctx.identity;
        final aik = result.remoteIdentity.accountIdentityKey;
        if (sender.account == identity.accountId &&
            !bytesEqual(aik, identity.accountKey.publicKey)) {
          return null; // A device claiming this account under another key.
        }
        if (result.newSession && sender.account != identity.accountId) {
          final pinned = (await _ctx.db.peopleDao.byAccount(
            sender.account,
          ))?.identityKey;
          if (pinned != null && !bytesEqual(pinned, aik)) return null;
        }
        // The ratchet moved: commit it before anything acts on the signal.
        final now = _ctx.now();
        await _ctx.db.transaction(() async {
          await _ctx.sessionStore.save(result.sessions, now: now);
          final used = result.consumedOneTimePrekeyId;
          if (used != null) {
            await _ctx.db.cryptoDao.deletePrekey(PrekeyKind.oneTime, used);
          }
          if (result.newSession && sender.account != identity.accountId) {
            await _ctx.db.peopleDao.upsertPerson(
              PeopleCompanion.insert(
                accountId: sender.account,
                identityKey: Value(aik),
                updatedAt: now,
              ),
            );
          }
        });
        try {
          return CallSignalPayload.decode(result.content);
        } on FormatException {
          return null;
        }
      });
    } on TransientEngineException {
      return null;
    }
  }
}
