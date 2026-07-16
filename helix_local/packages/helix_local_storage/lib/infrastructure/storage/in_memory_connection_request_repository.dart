import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_domain/domain/models.dart';

class InMemoryConnectionRequestRepository
    implements ConnectionRequestRepository {
  final Map<String, ConnectionRequest> _pending = {};
  final Set<String> _blocked = {};
  final Map<String, String> _sessionFingerprints = {};

  @override
  List<ConnectionRequest> listRequests() {
    return _pending.values.toList();
  }

  @override
  ConnectionRequest? getRequest(String requestId) {
    return _pending[requestId];
  }

  @override
  Future<void> saveRequest(ConnectionRequest request) async {
    _pending[request.requestId] = request;
  }

  @override
  Future<void> removeRequest(String requestId) async {
    _pending.remove(requestId);
  }

  @override
  bool isBlocked(String fingerprint) {
    return _blocked.contains(fingerprint);
  }

  @override
  Future<void> blockPeer(String fingerprint) async {
    _blocked.add(fingerprint);
  }

  @override
  Future<void> unblockPeer(String fingerprint) async {
    _blocked.remove(fingerprint);
  }

  @override
  Set<String> getBlockedPeers() {
    return _blocked;
  }

  @override
  Future<void> cacheSessionFingerprint(
    String sessionId,
    String fingerprint,
  ) async {
    _sessionFingerprints[sessionId] = fingerprint;
  }

  @override
  String? getFingerprintForSession(String sessionId) {
    return _sessionFingerprints[sessionId];
  }
}
