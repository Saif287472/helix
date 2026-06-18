import 'dart:async';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';

class ConnectionRequestUseCaseImpl implements ConnectionRequestUseCase {
  ConnectionRequestUseCaseImpl({
    required this._repository,
    required this._onIncoming,
    required this._onUpdate,
    required this._isPeerBlocked,
    required this._detectImpersonation,
    required this._generateRequestId,
    required this._tryConsumeGlobalRateLimit,
    required this._tryConsumeSourceRateLimit,
  });

  final ConnectionRequestRepository _repository;
  final void Function(ConnectionRequest request) _onIncoming;
  final void Function(ConnectionRequest request) _onUpdate;
  final bool Function(String fingerprint) _isPeerBlocked;
  final bool Function(String fingerprint, String displayName)
  _detectImpersonation;
  final String Function() _generateRequestId;
  final bool Function(int maxPerMinute) _tryConsumeGlobalRateLimit;
  final bool Function(String fingerprint, int maxPerMinute)
  _tryConsumeSourceRateLimit;

  @override
  Future<void> requestConnection(Peer peer) async {
    // Basic interface implementation, logic is handled in initiateRequest
  }

  @override
  Future<void> accept(String requestId) async {
    final request = _repository.getRequest(requestId);
    if (request == null) return;
    request.status = RequestStatus.accepted;
    await _repository.saveRequest(request);
    _onUpdate(request);
  }

  @override
  Future<void> reject(String requestId, String reason) async {
    final request = _repository.getRequest(requestId);
    if (request == null) return;
    request.status = RequestStatus.rejected;
    await _repository.saveRequest(request);
    _onUpdate(request);
  }

  Future<void> cancel(String requestId) async {
    final request = _repository.getRequest(requestId);
    if (request == null) return;
    request.status = RequestStatus.canceled;
    await _repository.saveRequest(request);
    _onUpdate(request);
  }

  Future<ConnectionRequest> initiateRequest({
    required Peer peer,
    required RequestSourceMethod source,
    required String localSessionId,
    required String localDeviceSuffix,
  }) async {
    if (localSessionId.isEmpty) {
      throw StateError(
        'Cannot send a request before the local session starts.',
      );
    }

    if (!_tryConsumeGlobalRateLimit(kMaxGlobalRequestsPerMinute)) {
      throw StateError('Global request rate limit exceeded.');
    }

    final outgoing = _repository.listRequests().where(
      (r) =>
          r.direction == RequestDirection.outgoing &&
          r.status == RequestStatus.pending,
    );
    if (outgoing.length >= kMaxPendingRequests) {
      throw StateError('Too many pending outbound requests.');
    }

    final requestId = _generateRequestId();
    final now = DateTime.now();

    final request = ConnectionRequest(
      requestId: requestId,
      direction: RequestDirection.outgoing,
      peerDisplayName: peer.displayName,
      peerDeviceSuffix: peer.deviceSuffix,
      peerSessionId: peer.sessionId,
      peerStaticKeyFingerprint: '',
      peerHost: peer.host,
      peerPort: peer.port,
      source: source,
      createdAt: now,
      expiresAt: now.add(kRequestTtl),
      status: RequestStatus.pending,
    );

    await _repository.saveRequest(request);
    _onUpdate(request);
    return request;
  }

  Future<ConnectionRequest?> processIncomingRequest({
    required String requestId,
    required String peerSessionId,
    required String peerDisplayName,
    required String peerSuffix,
    required String peerFingerprint,
    required String peerHost,
    required int peerPort,
    required bool isResume,
    required Future<bool> Function() triggerAutoAccept,
  }) async {
    if (requestId.isEmpty ||
        peerSessionId.isEmpty ||
        peerDisplayName.trim().isEmpty ||
        peerFingerprint.isEmpty) {
      return null;
    }

    if (_isPeerBlocked(peerFingerprint)) {
      return null;
    }

    if (isResume) {
      final autoAccepted = await triggerAutoAccept();
      if (autoAccepted) return null;
    }

    final duplicateIncoming = _findPendingIncomingFromPeer(
      sessionId: peerSessionId,
      fingerprint: peerFingerprint,
    );
    if (duplicateIncoming != null) {
      duplicateIncoming.status = RequestStatus.expired;
      _onUpdate(duplicateIncoming);
      await _repository.removeRequest(duplicateIncoming.requestId);
    }

    final incomingCount = _repository
        .listRequests()
        .where((r) =>
            r.direction == RequestDirection.incoming &&
            r.status == RequestStatus.pending)
        .length;
    if (incomingCount >= kMaxPendingRequests) {
      return null;
    }

    if (!_tryConsumeSourceRateLimit(
      peerFingerprint,
      kMaxRequestsPerSourcePerMinute,
    )) {
      return null;
    }

    // Simultaneous request merging
    final existingOutgoing = _repository.listRequests().firstWhere(
      (r) =>
          r.peerSessionId == peerSessionId &&
          r.direction == RequestDirection.outgoing &&
          r.status == RequestStatus.pending,
      orElse: () => _sentinel,
    );
    if (!identical(existingOutgoing, _sentinel)) {
      if (existingOutgoing.requestId.compareTo(requestId) < 0) {
        // Our outgoing request wins
        return null;
      } else {
        // Their request wins
        await cancel(existingOutgoing.requestId);
      }
    }

    final now = DateTime.now();
    final request = ConnectionRequest(
      requestId: requestId,
      direction: RequestDirection.incoming,
      peerDisplayName: peerDisplayName,
      peerDeviceSuffix: peerSuffix,
      peerSessionId: peerSessionId,
      peerStaticKeyFingerprint: peerFingerprint,
      peerHost: peerHost,
      peerPort: peerPort,
      source: RequestSourceMethod.nearby,
      createdAt: now,
      expiresAt: now.add(kRequestTtl),
      status: RequestStatus.pending,
    );

    await _repository.cacheSessionFingerprint(peerSessionId, peerFingerprint);

    if (_detectImpersonation(peerFingerprint, peerDisplayName)) {
      request.isPossibleImpersonation = true;
    }

    await _repository.saveRequest(request);
    _onIncoming(request);
    return request;
  }

  ConnectionRequest? _findPendingIncomingFromPeer({
    required String sessionId,
    required String fingerprint,
  }) {
    for (final request in _repository.listRequests()) {
      if (request.direction != RequestDirection.incoming ||
          request.status != RequestStatus.pending) {
        continue;
      }
      if (fingerprint.isNotEmpty &&
          request.peerStaticKeyFingerprint == fingerprint) {
        return request;
      }
      if (sessionId.isNotEmpty && request.peerSessionId == sessionId) {
        return request;
      }
    }
    return null;
  }

  static final _sentinel = ConnectionRequest(
    requestId: '',
    direction: RequestDirection.outgoing,
    peerDisplayName: '',
    peerDeviceSuffix: '',
    peerSessionId: '__sentinel__',
    peerStaticKeyFingerprint: '',
    peerHost: '',
    peerPort: 0,
    source: RequestSourceMethod.nearby,
    createdAt: DateTime(0),
    expiresAt: DateTime(0),
  );
}
