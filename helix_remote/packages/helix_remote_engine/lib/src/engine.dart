import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/account/account_service.dart';
import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/account/key_maintenance.dart';
import 'package:helix_remote_engine/src/calls/call_media.dart';
import 'package:helix_remote_engine/src/calls/calls_service.dart';
import 'package:helix_remote_engine/src/calls/engine_call_signaling.dart';
import 'package:helix_remote_engine/src/config.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/features/chats_service.dart';
import 'package:helix_remote_engine/src/features/phone_book.dart';
import 'package:helix_remote_engine/src/features/people_service.dart';
import 'package:helix_remote_engine/src/features/presence_service.dart';
import 'package:helix_remote_engine/src/features/push_service.dart';
import 'package:helix_remote_engine/src/features/settings_service.dart';
import 'package:helix_remote_engine/src/maintenance.dart';
import 'package:helix_remote_engine/src/messaging/apply.dart';
import 'package:helix_remote_engine/src/messaging/inbound.dart';
import 'package:helix_remote_engine/src/messaging/inbound_runner.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/messaging/sender.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/download_runner.dart';
import 'package:helix_remote_engine/src/transfers/inbound_media.dart';
import 'package:helix_remote_engine/src/transfers/media_janitor.dart';
import 'package:helix_remote_engine/src/transfers/media_processor.dart';
import 'package:helix_remote_engine/src/transfers/media_service.dart';
import 'package:helix_remote_engine/src/transfers/outbound_media.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_worker.dart';
import 'package:helix_remote_engine/src/transfers/transfers_service.dart';
import 'package:helix_remote_engine/src/transfers/upload_runner.dart';
import 'package:helix_remote_engine/src/util/ids.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ContentMessage, Envelope;
import 'package:meta/meta.dart';

/// The Helix Remote messaging engine (ADR-027, plan §6): everything between
/// the network and the UI that is not UI. Pure Dart, built from injected
/// pieces, with no globals, so the app, the FCM background isolate, the CLI
/// and tests each make their own.
///
/// ```dart
/// final db = await HelixDb.open(file, key: key);
/// final api = HelixApi(baseUrl: server, sessions: DbSessionTokenStore(db));
/// final engine = Engine(api: api, db: db, clock: DateTime.now,
///     random: SecureCryptoRandom());
/// await engine.start();            // sign in first if engine.status is signedOut
/// ```
///
/// The services are the engine's public face: [account], [devices],
/// [chats], [people], [settings], [presence], [push]. Each returns futures
/// and watch-query streams and holds no UI state.
///
/// **Lifecycle.** [start] loads the identity. Signed in, it starts the
/// outbox worker, the realtime socket (inbound pipeline) and housekeeping;
/// signed out, it waits, and the workers start by themselves when
/// registration or sign-in completes. [stop] stops them. [syncOnce] is the
/// headless path (FCM isolate, CLI `fetch`): read the mailbox over REST,
/// process, ack and send what that queued, without a socket or timers.
///
/// The caller owns [db] and [api] and closes them after [close].
final class Engine {
  Engine({
    required HelixApi api,
    required HelixDb db,
    required Clock clock,
    required CryptoRandom random,
    EngineConfig config = const EngineConfig(),
    PhoneBook? phoneBook,
    CallMediaFactory? callMedia,
    BlobStore? blobs,
    MediaProcessor? mediaProcessor,
    TransferConfig transferConfig = const TransferConfig(),
  }) : _hasBlobs = blobs != null,
       _ctx = EngineContext(
         api: api,
         db: db,
         clock: clock,
         random: random,
         config: config,
       ) {
    final ctx = _ctx;
    _peers = PeerDirectory(ctx);
    _crypto = PairwiseCrypto(ctx, _peers);
    devices = DeviceService(ctx, _peers);
    _sender = MessageSender(ctx, _peers, _crypto, devices);
    _outbox = OutboxService(ctx);
    _inboundMedia = InboundMedia(ctx, transferConfig)..enabled = _hasBlobs;
    _keys = KeyMaintenance(ctx);
    _maintenance = MaintenanceService(ctx, _keys, devices);
    presence = PresenceService(ctx, _sender);
    _inbound = InboundRunner(
      ctx,
      InboundProcessor(
        ctx,
        _crypto,
        ContentApplier(ctx, _outbox, media: _inboundMedia),
        _outbox,
        _Hooks(this),
      ),
      onDeviceRevoked: _handleRevoked,
      onSessionEnded: _handleSessionEnded,
    );
    _worker = OutboxWorker(
      ctx,
      _sender,
      _peers,
      _crypto,
      onDeviceRevoked: _handleRevoked,
      onSessionEnded: _handleSessionEnded,
    );
    account = AccountService(ctx, onSignedIn: _activate);
    chats = ChatsService(
      ctx,
      _outbox,
      onExpiryChanged: _maintenance.rescheduleExpiry,
    );
    people = PeopleService(ctx, _outbox, phoneBook: phoneBook);
    settings = SettingsService(ctx);
    push = PushService(ctx);
    // Calls, then transfers. Both wire themselves into [chats] and both need it
    // to exist first, which is why they come after it above.
    _callSignaling = EngineCallSignaling(ctx, _sender, _crypto);
    calls = CallsService(
      db: ctx.db,
      signaling: _callSignaling,
      clock: ctx.clock,
      ids: ctx.ids,
      selfAccount: () => ctx.identity.accountId,
      postLog: (peer, body) async {
        final chat = await chats.openDirect(peer);
        await chats.sendBody(chat.id, body);
      },
      emit: ctx.emit,
      config: config.calls,
      mediaFactory: callMedia,
    );
    _callSignaling.sink = calls;

    final store = blobs ?? const NoBlobStore();
    final outbound = OutboundMedia(
      ctx,
      _outbox,
      store,
      mediaProcessor ?? BasicMediaProcessor(store),
      transferConfig,
      onExpiryChanged: _maintenance.rescheduleExpiry,
    );
    _transferWorker = TransferWorker(
      ctx,
      transferConfig,
      UploadRunner(ctx, store, transferConfig, outbound),
      DownloadRunner(ctx, store, transferConfig),
      outbound,
      onDeviceRevoked: _handleRevoked,
      onSessionEnded: _handleSessionEnded,
    );
    outbound.cancelJob = _transferWorker.cancelRunning;
    _janitor = MediaJanitor(
      ctx,
      store,
      transferConfig,
      beforeSweep: () => media.upkeep(),
    );
    media = MediaService(
      ctx,
      blobs,
      transferConfig,
      outbound,
      _outbox,
      _janitor,
      _transferWorker.cancelRunning,
    );
    transfers = TransfersService(ctx, _transferWorker, outbound);
    chats.retryMediaHook = media.retryIfMedia;
  }

  final EngineContext _ctx;
  late final PeerDirectory _peers;
  late final PairwiseCrypto _crypto;
  late final MessageSender _sender;
  late final OutboxService _outbox;
  late final InboundMedia _inboundMedia;
  late final TransferWorker _transferWorker;
  late final MediaJanitor _janitor;
  final bool _hasBlobs;
  late final KeyMaintenance _keys;
  late final MaintenanceService _maintenance;
  late final InboundRunner _inbound;
  late final OutboxWorker _worker;
  late final EngineCallSignaling _callSignaling;
  StreamSubscription<RealtimeState>? _callWakes;

  /// Registration, sign-in, linking (this device as the new one).
  late final AccountService account;

  /// This account's devices, and approving a new device's link.
  late final DeviceService devices;

  /// Chats and messages.
  late final ChatsService chats;

  /// Discovery, profiles, names, blocks.
  late final PeopleService people;

  /// Local preferences, server-side privacy, the `~Helix name`.
  late final SettingsService settings;

  /// Typing indicators.
  late final PresenceService presence;

  /// Push-token registration.
  late final PushService push;

  /// 1:1 calls: the signalling state machine, the call log, pending calls
  /// for a device woken by a call push. The media comes from the host
  /// (`calls.mediaFactory`).
  late final CallsService calls;

  /// Attachments: send media, per-attachment progress, retry, cancel,
  /// download on demand, forward. Needs a `blobs` store (see [Engine.new]).
  late final MediaService media;

  /// The transfer queue as a whole.
  late final TransfersService transfers;

  final StreamController<EngineStatus> _statuses = StreamController.broadcast();
  EngineStatus _status = EngineStatus.idle;
  bool _realtime = true;
  bool _background = true;
  bool _workersRunning = false;
  bool _revoking = false;

  EngineStatus get status => _status;

  Stream<EngineStatus> get statuses => _statuses.stream;

  /// UI-relevant happenings that are not database changes: new messages
  /// (for notifications), typing, key changes, account signals, send
  /// failures.
  Stream<EngineEvent> get events => _ctx.events;

  /// The realtime socket's state (connecting, connected, waiting, …).
  Stream<RealtimeState> get connection => _ctx.api.realtime.states;

  RealtimeState get connectionState => _ctx.api.realtime.state;

  /// This device's account id, or null when signed out.
  String? get accountId => _ctx.isSignedIn ? _ctx.identity.accountId : null;

  /// This device's id, or null when signed out.
  String? get deviceId => _ctx.isSignedIn ? _ctx.identity.deviceId : null;

  // ------------------------------------------------------------- lifecycle

  /// Loads the identity and starts what applies: with [realtime] the
  /// WebSocket and the inbound pipeline, with [background] the outbox
  /// worker and housekeeping timers. A headless host passes neither and
  /// calls [syncOnce].
  ///
  /// Signed out, the status becomes [EngineStatus.signedOut] and the
  /// workers start when [account] finishes registering or signing in.
  Future<void> start({bool realtime = true, bool background = true}) async {
    _realtime = realtime;
    _background = background;
    if (_status == EngineStatus.running) return;
    final identity = await LocalIdentity.load(_ctx.db);
    _ctx.setIdentity(identity);
    if (identity == null) {
      _setStatus(EngineStatus.signedOut);
      return;
    }
    _ctx.api.auth.reauthenticate = () =>
        account.deviceKeySignIn(_ctx.api.identity, onRevoked: _handleRevoked);
    _setStatus(EngineStatus.running);
    await _startWorkers();
  }

  Future<void> _activate() async {
    final identity = await LocalIdentity.load(_ctx.db);
    _ctx.setIdentity(identity);
    if (identity == null) return;
    _ctx.api.auth.reauthenticate = () =>
        account.deviceKeySignIn(_ctx.api.identity, onRevoked: _handleRevoked);
    _setStatus(EngineStatus.running);
    if (_background || _realtime) {
      await _startWorkers();
    }
    // Learn the account's other devices and the server-side state.
    unawaited(_afterSignIn());
  }

  Future<void> _afterSignIn() async {
    try {
      await devices.refresh();
      await people.syncBlocks();
    } on Object {
      // Offline: maintenance repeats the device refresh.
    }
  }

  Future<void> _startWorkers() async {
    if (_workersRunning) return;
    _workersRunning = true;
    if (_background) {
      _worker.start();
      _maintenance.start();
      if (_hasBlobs) {
        _transferWorker.start();
        _janitor.start();
        unawaited(media.consumeOpenedViewOnce());
      }
    }
    if (_realtime) {
      // A foreground engine owns the calls of this database: whatever the
      // log still shows as ringing or live is left over from a crash.
      await calls.recoverUnfinished();
      await _inbound.startRealtime();
      // Offers that came while this device was offline wait on the server;
      // ring them whenever the socket (re)connects.
      _callWakes = _ctx.api.realtime.states.listen((state) {
        if (state.phase == RealtimePhase.connected) {
          unawaited(_ringPendingCalls());
        }
      });
    }
  }

  Future<void> _ringPendingCalls() async {
    try {
      await calls.fetchPending();
    } on Object {
      // Offline or signed out: the next connect tries again.
    }
  }

  Future<void> _stopWorkers() async {
    if (!_workersRunning) return;
    _workersRunning = false;
    await _callWakes?.cancel();
    _callWakes = null;
    await calls.release();
    await _inbound.stopRealtime();
    await _worker.stop();
    await _transferWorker.stop();
    await _janitor.stop();
    await _maintenance.stop();
  }

  /// Stops the workers. The database and API stay open (the host closes
  /// them); [start] may be called again.
  Future<void> stop() async {
    await _stopWorkers();
    if (_status != EngineStatus.revoked) _setStatus(EngineStatus.stopped);
  }

  /// Stops and releases the engine's own streams. Call before closing the
  /// database and the API.
  Future<void> close() async {
    await stop();
    await presence.close();
    await calls.close();
    await _statuses.close();
    await _ctx.close();
  }

  /// The headless path (FCM background isolate, `helix fetch`): read the
  /// mailbox over REST, process and ack everything, then send what that
  /// queued (delivered receipts, session resets). No socket, no timers.
  /// The summary carries what notifications need.
  Future<SyncSummary> syncOnce() async {
    if (!_ctx.isSignedIn) throw const NotSignedInException();
    final summary = await _inbound.fetchOnce();
    await _worker.drain();
    try {
      // Offers waiting for this device (a call push woke it): who is
      // calling, for the notification. Opening them is the app's job.
      return summary.withPendingCalls(await calls.peekPending());
    } on Object {
      return summary; // Offline for the calls route only: nothing to ring.
    }
  }

  /// Sends everything that is due (no waiting for backoff). For headless
  /// hosts and tests; the running worker does this by itself.
  Future<void> drainOutbox() => _worker.drain();

  /// Runs every transfer that is due and waits for them (no waiting for
  /// backoff). For headless hosts and tests; the running worker does this by
  /// itself.
  Future<void> drainTransfers() => _transferWorker.drain();

  /// Queues arbitrary [content] for [audience] without the checks the chat
  /// service applies (tests craft forged, late and newer-version content
  /// with it; C4 features build on the same outbox path).
  @visibleForTesting
  Future<void> debugSend(
    ContentMessage content, {
    required Iterable<String> audience,
    String? conversationId,
    bool urgent = true,
  }) async {
    await _outbox.enqueueContent(
      content: content,
      audience: audience,
      conversationId: conversationId,
      urgent: urgent,
    );
  }

  /// One housekeeping pass (expired messages, key upkeep).
  Future<void> runMaintenance() async {
    await _maintenance.runOnce();
    await media.sweep();
  }

  /// Reconnects the socket (the app came to the foreground, or another
  /// connection had replaced this one).
  void reconnect() => _inbound.reconnect();

  // ------------------------------------------------------------ sign-out

  /// Signs this device out: stops the workers, removes this device from the
  /// account on the server (best effort; otherwise only the session ends),
  /// and deletes every local row (keys, sessions, messages, settings).
  ///
  /// There is no sign-out that keeps the data: a device that kept its keys
  /// could sign itself in again with its signing key. The database is empty
  /// afterwards and may register or sign in again.
  Future<void> signOut() async {
    if (!_ctx.isSignedIn) return;
    await _stopWorkers();
    await account.leaveOnServer();
    await _ctx.api.auth.forget();
    await media.wipeFiles();
    await _ctx.db.wipeAll();
    _forgetIdentity();
    _setStatus(EngineStatus.signedOut);
  }

  /// The server says this device was revoked: stop, forget the session and
  /// (with `wipeOnRevocation`) delete the local data.
  Future<void> _handleRevoked() async {
    if (_status == EngineStatus.revoked || _revoking) return;
    _revoking = true;
    await _stopWorkers();
    await _ctx.api.auth.forget();
    if (_ctx.config.wipeOnRevocation) {
      await media.wipeFiles();
      try {
        await _ctx.db.wipeAll();
      } on Object {
        // The database is gone or closed; nothing left to wipe.
      }
    }
    _forgetIdentity();
    // Last, so whoever reacts to the status finds the wipe done.
    _setStatus(EngineStatus.revoked);
    _revoking = false;
  }

  /// The session could not be renewed: tokens are gone, the data stays.
  void _handleSessionEnded() {
    if (_status != EngineStatus.running) return;
    _setStatus(EngineStatus.signedOut);
    unawaited(_stopWorkers());
  }

  void _forgetIdentity() {
    _ctx.setIdentity(null);
    _crypto.reset();
  }

  void _setStatus(EngineStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }
}

/// The inbound pipeline's way back into the engine.
final class _Hooks implements InboundHooks {
  _Hooks(this._engine);

  final Engine _engine;

  @override
  Future<void> onPrekeysLow(int remaining) async {
    await _engine._keys.replenish(remaining);
  }

  @override
  Future<void> onOwnDevicesChanged() async {
    await _engine.devices.refresh();
    _engine._ctx.emit(const OwnDevicesChanged());
  }

  @override
  Future<void> onThisDeviceRevoked() => _engine._handleRevoked();

  @override
  Future<void> onCallSignal(Envelope envelope) =>
      _engine._callSignaling.onEnvelope(envelope);

  @override
  void onTyping(
    String conversationId,
    String account, {
    required bool typing,
  }) => _engine.presence.onTyping(conversationId, account, typing: typing);
}
