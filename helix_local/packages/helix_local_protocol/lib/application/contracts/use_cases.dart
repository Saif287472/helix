import 'dart:io';
import 'dart:typed_data';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';

abstract interface class SendMessageUseCase {
  Future<void> sendText({
    required String threadId,
    required String text,
    String? replyToMessageId,
  });
}

abstract interface class ReceiveMessageCoordinator {
  Future<void> receive(ChatMessage message);
}

abstract interface class DeliveryReceiptTracker {
  Future<void> markDelivered(String messageId);
  Future<void> markRead(String messageId);
}

abstract interface class ConnectionRequestUseCase {
  Future<void> requestConnection(Peer peer);
  Future<void> accept(String requestId);
  Future<void> reject(String requestId, String reason);
}

abstract interface class HandshakeCoordinator {
  Future<void> beginHandshake(Peer peer);
}

abstract interface class PeerConnectionManager {
  Future<void> connect(Peer peer);
  Future<void> disconnect(String peerId);
}

abstract interface class CreateGroupUseCase {
  Future<GroupSnapshot> createPublicLobby();
  Future<GroupSnapshot> createPrivateGroup(String displayName);
}

abstract interface class GroupMembershipManager {
  Future<void> approve(String groupId, String fingerprint);
  Future<void> deny(String groupId, String fingerprint);
  Future<void> kick(String groupId, String fingerprint);
}

abstract interface class SendFileUseCase {
  Future<void> sendFile({
    required String threadId,
    required String messageId,
    required String fileId,
    required File file,
    required String mimeType,
    required TransferGateway gateway,
  });
}

abstract interface class ReceiveFileCoordinator {
  Future<File?> receiveChunk({
    required String threadId,
    required String messageId,
    required FileTransferFrame frame,
  });

  Future<void> receiveProbe({
    required String threadId,
    required String messageId,
    required FileProbeFrame frame,
    required TransferGateway gateway,
  });

  Future<void> receiveComplete({
    required String threadId,
    required String messageId,
    required String fileId,
    required String expectedSha256,
  });

  Future<void> cancelTransfer(String fileId);
  Future<void> cancelAllTransfers();
  Future<void> dispose();
}

abstract interface class SendEphemeralMediaUseCase {
  Future<Uint8List> prepareImage(Uint8List bytes);
  Uint8List prepareVoice(Uint8List bytes);
  Future<void> sendMedia({
    required String mediaId,
    required String mimeType,
    required Uint8List prepared,
    required String threadId,
    required String messageId,
    required EphemeralMediaGateway gateway,
  });
}

abstract interface class InitiateCallUseCase {
  Future<void> initiateCall({
    required String peerId,
    required String peerDisplayName,
  });
}

abstract interface class HandleCallSignalUseCase {
  Future<void> handleSignal(
    String peerId,
    String peerDisplayName,
    CallSignalFrame frame,
  );
}

abstract interface class ReceiveEphemeralMediaCoordinator {
  Uint8List? receiveChunk(EphemeralMediaFrame frame);
  void cancelAssembly(String mediaId);
  bool isAssembling(String mediaId);
  void dispose();
}

abstract interface class IdentityManager {
  Profile? get profile;
  DeviceIdentity? get identity;
  bool get isFirstRun;
  Stream<Profile> get profileChanges;

  Future<void> init();
  Future<void> createProfile(
    String displayName,
    String secretCode,
    DiscoverabilityState disc,
  );
  Future<void> updateDisplayName(String name);
  Future<void> updateSecretCode(String code);
  Future<String?> getSecretCode();
  Future<String?> getSecretCodeVerifier();
  Future<void> updateDiscoverability(DiscoverabilityState state);
  Future<void> updatePreferences({
    bool? notifyShowSender,
    bool? notifySound,
    bool? copyEnabled,
    bool? screenshotProtect,
    String? themeMode,
    String? accentColor,
    bool? amoledDark,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? homeWelcomeDismissed,
    bool? biometricLock,
    int? lockAfterMinutes,
    String? ringtoneAsset,
  });
  Future<void> resetPreferencesToDefaults();
  Future<void> reset();
  String generateDicewarePassphrase();
  String? validateDisplayName(String name);
  String? validateSecretCode(String code);
  void dispose();
}

abstract interface class TrustUseCase {
  List<KnownPeer> get allPeers;
  List<KnownPeer> get trustedPeers;
  Stream<List<KnownPeer>> get changes;

  Future<void> init();
  KnownPeer? getPeer(String fingerprint);
  bool isKnown(String fingerprint);
  bool isTrusted(String fingerprint);
  String displayNameFor(String fingerprint, String fallback);
  KnownPeer? detectImpersonation(String incomingFp, String incomingName);
  Future<void> markKnown(
    String fingerprint,
    String publicName,
    String deviceSuffix,
    String host,
    int port,
  );
  Future<void> trustPeer(String fingerprint, String nickname);
  Future<void> untrustPeer(String fingerprint);
  Future<void> forgetPeer(String fingerprint);
  Future<void> renamePeer(String fingerprint, String nickname);
  Future<void> clearAllPeers();
  void dispose();
}

abstract interface class DisconnectWipeScheduler {
  void scheduleWipe(String threadId, Duration delay, void Function() onWipe);
  void cancelWipe(String threadId);
  void cancelAll();
}

abstract interface class ReconnectionCoordinator {
  void start();
  void stop();
}

abstract interface class ActiveSessionTracker {
  SessionState get state;
  String get sessionId;
  Stream<SessionState> get stateChanges;

  Future<void> startSession(Profile profile, DeviceIdentity identity);
  Future<void> stopSession();
  Future<bool> resumeSession();
  void dispose();
}

abstract interface class DiagnosticsUseCase {
  void recordBindError(String message);
  Future<NetworkDiagnostics> getDiagnostics({
    int tcpPort = 0,
    bool tcpActive = false,
    bool mdnsActive = false,
    bool udpActive = false,
  });
}

abstract interface class QrCodeUseCase {
  String encode(QrPayload payload);
  QrPayload? decode(String raw);
  Peer payloadToPeer(QrPayload payload);
  List<Peer> payloadToPeers(QrPayload payload);
}

abstract interface class SecretCodeUseCase {
  bool isChallengePacket(Uint8List packet);
  Future<String> deriveVerifier(String code);
  Future<void> broadcastSearch(
    String enteredCode,
    RawDatagramSocket socket,
    List<String> broadcastAddresses,
  );
  Future<bool> handleChallenge(
    Uint8List packet,
    String storedVerifier,
    RawDatagramSocket replySocket,
    InternetAddress requesterAddr,
    int requesterPort,
    String sessionId,
    String displayName,
    String deviceSuffix,
    int tcpPort,
  );
  Future<Peer?> waitForResponse(RawDatagramSocket socket, Duration timeout);
  Future<List<Peer>> waitForResponses(
    RawDatagramSocket socket,
    Duration timeout,
  );
  Future<List<Peer>> search(
    String enteredCode, {
    Duration timeout,
    List<String> broadcastAddresses,
  });
}

abstract interface class TcpServerUseCase {
  bool get isRunning;
  int get port;
  Stream<SecureSocket> get incomingConnections;
  Future<void> start(SecurityContext context);
  Future<void> stop();
  void dispose();
}
