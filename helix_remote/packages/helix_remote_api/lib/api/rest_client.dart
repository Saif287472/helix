import 'package:helix_remote_domain/models.dart';

abstract class HelixRemoteRestClient {
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String displayName,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
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

  Future<Map<String, dynamic>> requestNewDeviceLink({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
  });

  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  });

  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  });

  Future<Map<String, dynamic>> completeNewDeviceLink({
    required String linkId,
    required String signature,
  });

  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  });

  Future<void> revokeDevice(String deviceId);

  Future<void> reportLostDevice(String deviceId);

  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(String deviceId);

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

  Future<Map<String, dynamic>> requestBackupMediaUpload({
    required String objectId,
    required int byteSize,
    required String sha256,
  });

  Future<Map<String, dynamic>> getBackupMediaStatus(String objectId);

  Future<List<Map<String, dynamic>>> searchContacts(String query);

  Future<Map<String, dynamic>> getMyProfile();
  Future<Map<String, dynamic>> updateDisplayName(String displayName);
  Future<Map<String, dynamic>> changeUsername(String username);

  Future<Map<String, dynamic>> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required Map<String, dynamic> payload,
    String? requestId,
  });

  Future<Map<String, dynamic>> getPendingCalls();
  Future<Map<String, dynamic>> acceptPendingCall(String callId);
  Future<Map<String, dynamic>> declinePendingCall(String callId);
  Future<Map<String, dynamic>> cancelPendingCall(String callId);

  Future<Map<String, dynamic>> getTurnCredentials();

  set accessToken(String? token);

  Future<void> close();
}
