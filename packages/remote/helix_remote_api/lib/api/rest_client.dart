import 'package:helix_remote_domain/models.dart';

abstract class HelixRemoteRestClient {
  Future<RemoteAccount> registerAccount({
    required String username,
    required String identityPublicKey,
  });

  Future<Map<String, dynamic>> loginDevice({
    required String username,
    required String devicePublicKey,
    required String deviceName,
    required String signature,
  });

  Future<Map<String, dynamic>> refreshToken({
    required String refreshToken,
  });

  Future<List<RemoteDevice>> listDevices();

  Future<void> revokeDevice(int deviceId);

  Future<void> uploadPreKeys({
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  });

  Future<Map<String, dynamic>> getPreKeyBundle({
    required String accountId,
    required int deviceId,
  });

  Future<Map<String, dynamic>> sendContactRequest({
    required String targetUsername,
  });

  Future<void> acceptContactRequest(String requestId);

  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  });

  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId);

  Future<void> requestAccountDeletion({
    required String confirmationPhrase,
  });
}
