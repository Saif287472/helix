import 'dart:typed_data';
import 'package:helix_local_domain/domain/models.dart';

abstract interface class PeerRepository {
  Future<List<Peer>> listKnownPeers();
  Future<void> rememberPeer(Peer peer);
  Future<void> forgetPeer(String sessionId);
}

abstract interface class ConversationRepository {
  List<ChatThread> listThreads();
  ChatThread? getThread(String threadId);
  Future<void> saveThread(ChatThread thread);
  Future<void> removeThread(String threadId);
}

abstract interface class DraftRepository {
  Future<String?> loadDraft(String conversationId);
  Future<void> saveDraft(String conversationId, String text);
  Future<void> clearDraft(String conversationId);
}

abstract interface class GroupRepository {
  List<GroupSnapshot> listGroups();
  GroupSnapshot? loadGroup(String groupId);
  Future<void> saveGroup(GroupSnapshot group);
  Future<void> removeGroup(String groupId);
}

abstract interface class TrustRepository {
  Future<List<KnownPeer>> loadKnownPeers();
  Future<void> saveKnownPeers(List<KnownPeer> peers);
}

abstract interface class ProfileRepository {
  Future<Profile?> loadProfile();
  Future<void> saveProfile(Profile profile);
  Future<void> clear();
}

abstract interface class SecureIdentityStore {
  Future<DeviceIdentity?> loadIdentity();
  Future<void> saveIdentity(DeviceIdentity identity);
  Future<String?> loadSecretCode();
  Future<void> saveSecretCode(String secretCode);
  Future<String?> loadSecretCodeVerifier();
  Future<void> saveSecretCodeVerifier(String verifier);
  Future<bool> isFirstRun();
  Future<void> setFirstRunDone();
  Future<void> clear();
}

abstract interface class ConnectionRequestRepository {
  List<ConnectionRequest> listRequests();
  ConnectionRequest? getRequest(String requestId);
  Future<void> saveRequest(ConnectionRequest request);
  Future<void> removeRequest(String requestId);

  // Block list
  bool isBlocked(String fingerprint);
  Future<void> blockPeer(String fingerprint);
  Future<void> unblockPeer(String fingerprint);
  Set<String> getBlockedPeers();

  // Session-fingerprint cache
  Future<void> cacheSessionFingerprint(String sessionId, String fingerprint);
  String? getFingerprintForSession(String sessionId);
}

abstract interface class TransferRepository {
  List<FileTransferSession> listTransfers();
  FileTransferSession? loadTransfer(String fileId);
  Future<void> saveTransfer(FileTransferSession transfer);
  Future<void> removeTransfer(String fileId);
  Future<void> clear();
}

abstract interface class EphemeralMediaCache {
  Uint8List? getMedia(String mediaId);
  bool hasMedia(String mediaId);
  void storeMedia(String mediaId, Uint8List bytes);
  void clear();
}

abstract interface class SessionRepository {
  Future<String?> loadSessionId();
  Future<void> saveSessionId(String sessionId);
  Future<void> clearSessionId();
}
