import 'package:helix_remote_domain/models.dart';

abstract class HelixRemoteRestClient {
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String identityPublicKey,
    required String deviceId,
    required String devicePublicKey,
    required String deviceName,
  });

  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  });

  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  });

  Future<Map<String, dynamic>> refreshToken({required String refreshToken});

  Future<List<RemoteDevice>> listDevices();

  Future<void> revokeDevice(String deviceId);

  Future<void> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  });

  Future<Map<String, dynamic>> getPreKeyBundle({required String accountId});

  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  });

  Future<void> acceptContactRequest(String requestId);

  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  });

  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId);

  Future<void> requestAccountDeletion({required String confirmation});

  Future<Map<String, dynamic>> exportData();

  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  });

  Future<Map<String, dynamic>> downloadBackup();

  Future<Map<String, dynamic>> sendCallSignal({
    required String targetDeviceId,
    required Map<String, dynamic> payload,
  });

  set accessToken(String? token);

  Future<void> close();
}
