import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_crypto/crypto/session_key_derivation.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/frame_io.dart';

const _kHandshakeTimeout = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// Channel state machine
// ---------------------------------------------------------------------------

enum ChannelState {
  tcpConnected,
  preface,
  requestPhase,
  handshaking,
  identityExchange,
  capabilityExchange,
  active,
  closing,
  closed,
}

// ---------------------------------------------------------------------------
// Internal exceptions
// ---------------------------------------------------------------------------

class _ChannelError implements Exception {
  final String message;
  const _ChannelError(this.message);
  @override
  String toString() => '_ChannelError: $message';
}

class _IdentityVerificationError extends _ChannelError {
  const _IdentityVerificationError(super.message);
}

class _VersionMismatchError extends _ChannelError {
  const _VersionMismatchError(super.message);
}

// ---------------------------------------------------------------------------
// RequestService interface
// ---------------------------------------------------------------------------

/// Minimal interface that SecureChannel requires from the request layer.
/// The concrete RequestService in the application must implement this.
abstract class RequestValidator {
  /// Validate an incoming RequestFrame.
  /// Returns the matching [ConnectionRequest] if the request is acceptable,
  /// or null to reject it.
  ConnectionRequest? validateIncoming(RequestFrame frame);
}

// ---------------------------------------------------------------------------
// SecureChannel
// ---------------------------------------------------------------------------

class SecureChannel {
  // -- Public identity --
  final String localSessionId;
  String? _threadId; // peerStaticKeyFingerprint; set after identity exchange

  String get threadId {
    assert(_threadId != null, 'threadId not yet established');
    return _threadId!;
  }

  // -- State --
  ChannelState _state = ChannelState.tcpConnected;
  ChannelState get state => _state;

  /// Connection health derived from how recently traffic was received.
  ///
  /// Green  = heard from peer within one keepalive interval (≤ 6 s).
  /// Yellow = within two keepalive intervals (≤ 12 s).
  /// Red    = approaching timeout (> 12 s).
  ConnectionQuality get connectionQuality {
    if (_state != ChannelState.active) return ConnectionQuality.poor;
    final age = DateTime.now().difference(_lastTrafficAt);
    if (age <= const Duration(seconds: 6)) return ConnectionQuality.good;
    if (age <= const Duration(seconds: 12)) return ConnectionQuality.fair;
    return ConnectionQuality.poor;
  }

  // -- Broadcast streams --
  final _messageController = StreamController<ChatMessageFrame>.broadcast();
  final _stateController = StreamController<ChannelState>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _receiptController = StreamController<List<String>>.broadcast();
  final _reactionController = StreamController<ReactionFrame>.broadcast();
  final _fileChunkController = StreamController<FileTransferFrame>.broadcast();
  final _editController = StreamController<EditMessageFrame>.broadcast();
  final _deleteController = StreamController<DeleteMessageFrame>.broadcast();
  final _wipeController = StreamController<void>.broadcast();
  final _ephemeralMediaController =
      StreamController<EphemeralMediaFrame>.broadcast();
  final _fileProbeController = StreamController<FileProbeFrame>.broadcast();
  final _fileResumeController = StreamController<FileResumeFrame>.broadcast();
  final _fileCompleteController =
      StreamController<FileCompleteFrame>.broadcast();
  final _fileCancelController = StreamController<FileCancelFrame>.broadcast();
  final _groupControlController =
      StreamController<GroupControlFrame>.broadcast();
  final _groupMessageController =
      StreamController<GroupMessageFrame>.broadcast();
  final _callSignalController = StreamController<CallSignalFrame>.broadcast();

  Stream<ChatMessageFrame> get messages => _messageController.stream;
  Stream<ChannelState> get stateChanges => _stateController.stream;
  Stream<bool> get typingEvents => _typingController.stream;
  Stream<List<String>> get receiptEvents => _receiptController.stream;
  Stream<ReactionFrame> get reactionEvents => _reactionController.stream;
  Stream<FileTransferFrame> get fileChunkEvents => _fileChunkController.stream;
  Stream<EditMessageFrame> get editEvents => _editController.stream;
  Stream<DeleteMessageFrame> get deleteEvents => _deleteController.stream;
  Stream<void> get wipeEvents => _wipeController.stream;
  Stream<EphemeralMediaFrame> get ephemeralMediaEvents =>
      _ephemeralMediaController.stream;
  Stream<FileProbeFrame> get fileProbeEvents => _fileProbeController.stream;
  Stream<FileResumeFrame> get fileResumeEvents => _fileResumeController.stream;
  Stream<FileCompleteFrame> get fileCompleteEvents =>
      _fileCompleteController.stream;
  Stream<FileCancelFrame> get fileCancelEvents => _fileCancelController.stream;
  Stream<GroupControlFrame> get groupControlEvents =>
      _groupControlController.stream;
  Stream<GroupMessageFrame> get groupMessageEvents =>
      _groupMessageController.stream;
  Stream<CallSignalFrame> get callSignalEvents => _callSignalController.stream;

  // -- Transport --
  final SecureSocket _socket;
  late final IOSink _sink;

  // The single, persistent byte-stream reader for this connection.
  // All reads (handshake frames AND the active read loop) go through this one
  // StreamIterator so we never create a second subscription on the
  // single-subscription socket stream.
  late final LengthPrefixedFrameReader _reader;

  // -- Negotiated peer capabilities (intersection of local and peer bitmasks) --
  int _negotiatedCapabilities = 0;

  /// The capability bitmask agreed on during handshake.
  /// Use [supportsCapability] for readable checks.
  int get negotiatedCapabilities => _negotiatedCapabilities;

  /// Returns true when [flag] was negotiated with the peer.
  bool supportsCapability(int flag) => _negotiatedCapabilities & flag != 0;

  // -- Rekey tracking --
  int _outboundMessageCount = 0;
  final DateTime _sessionStart = DateTime.now();
  bool _rekeyPending = false;

  // -- Duplicate detection (bounded FIFO, oldest entry evicted at capacity) --
  static const _kMaxSeenMessageIds = 1000;
  final Set<String> _seenMessageIds = <String>{};

  // -- Keepalive --
  Timer? _keepaliveTimer;
  DateTime _lastTrafficAt = DateTime.now();
  int _keepaliveCounter = 0;

  // -- Pending ack completers --
  final _pendingAcks = <String, Completer<bool>>{};
  Future<void> _writeQueue = Future<void>.value();

  // -- Forward secrecy chain keys --
  crypto.SecretKey? _sendChainKey;
  crypto.SecretKey? _recvChainKey;
  Uint8List? _localStaticPublicKeyDer;
  Uint8List? _peerStaticPublicKeyDer;
  String? _peerSessionId;

  // ---------------------------------------------------------------------------
  // Private constructor — use the static factory methods
  // ---------------------------------------------------------------------------

  SecureChannel._({required SecureSocket socket, required this.localSessionId})
    : _socket = socket {
    _sink = socket;
    // Wrap the socket's List<int> stream into Uint8List chunks and hand
    // ownership to the single persistent reader.
    final byteStream = socket.map((c) => Uint8List.fromList(c));
    _reader = LengthPrefixedFrameReader(byteStream);
  }

  // ---------------------------------------------------------------------------
  // Factory: server side
  // ---------------------------------------------------------------------------

  /// Accept a raw TCP socket as the server side of a new Helix connection.
  ///
  /// Protocol flow:
  ///   1. Upgrade to TLS (server role, TOFU cert).
  ///   2. Read RequestFrame — validate via [requestService].
  ///   3. Send AcceptFrame (or RejectFrame + close on failure).
  ///   4. Mutual identity exchange (IdentityFrame / IdentityAckFrame).
  ///   5. Capability exchange (CapabilityFrame).
  ///   6. Enter active state and start keepalive + read loop.
  static Future<SecureChannel> acceptConnection({
    required Socket rawSocket,
    required DeviceIdentity localIdentity,
    required String localSessionId,
    required RequestValidator requestService,
  }) async {
    final ctx = _buildSecurityContext(localIdentity);

    // Upgrade to TLS — server mode.
    // Peer cert validation is TOFU; real identity is proved by IdentityFrame.
    SecureSocket tlsSocket;
    try {
      tlsSocket = await SecureSocket.secureServer(
        rawSocket,
        ctx,
      ).timeout(_kHandshakeTimeout);
    } catch (_) {
      rawSocket.destroy();
      rethrow;
    }

    final ch = SecureChannel._(
      socket: tlsSocket,
      localSessionId: localSessionId,
    );
    ch._setState(ChannelState.requestPhase);

    try {
      // 1. Read RequestFrame
      final first = await ch._readFrame().timeout(_kHandshakeTimeout);
      if (first == null || first is! RequestFrame) {
        await ch._sendRejectAndClose('bad-request', 'expected-request-frame');
        throw const _ChannelError('Expected RequestFrame as first frame');
      }

      final req = requestService.validateIncoming(first);
      if (req == null) {
        await ch._sendRejectAndClose(first.requestId, 'rejected');
        throw const _ChannelError('Request rejected by RequestService');
      }

      // 2. Accept
      await ch._writeFrame(AcceptFrame(requestId: first.requestId));

      // 3. Identity exchange
      ch._setState(ChannelState.identityExchange);
      final peerFp = await ch
          ._performIdentityExchange(
            localIdentity: localIdentity,
            expectedPeerSessionId: first.sessionId,
          )
          .timeout(_kHandshakeTimeout);
      ch._threadId = peerFp;

      // 4. Capability exchange
      ch._setState(ChannelState.capabilityExchange);
      await ch._performCapabilityExchange().timeout(_kHandshakeTimeout);

      // 5. Active
      ch._setState(ChannelState.active);
      ch._startKeepalive();
      ch._startReadLoop();
      return ch;
    } catch (e) {
      await ch.close();
      rethrow;
    }
  }

  /// Accept an already-established TLS socket after the CBOR request handshake.
  ///
  /// This skips the transport RequestFrame/AcceptFrame phase because the app
  /// already exchanged and accepted the request on the plain TCP control socket.
  static Future<SecureChannel> acceptEstablished({
    required SecureSocket socket,
    required DeviceIdentity localIdentity,
    required String localSessionId,
    required ConnectionRequest request,
  }) async {
    final ch = SecureChannel._(socket: socket, localSessionId: localSessionId);

    try {
      ch._setState(ChannelState.identityExchange);
      final peerFp = await ch._performIdentityExchange(
        localIdentity: localIdentity,
        expectedPeerSessionId: request.peerSessionId,
      );
      if (request.peerStaticKeyFingerprint.isNotEmpty &&
          peerFp != request.peerStaticKeyFingerprint) {
        throw const _IdentityVerificationError(
          'Peer static key fingerprint does not match expected value',
        );
      }
      ch._threadId = peerFp;

      ch._setState(ChannelState.capabilityExchange);
      await ch._performCapabilityExchange();

      ch._setState(ChannelState.active);
      ch._startKeepalive();
      ch._startReadLoop();
      return ch;
    } catch (e) {
      await ch.close();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Factory: client side
  // ---------------------------------------------------------------------------

  /// Open a new Helix connection to [host]:[port] as the initiating side.
  ///
  /// Protocol flow:
  ///   1. TCP connect + TLS upgrade.
  ///   2. Send RequestFrame.
  ///   3. Wait for AcceptFrame (throws on Reject / Busy).
  ///   4. Mutual identity exchange.
  ///   5. Capability exchange.
  ///   6. Enter active state.
  static Future<SecureChannel> connect({
    required String host,
    required int port,
    required DeviceIdentity localIdentity,
    required String localSessionId,
    required ConnectionRequest request,
  }) async {
    final ctx = _buildSecurityContext(localIdentity);

    final tlsSocket = await SecureSocket.connect(
      host,
      port,
      context: ctx,
      onBadCertificate: (_) => true, // TOFU — verified via IdentityFrame
    ).timeout(_kHandshakeTimeout);

    final ch = SecureChannel._(
      socket: tlsSocket,
      localSessionId: localSessionId,
    );
    ch._setState(ChannelState.requestPhase);

    try {
      // 1. Send RequestFrame
      await ch._writeFrame(
        RequestFrame(
          requestId: request.requestId,
          displayName:
              request.peerDisplayName, // local display name not on model
          deviceSuffix: localIdentity.deviceSuffix,
          sessionId: localSessionId,
          staticKeyFingerprint: localIdentity.staticPublicKeyFingerprint,
          protocolMajor: kProtocolMajor,
          protocolMinor: kProtocolMinor,
          port: port,
          expiresAt: request.expiresAt.millisecondsSinceEpoch,
        ),
      );

      // 2. Read response
      ch._setState(ChannelState.handshaking);
      final response = await ch._readFrame().timeout(_kHandshakeTimeout);
      if (response == null) {
        throw const _ChannelError('Peer closed after request with no response');
      }
      switch (response.type) {
        case kTypeReject:
          throw _ChannelError(
            'Request rejected: ${(response as RejectFrame).reason}',
          );
        case kTypeBusy:
          throw const _ChannelError('Peer is busy');
        case kTypeAccept:
          if ((response as AcceptFrame).requestId != request.requestId) {
            throw const _ChannelError('AcceptFrame requestId mismatch');
          }
        default:
          throw const _ChannelError('Unexpected frame type awaiting accept');
      }

      // 3. Identity exchange
      ch._setState(ChannelState.identityExchange);
      final peerFp = await ch
          ._performIdentityExchange(
            localIdentity: localIdentity,
            expectedPeerSessionId: request.peerSessionId,
          )
          .timeout(_kHandshakeTimeout);
      if (request.peerStaticKeyFingerprint.isNotEmpty &&
          peerFp != request.peerStaticKeyFingerprint) {
        throw const _IdentityVerificationError(
          'Peer static key fingerprint does not match expected value',
        );
      }
      ch._threadId = peerFp;

      // 4. Capability exchange
      ch._setState(ChannelState.capabilityExchange);
      await ch._performCapabilityExchange().timeout(_kHandshakeTimeout);

      // 5. Active
      ch._setState(ChannelState.active);
      ch._startKeepalive();
      ch._startReadLoop();
      return ch;
    } catch (e) {
      await ch.close();
      rethrow;
    }
  }

  /// Open a channel over an already-established TLS socket after the CBOR
  /// request handshake.
  static Future<SecureChannel> connectEstablished({
    required SecureSocket socket,
    required DeviceIdentity localIdentity,
    required String localSessionId,
    required ConnectionRequest request,
  }) async {
    final ch = SecureChannel._(socket: socket, localSessionId: localSessionId);

    try {
      ch._setState(ChannelState.identityExchange);
      final peerFp = await ch._performIdentityExchange(
        localIdentity: localIdentity,
        expectedPeerSessionId: request.peerSessionId,
      );
      if (request.peerStaticKeyFingerprint.isNotEmpty &&
          peerFp != request.peerStaticKeyFingerprint) {
        throw const _IdentityVerificationError(
          'Peer static key fingerprint does not match expected value',
        );
      }
      ch._threadId = peerFp;

      ch._setState(ChannelState.capabilityExchange);
      await ch._performCapabilityExchange();

      ch._setState(ChannelState.active);
      ch._startKeepalive();
      ch._startReadLoop();
      return ch;
    } catch (e) {
      await ch.close();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // TLS context
  // ---------------------------------------------------------------------------

  static SecurityContext buildSecurityContext(DeviceIdentity identity) {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(identity.certPem));
    ctx.usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    return ctx;
  }

  static SecurityContext _buildSecurityContext(DeviceIdentity identity) =>
      buildSecurityContext(identity);

  // ---------------------------------------------------------------------------
  // Identity exchange
  // ---------------------------------------------------------------------------

  /// Performs the mutual IdentityFrame / IdentityAckFrame exchange over an
  /// already-established TLS connection.
  ///
  /// Returns the peer's static key fingerprint (8 lower-case hex chars) so
  /// the caller can set [_threadId] and optionally verify it against the
  /// expected value from the ConnectionRequest.
  Future<String> _performIdentityExchange({
    required DeviceIdentity localIdentity,
    required String expectedPeerSessionId,
  }) async {
    // -- Build our IdentityFrame --
    final privateKey = CryptoUtils.rsaPrivateKeyFromPem(
      localIdentity.privateKeyPem,
    );
    final publicKey = _publicKeyFromPrivate(privateKey);
    final spkiDer = _encodeSpkiDer(publicKey);
    _localStaticPublicKeyDer = Uint8List.fromList(spkiDer);
    final signPayload = buildIdentityProofPayload(localSessionId);
    final signature = CryptoUtils.rsaSign(privateKey, signPayload);

    await _writeFrame(
      IdentityFrame(
        staticPublicKeyDer: spkiDer,
        signature: signature,
        sessionId: localSessionId,
      ),
    );

    // -- Read peer's IdentityFrame --
    final peerFrame = await _readFrame();
    if (peerFrame is! IdentityFrame) {
      throw const _IdentityVerificationError(
        'Expected IdentityFrame from peer',
      );
    }

    // Verify session binding
    if (peerFrame.sessionId != expectedPeerSessionId) {
      await _writeFrame(IdentityAckFrame(ok: false, sessionId: localSessionId));
      throw const _IdentityVerificationError(
        'Peer sessionId in IdentityFrame does not match expected value',
      );
    }
    _peerSessionId = peerFrame.sessionId;
    _peerStaticPublicKeyDer = Uint8List.fromList(peerFrame.staticPublicKeyDer);

    // Verify signature
    final peerPubKey = CryptoUtils.rsaPublicKeyFromDERBytes(
      peerFrame.staticPublicKeyDer,
    );
    final peerPayload = buildIdentityProofPayload(peerFrame.sessionId);
    final valid = CryptoUtils.rsaVerify(
      peerPubKey,
      peerPayload,
      peerFrame.signature,
    );

    if (!valid) {
      await _writeFrame(IdentityAckFrame(ok: false, sessionId: localSessionId));
      throw const _IdentityVerificationError(
        'Peer identity signature verification failed',
      );
    }

    // Send positive ack
    await _writeFrame(IdentityAckFrame(ok: true, sessionId: localSessionId));

    // Read peer's ack of our identity
    final ourAck = await _readFrame();
    if (ourAck is! IdentityAckFrame) {
      throw const _IdentityVerificationError(
        'Expected IdentityAckFrame from peer',
      );
    }
    if (!ourAck.ok) {
      throw const _IdentityVerificationError(
        'Peer rejected our identity proof',
      );
    }

    // Fingerprint from peer RSA modulus, matching ProfileService.
    return _fingerprintOfSpki(peerFrame.staticPublicKeyDer);
  }

  // ---------------------------------------------------------------------------
  // Capability exchange
  // ---------------------------------------------------------------------------

  Future<void> _performCapabilityExchange() async {
    await _writeFrame(
      CapabilityFrame(
        major: kProtocolMajor,
        minor: kProtocolMinor,
        features: const [],
        capabilities: kCapAll,
      ),
    );

    final peerCap = await _readFrame();
    if (peerCap is! CapabilityFrame) {
      throw const _ChannelError('Expected CapabilityFrame from peer');
    }

    if (peerCap.major != kProtocolMajor) {
      await _writeFrame(
        VersionMismatchFrame(
          ourMajor: kProtocolMajor,
          ourMinor: kProtocolMinor,
        ),
      );
      throw _VersionMismatchError(
        'Protocol major version mismatch: ours=$kProtocolMajor '
        'peer=${peerCap.major}',
      );
    }

    // Store the intersection of what both sides support.
    _negotiatedCapabilities = kCapAll & peerCap.capabilities;

    // Initialise per-message chain keys. Do not advertise this as forward
    // secrecy until the authenticated key agreement has been externally
    // reviewed and the capability flag is re-enabled deliberately.
    await _initChainKeys();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Send a chat message frame over the active channel.
  ///
  /// After writing, the send chain key is ratcheted forward.
  Future<void> sendMessage(ChatMessageFrame msg) async {
    _assertActive();
    _checkRekey();
    await _writeFrame(msg);
    _outboundMessageCount++;
    _lastTrafficAt = DateTime.now();
    await _ratchetSendKey();
  }

  /// Send a typing indicator (best-effort, no ack).
  Future<void> sendTyping(bool isTyping) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(TypingIndicatorFrame(isTyping: isTyping));
    } catch (_) {}
  }

  /// Send read receipts for a list of message IDs (best-effort).
  Future<void> sendReadReceipt(List<String> messageIds) async {
    if (_state != ChannelState.active || messageIds.isEmpty) return;
    try {
      await _writeFrame(ReadReceiptFrame(messageIds: messageIds));
    } catch (_) {}
  }

  /// Toggle a reaction on a message (best-effort).
  Future<void> sendReaction(
    String messageId,
    String emoji, {
    required bool remove,
  }) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(
        ReactionFrame(messageId: messageId, emoji: emoji, remove: remove),
      );
    } catch (_) {}
  }

  /// Send a single file chunk frame (best-effort — caller tracks progress).
  ///
  /// Intentionally omits flush: calling flush() after every 512 KB chunk
  /// serialises the entire pipeline (disk read → encode → OS write → wait)
  /// and caps throughput to ~5 MB/s. Instead, chunks are written to the TLS
  /// sink without waiting for the OS to drain the buffer; the sink drains
  /// concurrently while the sender reads the next chunk from disk. The
  /// subsequent sendFileComplete call uses _writeFrame (which does flush),
  /// which flushes all accumulated chunk data plus the complete frame.
  Future<void> sendFileChunk(FileTransferFrame chunk) {
    _assertActive();
    final previous = _writeQueue.catchError((_) {});
    final next = previous.then((_) {
      _sink.add(encodeFrame(chunk));
      _lastTrafficAt = DateTime.now();
    });
    _writeQueue = next.catchError((_) {});
    return next;
  }

  /// Send one chunk of ephemeral (RAM-only) media (best-effort — caller tracks progress).
  Future<void> sendEphemeralMedia(EphemeralMediaFrame chunk) async {
    _assertActive();
    await _writeFrame(chunk);
    _lastTrafficAt = DateTime.now();
  }

  /// Send a FileProbeFrame to announce an upcoming transfer (throws if not active).
  Future<void> sendFileProbe(FileProbeFrame probe) async {
    _assertActive();
    await _writeFrame(probe);
    _lastTrafficAt = DateTime.now();
  }

  /// Reply to a probe with the byte offset to resume from (best-effort).
  Future<void> sendFileResume(FileResumeFrame resume) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(resume);
    } catch (_) {}
  }

  /// Signal that all chunks were sent and the receiver should finalize (throws if not active).
  Future<void> sendFileComplete(FileCompleteFrame complete) async {
    _assertActive();
    await _writeFrame(complete);
  }

  /// Abort an in-progress transfer (best-effort — peer should delete the .part file).
  Future<void> sendFileCancel(FileCancelFrame cancel) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(cancel);
    } catch (_) {}
  }

  /// Send a WebRTC call signal frame. Throws [StateError] if the channel is
  /// not active, or [UnsupportedError] if the peer did not negotiate kCapWebRTC.
  Future<void> sendCallSignal(CallSignalFrame frame) async {
    if (_state != ChannelState.active) {
      throw StateError('Channel is not active');
    }
    if (!supportsCapability(kCapWebRTC)) {
      throw UnsupportedError('Peer does not support WebRTC');
    }
    await _writeFrame(frame);
    _lastTrafficAt = DateTime.now();
  }

  /// Send a group membership/admin/election event. Throws [StateError] if the
  /// channel is not active, or [UnsupportedError] if the peer did not negotiate
  /// kCapGroups.
  Future<void> sendGroupControl(GroupControlFrame control) async {
    if (_state != ChannelState.active) {
      throw StateError('Channel is not active');
    }
    if (!supportsCapability(kCapGroups)) {
      throw UnsupportedError('Peer does not support groups');
    }
    await _writeFrame(control);
    _lastTrafficAt = DateTime.now();
  }

  /// Send an opaque sender-encrypted group payload. Throws [StateError] if the
  /// channel is not active, or [UnsupportedError] if the peer did not negotiate
  /// kCapGroups.
  Future<void> sendGroupMessage(GroupMessageFrame message) async {
    if (_state != ChannelState.active) {
      throw StateError('Channel is not active');
    }
    if (!supportsCapability(kCapGroups)) {
      throw UnsupportedError('Peer does not support groups');
    }
    await _writeFrame(message);
    _lastTrafficAt = DateTime.now();
  }

  /// Edit a previously-sent message on the peer side (best-effort).
  Future<void> sendEdit(String messageId, String newText) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(
        EditMessageFrame(
          messageId: messageId,
          newText: newText,
          editedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {}
  }

  /// Delete a message on the peer side (best-effort).
  Future<void> sendDelete(String messageId) async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(DeleteMessageFrame(messageId: messageId));
    } catch (_) {}
  }

  /// Send a CloseFrame and then close the underlying socket.
  Future<void> sendClose({String reason = 'normal'}) async {
    if (_state == ChannelState.closing || _state == ChannelState.closed) return;
    _setState(ChannelState.closing);
    try {
      await _writeFrame(CloseFrame(reason: reason));
    } catch (_) {
      // Best-effort; ignore write errors during close.
    }
    await close();
  }

  /// Send a WipeFrame to signal the peer to destroy all chat data.
  Future<void> sendWipe() async {
    if (_state != ChannelState.active) return;
    try {
      await _writeFrame(WipeFrame());
    } catch (_) {}
  }

  Future<void>? _closeFuture;

  /// Close the channel immediately without sending a CloseFrame.
  Future<void> close() => _closeFuture ??= _closeImpl();

  Future<void> _closeImpl() async {
    _setState(ChannelState.closed);
    _stopKeepalive();

    try {
      await _reader.cancel();
    } catch (_) {}

    try {
      await _socket.close();
    } catch (_) {}

    // Fail all pending ack waiters.
    for (final c in _pendingAcks.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _pendingAcks.clear();

    Future<void> tryClose(StreamController<dynamic> c) async {
      if (!c.isClosed) {
        try {
          await c.close();
        } catch (_) {}
      }
    }

    await tryClose(_messageController);
    await tryClose(_stateController);
    await tryClose(_typingController);
    await tryClose(_receiptController);
    await tryClose(_reactionController);
    await tryClose(_fileChunkController);
    await tryClose(_editController);
    await tryClose(_deleteController);
    await tryClose(_wipeController);
    await tryClose(_ephemeralMediaController);
    await tryClose(_fileProbeController);
    await tryClose(_fileResumeController);
    await tryClose(_fileCompleteController);
    await tryClose(_fileCancelController);
    await tryClose(_groupControlController);
    await tryClose(_groupMessageController);
    await tryClose(_callSignalController);
  }

  // ---------------------------------------------------------------------------
  // Read loop (entered after handshake completes)
  // ---------------------------------------------------------------------------

  void _startReadLoop() {
    _runReadLoop();
  }

  void _runReadLoop() async {
    try {
      while (_state == ChannelState.active) {
        final frame = await _readFrame();
        if (frame == null) break; // clean EOF
        _lastTrafficAt = DateTime.now();
        await _handleIncomingFrame(frame);
      }
    } catch (_) {
      // Protocol error or socket error — tear down the channel.
    } finally {
      if (_state != ChannelState.closed && _state != ChannelState.closing) {
        await close();
      }
    }
  }

  Future<void> _handleIncomingFrame(ProtocolFrame frame) async {
    switch (frame.type) {
      case kTypeChatMessage:
        final msg = frame as ChatMessageFrame;
        // Always ack, even duplicates (idempotent).
        await _writeFrame(ChatAckFrame(messageId: msg.messageId, ok: true));
        if (_seenMessageIds.contains(msg.messageId)) return; // duplicate
        _seenMessageIds.add(msg.messageId);
        if (_seenMessageIds.length > _kMaxSeenMessageIds) {
          _seenMessageIds.remove(_seenMessageIds.first);
        }
        if (!_messageController.isClosed) _messageController.add(msg);
        // Ratchet receive chain key forward.
        await _ratchetRecvKey();

      case kTypeChatAck:
        final ack = frame as ChatAckFrame;
        final c = _pendingAcks.remove(ack.messageId);
        if (c != null && !c.isCompleted) c.complete(ack.ok);

      case kTypeKeepalive:
        // _lastTrafficAt already refreshed above; no reply needed.
        break;

      case kTypeTypingIndicator:
        if (!_typingController.isClosed) {
          _typingController.add((frame as TypingIndicatorFrame).isTyping);
        }

      case kTypeReadReceipt:
        if (!_receiptController.isClosed) {
          _receiptController.add((frame as ReadReceiptFrame).messageIds);
        }

      case kTypeReaction:
        if (!_reactionController.isClosed) {
          _reactionController.add(frame as ReactionFrame);
        }

      case kTypeFileTransfer:
        if (!_fileChunkController.isClosed) {
          _fileChunkController.add(frame as FileTransferFrame);
        }

      case kTypeEditMessage:
        if (!_editController.isClosed) {
          _editController.add(frame as EditMessageFrame);
        }

      case kTypeDeleteMessage:
        if (!_deleteController.isClosed) {
          _deleteController.add(frame as DeleteMessageFrame);
        }

      case kTypeWipe:
        if (!_wipeController.isClosed) _wipeController.add(null);

      case kTypeEphemeralMedia:
        if (!_ephemeralMediaController.isClosed) {
          _ephemeralMediaController.add(frame as EphemeralMediaFrame);
        }

      case kTypeFileProbe:
        if (!_fileProbeController.isClosed) {
          _fileProbeController.add(frame as FileProbeFrame);
        }

      case kTypeFileResume:
        if (!_fileResumeController.isClosed) {
          _fileResumeController.add(frame as FileResumeFrame);
        }

      case kTypeFileComplete:
        if (!_fileCompleteController.isClosed) {
          _fileCompleteController.add(frame as FileCompleteFrame);
        }

      case kTypeFileCancel:
        if (!_fileCancelController.isClosed) {
          _fileCancelController.add(frame as FileCancelFrame);
        }

      case kTypeGroupControl:
        if (!_groupControlController.isClosed) {
          _groupControlController.add(frame as GroupControlFrame);
        }

      case kTypeGroupMessage:
        if (!_groupMessageController.isClosed) {
          _groupMessageController.add(frame as GroupMessageFrame);
        }

      case kTypeCallSignal:
        if (!_callSignalController.isClosed) {
          _callSignalController.add(frame as CallSignalFrame);
        }

      case kTypeClose:
        await close();

      case kTypeVersionMismatch:
        await close();

      case kTypeProfileUpdate:
        break;

      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Frame reader — single entry point so the StreamIterator is never shared
  // ---------------------------------------------------------------------------

  Future<ProtocolFrame?> _readFrame() => _reader.readFrame();

  // ---------------------------------------------------------------------------
  // Keepalive
  // ---------------------------------------------------------------------------

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      kKeepaliveInterval,
      (_) => _onKeepaliveTick(),
    );
  }

  void _stopKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  void _onKeepaliveTick() {
    if (_state != ChannelState.active) return;
    if (DateTime.now().difference(_lastTrafficAt) >= kKeepaliveTimeout) {
      // Timeout — close without sending CloseFrame (peer is likely gone).
      close();
      return;
    }
    _writeFrame(
      KeepaliveFrame(counter: _keepaliveCounter++),
    ).catchError((_) => close());
  }

  // ---------------------------------------------------------------------------
  // Rekey
  // ---------------------------------------------------------------------------

  void _checkRekey() {
    if (_rekeyPending) return;
    final countExceeded = _outboundMessageCount >= kRekeyMessageCount;
    final timeExceeded =
        DateTime.now().difference(_sessionStart) >= kRekeyDuration;
    if (countExceeded || timeExceeded) {
      _rekeyPending = true;
      // Send CloseFrame with rekey reason; the app layer must prompt reconnect.
      sendClose(reason: 'rekey');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _setState(ChannelState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _assertActive() {
    if (_state != ChannelState.active) {
      throw StateError('SecureChannel not active (state=$_state)');
    }
  }

  Future<void> _writeFrame(ProtocolFrame frame) {
    final previous = _writeQueue.catchError((_) {});
    final next = previous.then((_) => writeFrame(_sink, frame));
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _sendRejectAndClose(String requestId, String reason) async {
    try {
      await _writeFrame(RejectFrame(requestId: requestId, reason: reason));
    } catch (_) {}
    await close();
  }

  // ---------------------------------------------------------------------------
  // Forward-secrecy key ratchet (HKDF-SHA256)
  // ---------------------------------------------------------------------------

  /// Initialise send/receive chain keys from the TLS connection.
  ///
  /// Uses the peer certificate's DER bytes as input keying material, then
  /// derives two independent 32-byte chain keys: one for sending and one for
  /// receiving. The ordering is deterministic — the side with the
  /// lexicographically smaller session ID gets the first derived key for
  /// sending and the second for receiving; the other side gets the reverse.
  Future<void> _initChainKeys() async {
    final localDer = _localStaticPublicKeyDer;
    final peerDer = _peerStaticPublicKeyDer;
    final peerSessionId = _peerSessionId;
    if (localDer == null || peerDer == null || peerSessionId == null) {
      throw const _ChannelError('Identity material unavailable for HKDF seed');
    }

    final keys = await deriveDirectionalChainKeys(
      localSessionId: localSessionId,
      peerSessionId: peerSessionId,
      localPublicKeyDer: localDer,
      peerPublicKeyDer: peerDer,
    );
    _sendChainKey = keys.sendChainKey;
    _recvChainKey = keys.receiveChainKey;
  }

  /// Derive the next chain key from [current] using HKDF-SHA256.
  Future<crypto.SecretKey> _ratchetKey(crypto.SecretKey current) async {
    return ratchetChainKey(current);
  }

  /// Ratchet the send chain key forward. Called after every sent message.
  Future<void> _ratchetSendKey() async {
    final key = _sendChainKey;
    if (key != null) {
      _sendChainKey = await _ratchetKey(key);
    }
  }

  /// Ratchet the receive chain key forward. Called after every received
  /// (non-duplicate) message.
  Future<void> _ratchetRecvKey() async {
    final key = _recvChainKey;
    if (key != null) {
      _recvChainKey = await _ratchetKey(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Crypto helpers (all static so they're pure functions)
  // ---------------------------------------------------------------------------

  /// Derive the RSA public key from a PointyCastle RSAPrivateKey.
  static RSAPublicKey _publicKeyFromPrivate(RSAPrivateKey priv) {
    final mod = priv.modulus;
    final exp = priv.publicExponent;
    if (mod == null || exp == null) {
      throw StateError('RSAPrivateKey is missing modulus or publicExponent');
    }
    return RSAPublicKey(mod, exp);
  }

  /// Encode an RSA public key as a SubjectPublicKeyInfo (SPKI) DER blob.
  static Uint8List _encodeSpkiDer(RSAPublicKey key) {
    final pem = CryptoUtils.encodeRSAPublicKeyToPem(key);
    return CryptoUtils.getBytesFromPEMString(pem);
  }

  /// Compute the 32-char hex fingerprint from a SPKI DER blob.
  /// Matches ProfileService: first 16 bytes (32 hex chars) of SHA-256 of the
  /// RSA modulus bytes.
  static String _fingerprintOfSpki(Uint8List der) {
    final key = CryptoUtils.rsaPublicKeyFromDERBytes(der);
    final modulus = key.modulus;
    if (modulus == null) {
      throw StateError('RSAPublicKey is missing modulus');
    }
    final hex = modulus.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final modulusBytes = Uint8List.fromList(
      List.generate(
        padded.length ~/ 2,
        (i) => int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );

    final digest = SHA256Digest();
    final hash = Uint8List(digest.digestSize);
    digest.update(modulusBytes, 0, modulusBytes.length);
    digest.doFinal(hash, 0);
    return hash
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
