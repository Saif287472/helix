import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:helix/application/connection/connection_request_use_case_impl.dart';
import 'package:helix/providers/controllers/trust_service.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

import 'package:helix_local_transport/services/transport/secure_channel.dart';

class RequestConnectionResult {
  const RequestConnectionResult({required this.request, this.channel});

  final ConnectionRequest request;
  final SecureChannel? channel;
}

class AutoResumeChannel {
  const AutoResumeChannel({
    required this.threadId,
    required this.peerDisplayName,
    required this.peerDeviceSuffix,
    required this.peerSessionId,
    required this.peerHost,
    required this.peerPort,
    required this.channel,
  });

  final String threadId;
  final String peerDisplayName;
  final String peerDeviceSuffix;
  final String peerSessionId;
  final String peerHost;
  final int peerPort;
  final SecureChannel channel;
}

typedef ResumeCheck =
    Future<({DeviceIdentity identity, String sessionId})?> Function(
      String peerFingerprint,
    );

class _SourceTracker {
  final _timestamps = <DateTime>[];
  DateTime lastUsed = DateTime.now();

  bool tryConsume(int maxPerMinute) {
    final now = DateTime.now();
    lastUsed = now;
    _timestamps.removeWhere((t) => now.difference(t).inMinutes >= 1);
    if (_timestamps.length >= maxPerMinute) return false;
    _timestamps.add(now);
    return true;
  }
}

class RequestService implements RequestValidator {
  RequestService({
    required ConnectionRequestRepository connectionRequestRepository,
    ConnectionRequestUseCaseImpl? connectionRequestUseCase,
  }) {
    _connectionRequestRepository = connectionRequestRepository;
    _connectionRequestUseCase =
        connectionRequestUseCase ??
        ConnectionRequestUseCaseImpl(
          repository: _connectionRequestRepository,
          onIncoming: emitIncoming,
          onUpdate: emitUpdate,
          isPeerBlocked: isBlocked,
          detectImpersonation: (fingerprint, displayName) =>
              _trustService?.detectImpersonation(fingerprint, displayName) !=
              null,
          generateRequestId: () => const Uuid().v4(),
          tryConsumeGlobalRateLimit: tryConsumeGlobalRateLimit,
          tryConsumeSourceRateLimit: tryConsumeSourceRateLimit,
        );
  }

  late final ConnectionRequestRepository _connectionRequestRepository;
  late final ConnectionRequestUseCaseImpl _connectionRequestUseCase;

  TrustService? _trustService;
  TrustService? get trustService => _trustService;
  void setTrustService(TrustService svc) => _trustService = svc;

  ResumeCheck? _resumeCheck;
  final _activeSockets = <String, Socket>{};
  final _socketTimers = <String, Timer>{};

  Socket? _removeActiveSocket(String requestId) {
    _socketTimers.remove(requestId)?.cancel();
    return _activeSockets.remove(requestId);
  }

  final _globalTracker = _SourceTracker();
  final _sourceTrackers = <String, _SourceTracker>{};
  final _oneWaySendTrackers = <String, _SourceTracker>{};
  final _localBlockedPeers = <String>{};

  String _localSessionId = '';
  String _localDisplayName = '';
  String _localDeviceSuffix = '';
  int _localTcpPort = 0;

  final _oneWayController = StreamController<OneWayMessage>.broadcast();
  final _resumeController = StreamController<AutoResumeChannel>.broadcast();
  final _incomingCtrl = StreamController<ConnectionRequest>.broadcast();
  final _updateCtrl = StreamController<ConnectionRequest>.broadcast();
  final _blockedPeersCtrl = StreamController<Set<String>>.broadcast();

  Map<String, ConnectionRequest> get pendingRequests {
    final list = _connectionRequestRepository.listRequests();
    return {for (final request in list) request.requestId: request};
  }

  Set<String> get blockedPeers =>
      _connectionRequestRepository.getBlockedPeers().union(_localBlockedPeers);

  Stream<ConnectionRequest> get incomingRequests => _incomingCtrl.stream;
  Stream<ConnectionRequest> get requestUpdates => _updateCtrl.stream;
  Stream<OneWayMessage> get incomingOneWayMessages => _oneWayController.stream;
  Stream<AutoResumeChannel> get resumeChannels => _resumeController.stream;
  Stream<Set<String>> get blockedPeersStream => _blockedPeersCtrl.stream;

  void start() {}

  void configureLocalSession({
    required String sessionId,
    required String displayName,
    required String deviceSuffix,
    required int tcpPort,
  }) {
    _localSessionId = sessionId;
    _localDisplayName = displayName;
    _localDeviceSuffix = deviceSuffix;
    _localTcpPort = tcpPort;
  }

  void emitIncoming(ConnectionRequest req) {
    if (!_incomingCtrl.isClosed) _incomingCtrl.add(req);
  }

  void emitUpdate(ConnectionRequest req) {
    if (!_updateCtrl.isClosed) _updateCtrl.add(req);
  }

  void setResumeCheck(ResumeCheck check) {
    _resumeCheck = check;
  }

  bool isBlocked(String fingerprint) => blockedPeers.contains(fingerprint);

  void _pruneTrackers() {
    final now = DateTime.now();
    _sourceTrackers.removeWhere((_, tracker) => now.difference(tracker.lastUsed).inMinutes >= 1);
    _oneWaySendTrackers.removeWhere((_, tracker) => now.difference(tracker.lastUsed).inMinutes >= 1);
  }

  bool tryConsumeGlobalRateLimit(int maxPerMinute) =>
      _globalTracker.tryConsume(maxPerMinute);

  bool tryConsumeSourceRateLimit(String fingerprint, int maxPerMinute) =>
      (_sourceTrackers..removeWhere((_, tracker) => DateTime.now().difference(tracker.lastUsed).inMinutes >= 1))
          .putIfAbsent(fingerprint, () => _SourceTracker())
          .tryConsume(maxPerMinute);

  String? fingerprintForSession(String sessionId) =>
      _connectionRequestRepository.getFingerprintForSession(sessionId);

  @override
  ConnectionRequest? validateIncoming(RequestFrame frame) {
    final request = _connectionRequestRepository.getRequest(frame.requestId);
    if (request == null || request.status != RequestStatus.pending) {
      return null;
    }
    if (isBlocked(frame.staticKeyFingerprint)) return null;
    return request;
  }

  Future<RequestConnectionResult> sendRequest(
    Peer peer,
    RequestSourceMethod source,
    DeviceIdentity localIdentity,
    String localSessionId,
    String localDisplayName, {
    int localTcpPort = 0,
    bool isResume = false,
    String resumeThreadId = '',
    Duration connectTimeout = const Duration(seconds: 5),
    Duration responseTimeout = const Duration(seconds: 10),
  }) async {
    final request = await _connectionRequestUseCase.initiateRequest(
      peer: peer,
      source: source,
      localSessionId: localSessionId,
      localDeviceSuffix: localIdentity.deviceSuffix,
    );

    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: connectTimeout,
      );
      _activeSockets[request.requestId] = socket;

      final expiresAt = DateTime.now().add(kRequestTtl).millisecondsSinceEpoch;
      final frame = RequestFrame(
        requestId: request.requestId,
        displayName: localDisplayName,
        deviceSuffix: localIdentity.deviceSuffix,
        sessionId: localSessionId,
        staticKeyFingerprint: localIdentity.staticPublicKeyFingerprint,
        protocolMajor: kProtocolMajor,
        protocolMinor: kProtocolMinor,
        port: localTcpPort,
        expiresAt: expiresAt,
      );
      _sendLengthPrefixedFrame(socket, frame.encode());
      await socket.flush();

      final response = await _readProtocolFrame(socket, responseTimeout);
      if (response is AcceptFrame) {
        socket.destroy();
        socket = null;

        final channel = await SecureChannel.connect(
          host: peer.host,
          port: response.connectPort > 0 ? response.connectPort : peer.port,
          localIdentity: localIdentity,
          localSessionId: localSessionId,
          request: request,
        );

        request.status = RequestStatus.accepted;
        await _connectionRequestRepository.saveRequest(request);
        emitUpdate(request);
        _removeActiveSocket(request.requestId);
        return RequestConnectionResult(request: request, channel: channel);
      }

      request.status = response is RejectFrame
          ? RequestStatus.rejected
          : RequestStatus.expired;
      await _connectionRequestRepository.saveRequest(request);
      emitUpdate(request);
      return RequestConnectionResult(request: request);
    } catch (_) {
      request.status = RequestStatus.expired;
      await _connectionRequestRepository.saveRequest(request);
      emitUpdate(request);
      rethrow;
    } finally {
      _removeActiveSocket(request.requestId);
      socket?.destroy();
    }
  }

  Future<SecureChannel?> acceptRequest(
    String requestId,
    DeviceIdentity localIdentity,
    String localSessionId,
  ) async {
    final request = _connectionRequestRepository.getRequest(requestId);
    if (request == null || request.direction != RequestDirection.incoming) {
      return null;
    }

    Socket? socket = _removeActiveSocket(requestId);
    if (socket == null) return null;
    ServerSocket? secureListener;
    Socket? acceptedSocket;
    SecureChannel? channel;

    try {
      secureListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);

      _sendLengthPrefixedFrame(
        socket,
        AcceptFrame(
          requestId: requestId,
          connectPort: secureListener.port,
        ).encode(),
      );
      await socket.flush();
      socket.destroy();
      socket = null;

      acceptedSocket =
          await secureListener.first.timeout(const Duration(seconds: 15));
      channel = await SecureChannel.acceptConnection(
        rawSocket: acceptedSocket,
        localIdentity: localIdentity,
        localSessionId: localSessionId,
        requestService: this,
      );
      acceptedSocket = null; // owned by channel now

      request.status = RequestStatus.accepted;
      await _connectionRequestRepository.saveRequest(request);
      emitUpdate(request);
      return channel;
    } catch (_) {
      acceptedSocket?.destroy();
      await channel?.close();
      request.status = RequestStatus.expired;
      await _connectionRequestRepository.saveRequest(request);
      emitUpdate(request);
      rethrow;
    } finally {
      await secureListener?.close();
      socket?.destroy();
    }
  }

  Future<void> rejectRequest(String requestId) async {
    final request = _connectionRequestRepository.getRequest(requestId);
    if (request == null || request.direction != RequestDirection.incoming) {
      return;
    }

    request.status = RequestStatus.rejected;
    await _connectionRequestRepository.saveRequest(request);
    emitUpdate(request);

    final socket = _removeActiveSocket(requestId);
    if (socket != null) {
      try {
        _sendLengthPrefixedFrame(
          socket,
          RejectFrame(requestId: requestId, reason: 'rejected').encode(),
        );
        await socket.flush();
      } catch (_) {
        // Best effort: rejecting must not surface socket details to the UI.
      }
      socket.destroy();
    }
  }

  Future<void> cancelRequest(String requestId) async {
    final request = _connectionRequestRepository.getRequest(requestId);
    if (request == null) return;
    request.status = RequestStatus.canceled;
    await _connectionRequestRepository.saveRequest(request);
    emitUpdate(request);
    closeRequestSocket(requestId);
  }

  Future<void> blockPeer(String fingerprint) async {
    await _connectionRequestRepository.blockPeer(fingerprint);
    _blockedPeersCtrl.add(blockedPeers);
  }

  Future<void> unblockPeer(String fingerprint) async {
    await _connectionRequestRepository.unblockPeer(fingerprint);
    _localBlockedPeers.remove(fingerprint);
    _blockedPeersCtrl.add(blockedPeers);
  }

  void blockPeerSessionOnly(String fingerprint) {
    _localBlockedPeers.add(fingerprint);
    _blockedPeersCtrl.add(blockedPeers);
  }

  void closeRequestSocket(String requestId) {
    final socket = _removeActiveSocket(requestId);
    socket?.destroy();
  }

  void clearRequest(String requestId) {
    _connectionRequestRepository.removeRequest(requestId);
  }

  void clearAllRequests() {
    for (final request in _connectionRequestRepository.listRequests()) {
      _connectionRequestRepository.removeRequest(request.requestId);
    }
  }

  Future<void> sendOneWayMessage(
    Peer peer,
    DeviceIdentity localIdentity,
    String localSessionId,
    String localDisplayName,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Message text must not be empty');
    if (utf8.encode(trimmed).length > kMaxMessageBytes) {
      throw ArgumentError('Message text exceeds maximum size');
    }

    final targetKey = '${peer.host}:${peer.port}';
    _pruneTrackers();
    if (!_oneWaySendTrackers
        .putIfAbsent(targetKey, () => _SourceTracker())
        .tryConsume(kMaxOneWaySendsPerTargetPerMinute)) {
      throw StateError(
        'Too many one-way messages sent to this device. Try again in a minute.',
      );
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 5),
      );
      socket.add(
        Uint8List.fromList([
          0xFE,
          ...utf8.encode(
            jsonEncode({
              'fingerprint': localIdentity.staticPublicKeyFingerprint,
              'displayName': localDisplayName,
              'deviceSuffix': localIdentity.deviceSuffix,
              'sessionId': localSessionId,
              'messageId': const Uuid().v4(),
              'text': trimmed,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          ),
        ]),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      socket?.destroy();
    }
  }

  Future<void> handleIncomingTcpConnection(Socket socket) async {
    try {
      final bytes = await _readRawPacket(socket);
      if (bytes.isEmpty) {
        socket.destroy();
        return;
      }

      if (bytes[0] == 0xFF) {
        _handleDirectIpProbe(socket, bytes);
        return;
      }

      final oneWay = _tryDecodeOneWay(bytes, socket);
      if (oneWay) return;

      final frame = ProtocolFrame.decode(Uint8List.fromList(bytes));
      if (frame is! RequestFrame) {
        socket.destroy();
        return;
      }

      final resumeConfig = await _resumeCheck?.call(frame.staticKeyFingerprint);
      if (resumeConfig != null) {
        await _autoAcceptResume(socket, frame, resumeConfig);
        return;
      }

      final request = await _connectionRequestUseCase.processIncomingRequest(
        requestId: frame.requestId,
        peerSessionId: frame.sessionId,
        peerDisplayName: frame.displayName,
        peerSuffix: frame.deviceSuffix,
        peerFingerprint: frame.staticKeyFingerprint,
        peerHost: socket.remoteAddress.address,
        peerPort: frame.port > 0 ? frame.port : socket.remotePort,
        isResume: false,
        triggerAutoAccept: () async => false,
      );

      if (request == null) {
        _sendLengthPrefixedFrame(
          socket,
          RejectFrame(requestId: frame.requestId, reason: 'rejected').encode(),
        );
        await socket.flush();
        socket.destroy();
        return;
      }

      final oldSocket = _activeSockets[request.requestId];
      if (oldSocket != null) {
        try {
          oldSocket.destroy();
        } catch (_) {}
      }
      final expectedSocket = socket;
      _activeSockets[request.requestId] = expectedSocket;

      final oldTimer = _socketTimers[request.requestId];
      if (oldTimer != null) {
        oldTimer.cancel();
      }

      final ttl = request.expiresAt.difference(DateTime.now());
      if (ttl > Duration.zero) {
        _socketTimers[request.requestId] = Timer(ttl, () {
          if (identical(_activeSockets[request.requestId], expectedSocket)) {
            _activeSockets.remove(request.requestId);
            _socketTimers.remove(request.requestId);
            expectedSocket.destroy();
          }
        });
      } else {
        expectedSocket.destroy();
      }
    } catch (_) {
      socket.destroy();
    }
  }

  Future<void> close() async {
    for (final t in _socketTimers.values) {
      t.cancel();
    }
    _socketTimers.clear();
    final sockets = List<Socket>.of(_activeSockets.values);
    _activeSockets.clear();
    for (final socket in sockets) {
      socket.destroy();
    }
    await _oneWayController.close();
    await _resumeController.close();
    await _incomingCtrl.close();
    await _updateCtrl.close();
    await _blockedPeersCtrl.close();
  }

  Future<void> _autoAcceptResume(
    Socket socket,
    RequestFrame frame,
    ({DeviceIdentity identity, String sessionId}) resumeConfig,
  ) async {
    ServerSocket? listener;
    Socket? acceptedSocket;
    SecureChannel? channel;

    final now = DateTime.now();
    final request = ConnectionRequest(
      requestId: frame.requestId,
      direction: RequestDirection.incoming,
      peerDisplayName: frame.displayName,
      peerDeviceSuffix: frame.deviceSuffix,
      peerSessionId: frame.sessionId,
      peerStaticKeyFingerprint: frame.staticKeyFingerprint,
      peerHost: socket.remoteAddress.address,
      peerPort: frame.port > 0 ? frame.port : socket.remotePort,
      source: RequestSourceMethod.nearby,
      createdAt: now,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(frame.expiresAt),
      status: RequestStatus.pending,
    );
    await _connectionRequestRepository.saveRequest(request);

    try {
      listener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);

      _sendLengthPrefixedFrame(
        socket,
        AcceptFrame(
          requestId: frame.requestId,
          connectPort: listener.port,
        ).encode(),
      );
      await socket.flush();
      socket.destroy();

      acceptedSocket = await listener.first.timeout(const Duration(seconds: 15));
      channel = await SecureChannel.acceptConnection(
        rawSocket: acceptedSocket,
        localIdentity: resumeConfig.identity,
        localSessionId: resumeConfig.sessionId,
        requestService: this,
      ).timeout(const Duration(seconds: 15));

      request.status = RequestStatus.accepted;
      await _connectionRequestRepository.saveRequest(request);

      _resumeController.add(
        AutoResumeChannel(
          threadId: frame.staticKeyFingerprint,
          peerDisplayName: frame.displayName,
          peerDeviceSuffix: frame.deviceSuffix,
          peerSessionId: frame.sessionId,
          peerHost: request.peerHost,
          peerPort: request.peerPort,
          channel: channel,
        ),
      );
    } catch (_) {
      acceptedSocket?.destroy();
      await channel?.close().catchError((_) {});
      rethrow;
    } finally {
      try { await listener?.close(); } catch (_) {}
    }
  }

  void _handleDirectIpProbe(Socket socket, List<int> bytes) {
    if (_localSessionId.isEmpty || _localDisplayName.isEmpty) {
      socket.destroy();
      return;
    }

    final sessionBytes = utf8.encode(_localSessionId);
    final nameBytes = utf8.encode(_localDisplayName);
    final suffixBytes = utf8.encode(_localDeviceSuffix);
    final response = Uint8List(
      5 +
          1 +
          sessionBytes.length +
          1 +
          nameBytes.length +
          1 +
          suffixBytes.length,
    );
    var offset = 0;
    response[offset++] = 0x01;
    response[offset++] = kProtocolMajor;
    response[offset++] = kProtocolMinor;
    response[offset++] = (_localTcpPort >> 8) & 0xFF;
    response[offset++] = _localTcpPort & 0xFF;
    response[offset++] = sessionBytes.length;
    response.setRange(offset, offset + sessionBytes.length, sessionBytes);
    offset += sessionBytes.length;
    response[offset++] = nameBytes.length;
    response.setRange(offset, offset + nameBytes.length, nameBytes);
    offset += nameBytes.length;
    response[offset++] = suffixBytes.length;
    response.setRange(offset, offset + suffixBytes.length, suffixBytes);

    socket.add(response);
    socket.flush().whenComplete(socket.destroy);
  }

  bool _tryDecodeOneWay(List<int> bytes, Socket socket) {
    if (bytes.isEmpty || bytes[0] != 0xFE) {
      return false;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes.sublist(1)));
    } catch (_) {
      socket.destroy();
      return true;
    }
    if (decoded is! Map<String, Object?>) {
      socket.destroy();
      return true;
    }

    final fingerprint = decoded['fingerprint'] as String? ?? '';
    if (isBlocked(fingerprint)) {
      socket.destroy();
      return true;
    }

    final message = OneWayMessage(
      peerStaticKeyFingerprint: fingerprint,
      peerDisplayName: decoded['displayName'] as String? ?? 'Unknown Peer',
      peerDeviceSuffix: decoded['deviceSuffix'] as String? ?? '',
      peerSessionId: decoded['sessionId'] as String? ?? '',
      messageId: decoded['messageId'] as String? ?? const Uuid().v4(),
      text: decoded['text'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        decoded['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      peerHost: socket.remoteAddress.address,
      peerPort: socket.remotePort,
      expiresAt: DateTime.now().add(kOneWayMessageTtl),
    );
    socket.destroy();
    if (!_oneWayController.isClosed) _oneWayController.add(message);
    return true;
  }

  void _sendLengthPrefixedFrame(Socket socket, Uint8List payload) {
    final prefix = Uint8List(4);
    ByteData.view(prefix.buffer).setUint32(0, payload.length, Endian.big);
    socket.add(prefix);
    socket.add(payload);
  }

  Future<ProtocolFrame?> _readProtocolFrame(
    Socket socket, [
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    final bytes = await _readRawPacket(socket, timeout);
    if (bytes.isEmpty) return null;
    return ProtocolFrame.decode(Uint8List.fromList(bytes));
  }

  Future<List<int>> _readRawPacket(
    Socket socket, [
    Duration timeout = const Duration(seconds: 10),
  ]) {
    final completer = Completer<List<int>>();
    final bytes = <int>[];
    Timer? settleTimer;
    StreamSubscription<Uint8List>? subscription;
    int? expectedLength;
    bool isPrefixed = false;

    void complete() {
      if (completer.isCompleted) return;
      settleTimer?.cancel();
      subscription?.cancel();
      completer.complete(bytes);
    }

    const maxPacketBytes = 128 * 1024;

    subscription = socket.listen(
      (chunk) {
        if (bytes.isEmpty && chunk.isNotEmpty) {
          if (chunk[0] == 0x00) {
            isPrefixed = true;
          }
        }

        if (bytes.length + chunk.length > maxPacketBytes) {
          settleTimer?.cancel();
          subscription?.cancel();
          socket.destroy();
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Control packet too large'),
            );
          }
          return;
        }

        bytes.addAll(chunk);

        if (isPrefixed) {
          if (expectedLength == null && bytes.length >= 4) {
            final data = Uint8List.fromList(bytes.sublist(0, 4));
            expectedLength = ByteData.view(data.buffer).getUint32(0, Endian.big);
            if (expectedLength! < 0 || expectedLength! > maxPacketBytes) {
              subscription?.cancel();
              socket.destroy();
              if (!completer.isCompleted) {
                completer.completeError(
                  StateError('Invalid frame length: $expectedLength'),
                );
              }
              return;
            }
          }
          if (expectedLength != null && bytes.length >= 4 + expectedLength!) {
            final payload = bytes.sublist(4, 4 + expectedLength!);
            settleTimer?.cancel();
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete(payload);
            }
          }
        } else {
          settleTimer?.cancel();
          settleTimer = Timer(const Duration(milliseconds: 25), complete);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        settleTimer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (isPrefixed) {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Connection closed before frame fully received'),
            );
          }
        } else {
          complete();
        }
      },
      cancelOnError: true,
    );

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        settleTimer?.cancel();
        subscription?.cancel();
        if (isPrefixed) {
          throw TimeoutException('Timeout waiting for request frame');
        } else {
          complete();
          return bytes;
        }
      },
    );
  }
}
