import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/sender.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// `outbox_ops.kind` values.
abstract final class OutboxKinds {
  /// Encrypt `content` for the devices of `audience` and send it.
  static const sendContent = 'send_content';

  /// Start a fresh session with one device and tell it about a message we
  /// could not decrypt (CRYPTO_V2.md §13a).
  static const sessionReset = 'session_reset';
}

/// The plaintext of a `send_content` op: written with the optimistic row,
/// encrypted per recipient device only when the op is sent.
final class SendContentPayload {
  const SendContentPayload({
    required this.content,
    required this.audience,
    this.urgent = true,
  });

  final ContentMessage content;

  /// Accounts to address, this account's own included to sync its other
  /// devices.
  final List<String> audience;
  final bool urgent;

  String encode() => jsonEncode({
    'content': content.toJson(),
    'audience': audience,
    'urgent': urgent,
  });

  static SendContentPayload decode(String payload) {
    final json = JsonReader.decode(payload);
    return SendContentPayload(
      content: ContentMessage.fromJson(json.object('content')),
      audience: json.strings('audience'),
      urgent: json.flag('urgent', orElse: true),
    );
  }
}

/// The payload of a `session_reset` op.
final class SessionResetPayload {
  const SessionResetPayload({
    required this.account,
    required this.device,
    required this.messageId,
  });

  final String account;
  final String device;

  /// The envelope id of the message that could not be decrypted.
  final String messageId;

  String encode() => jsonEncode({
    'account': account,
    'device': device,
    'message_id': messageId,
  });

  static SessionResetPayload decode(String payload) {
    final json = JsonReader.decode(payload);
    return SessionResetPayload(
      account: json.nonEmpty('account'),
      device: json.nonEmpty('device'),
      messageId: json.nonEmpty('message_id'),
    );
  }
}

/// The only way work enters the outbox. Every write goes through
/// [OutboxDao.enqueue]; the [OutboxWorker] has exactly one wake-up path, the
/// queue's own change stream, so nothing waits for an unrelated trigger.
/// Call these inside the transaction that writes the optimistic row.
final class OutboxService {
  OutboxService(this._ctx);

  final EngineContext _ctx;

  /// Queues [content] for [audience]. [requestId] is the idempotency key and
  /// the id of the request; it defaults to the content id, which receivers
  /// use to name a message they could not decrypt.
  Future<OutboxOpRow> enqueueContent({
    required ContentMessage content,
    required Iterable<String> audience,
    String? conversationId,
    int? messageRowid,
    String? requestId,
    bool urgent = true,
  }) => _ctx.db.outboxDao.enqueue(
    kind: OutboxKinds.sendContent,
    idempotencyKey: requestId ?? content.id,
    payload: SendContentPayload(
      content: content,
      audience: audience.toSet().toList()..sort(),
      urgent: urgent,
    ).encode(),
    conversationId: conversationId,
    messageRowid: messageRowid,
    now: _ctx.now(),
  );

  Future<OutboxOpRow> enqueueReset(SessionResetPayload payload) =>
      _ctx.db.outboxDao.enqueue(
        kind: OutboxKinds.sessionReset,
        idempotencyKey: 'reset:${payload.device}:${payload.messageId}',
        payload: payload.encode(),
        now: _ctx.now(),
      );

  /// Puts a failed op back in the queue (the user tapped "retry") and shows
  /// its message as sending again.
  Future<void> retry(int opId) => _ctx.db.transaction(() async {
    final op = await _ctx.db.outboxDao.byId(opId);
    if (op == null) return;
    await _ctx.db.outboxDao.retry(opId, now: _ctx.now());
    final rowid = op.messageRowid;
    if (rowid != null && await _ctx.db.messagesDao.byRowid(rowid) != null) {
      await _ctx.db.messagesDao.advanceStatus(rowid, MessageStatus.pending);
    }
  });
}

/// What to do with an op after an attempt failed.
sealed class OpFailure {
  const OpFailure(this.code);

  /// An error code for `last_error`; never content.
  final String code;
}

final class RetryLater extends OpFailure {
  const RetryLater(super.code, {this.atLeast});

  final Duration? atLeast;
}

final class GiveUp extends OpFailure {
  const GiveUp(super.code);
}

final class DeviceRevoked extends OpFailure {
  const DeviceRevoked() : super('device_revoked');
}

final class SessionEnded extends OpFailure {
  const SessionEnded() : super('signed_out');
}

/// Sorts an error from an attempt into retry, give up, or an account-level
/// condition. Unknown errors retry (with backoff and the age limit) rather
/// than losing the message.
OpFailure classifyOpError(Object error) {
  switch (error) {
    case NetworkException():
      return const RetryLater('network');
    case SignedOutException():
      return const SessionEnded();
    case MalformedResponseException():
      return const RetryLater('bad_response');
    case TransientEngineException():
      return const RetryLater('transient');
    case UntrustedPeerException():
      return const GiveUp('untrusted_peer');
    case CryptoV2Exception():
      return const GiveUp('crypto');
    case ApiException():
      if (error.code == ErrorCode.deviceRevoked) return const DeviceRevoked();
      if (error.code == ErrorCode.deviceListStale) {
        return const RetryLater('device_list_stale');
      }
      if (error.isRetryable ||
          error.isUnauthenticated ||
          error.code == ErrorCode.quotaExceeded) {
        return RetryLater(error.code.wire, atLeast: error.retryAfter);
      }
      return GiveUp(error.code.wire);
    default:
      return const RetryLater('internal');
  }
}

/// Sends queued ops: claims the due ones (oldest first, one at a time per
/// conversation), encrypts and posts them through the [MessageSender], and
/// completes, reschedules with backoff or fails them.
///
/// It wakes on the queue's change stream (every enqueue, from any code
/// path) and on a timer for the next retry, and it can be driven by hand
/// with [drain] (headless runs, tests).
final class OutboxWorker {
  OutboxWorker(
    this._ctx,
    this._sender,
    this._peers,
    this._crypto, {
    required this.onDeviceRevoked,
    required this.onSessionEnded,
  });

  final EngineContext _ctx;
  final MessageSender _sender;
  final PeerDirectory _peers;
  final PairwiseCrypto _crypto;

  /// The server said this device is revoked.
  final Future<void> Function() onDeviceRevoked;

  /// The device session is gone and could not be renewed.
  final void Function() onSessionEnded;

  StreamSubscription<String>? _subscription;
  Timer? _timer;
  bool _active = false;
  bool _running = false;
  bool _again = false;
  Completer<void>? _idle;

  /// Starts listening; the first run happens at once.
  void start() {
    if (_active) return;
    _active = true;
    _subscription = _ctx.db.outboxDao.watchQueueMark().listen((_) => _poke());
  }

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _idle?.future;
  }

  void _poke() {
    if (!_active) return;
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    _idle = Completer<void>();
    try {
      do {
        _again = false;
        while (_active && await runOnce() > 0) {}
      } while (_again && _active);
    } on Object {
      // The database closed under us (sign-out, wipe): nothing to send.
    } finally {
      _running = false;
      _idle!.complete();
      if (_active) await _arm();
    }
  }

  Future<void> _arm() async {
    _timer?.cancel();
    final DateTime? next;
    try {
      next = await _ctx.db.outboxDao.nextWakeAt();
    } on Object {
      return;
    }
    if (next == null || !_active) return;
    var wait = next.difference(_ctx.now());
    if (wait < Duration.zero) wait = Duration.zero;
    if (wait > const Duration(minutes: 30)) wait = const Duration(minutes: 30);
    _timer = Timer(wait, _poke);
  }

  /// Claims and processes the due ops once. Returns how many were claimed.
  Future<int> runOnce() async {
    final now = _ctx.now();
    final claimed = await _ctx.db.outboxDao.claimDueOrdered(
      now,
      leaseUntil: now.add(_ctx.config.outboxLease),
    );
    for (final op in claimed) {
      await _process(op);
    }
    return claimed.length;
  }

  /// Runs until nothing is due (ops backing off stay queued). For headless
  /// runs and tests.
  Future<void> drain() async {
    while (await runOnce() > 0) {}
  }

  Future<void> _process(OutboxOpRow op) async {
    try {
      switch (op.kind) {
        case OutboxKinds.sendContent:
          final payload = SendContentPayload.decode(op.payload);
          await _sender.send(
            requestId: op.idempotencyKey,
            content: payload.content.encode(),
            accounts: payload.audience,
            urgent: payload.urgent,
          );
        case OutboxKinds.sessionReset:
          await _reset(SessionResetPayload.decode(op.payload));
        default:
          throw const _UnknownOp();
      }
      await _succeeded(op);
    } on _UnknownOp {
      await _giveUp(op, 'unknown_op');
    } on ProtocolFormatException {
      await _giveUp(op, 'bad_payload');
    } on Object catch (error) {
      await _failed(op, classifyOpError(error));
    }
  }

  Future<void> _reset(SessionResetPayload payload) async {
    final remote = DeviceAddress(payload.account, payload.device);
    final cooldown = _ctx.config.resetCooldown;
    if (!await _crypto.hasFreshUnansweredSession(remote, within: cooldown)) {
      final fetched = await _peers.fetch(
        payload.account,
        devices: [payload.device],
      );
      final bundle = fetched.bundleOf(payload.device);
      if (bundle == null) return; // The device is gone: nothing to repair.
      await _crypto.startFreshSession(bundle, within: cooldown);
    }
    final content = ContentMessage(
      id: _ctx.ids.next(),
      sentAt: _ctx.now(),
      conversation: DirectConversation(to: payload.account),
      body: DecryptionErrorBody(
        messageId: payload.messageId,
        senderDevice: payload.device,
      ),
    );
    await _sender.send(
      requestId: content.id,
      content: content.encode(),
      accounts: [payload.account],
      urgent: false,
    );
  }

  Future<void> _succeeded(OutboxOpRow op) => _ctx.db.transaction(() async {
    await _ctx.db.outboxDao.complete(op.id);
    final rowid = op.messageRowid;
    if (rowid != null && await _ctx.db.messagesDao.byRowid(rowid) != null) {
      await _ctx.db.messagesDao.advanceStatus(rowid, MessageStatus.sent);
    }
  });

  Future<void> _failed(OutboxOpRow op, OpFailure failure) async {
    switch (failure) {
      case DeviceRevoked():
        // Not awaited: revoking stops this worker.
        unawaited(onDeviceRevoked());
      case SessionEnded():
        // Keep the op; it runs again after the next sign-in.
        await _ctx.db.outboxDao.reschedule(
          op.id,
          nextAttemptAt: _ctx.now().add(const Duration(seconds: 30)),
          errorCode: failure.code,
        );
        onSessionEnded();
      case GiveUp():
        await _giveUp(op, failure.code);
      case RetryLater():
        if (_ctx.now().difference(op.createdAt) > _ctx.config.outboxMaxAge) {
          await _giveUp(op, 'expired');
          return;
        }
        var delay = _ctx.config.outboxBackoff.delay(
          op.attempts + 1,
          _ctx.ids.jitter(),
        );
        final atLeast = failure.atLeast;
        if (atLeast != null && atLeast > delay) delay = atLeast;
        await _ctx.db.outboxDao.reschedule(
          op.id,
          nextAttemptAt: _ctx.now().add(delay),
          errorCode: failure.code,
        );
    }
  }

  Future<void> _giveUp(OutboxOpRow op, String code) async {
    await _ctx.db.transaction(() async {
      await _ctx.db.outboxDao.fail(op.id, errorCode: code);
      final rowid = op.messageRowid;
      if (rowid != null && await _ctx.db.messagesDao.byRowid(rowid) != null) {
        await _ctx.db.messagesDao.advanceStatus(rowid, MessageStatus.failed);
      }
    });
    _ctx.emit(SendFailedEvent(messageRowid: op.messageRowid, errorCode: code));
  }
}

final class _UnknownOp implements Exception {
  const _UnknownOp();
}
