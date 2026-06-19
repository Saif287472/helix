import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';

class BackupsModule {
  final BackendDatabase db;

  BackupsModule(this.db);

  Router get router {
    final router = Router();
    router.post('/', _uploadBackupHandler);
    router.get('/', _downloadBackupHandler);
    router.get('/attachments/upload-url', _getAttachmentUploadUrlHandler);
    return router;
  }

  Future<Response> _uploadBackupHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final backupData = body['backup_data'] as String?;
      final backupId = body['backup_id'] as String?;
      final version = body['version'] as int?;
      final kdf = body['kdf'] as String?;
      final salt = body['salt'] as String?;
      final backupKeyHint = body['backup_key_hint'] as String? ?? '';
      final deletionWatermark = body['deletion_watermark'] as int? ?? 0;

      if (body.containsKey('backup_key') ||
          body.containsKey('passphrase') ||
          body.containsKey('recovery_phrase')) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Backup keys must never be uploaded'}),
        );
      }

      if (backupData == null ||
          backupId == null ||
          version == null ||
          kdf == null ||
          salt == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing backup envelope metadata'}),
        );
      }
      if (version < 1) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Unsupported backup version'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.setBackup(
        accountId,
        backupData,
        backupId: backupId,
        version: version,
        kdf: kdf,
        salt: salt,
        backupKeyHint: backupKeyHint,
        deletionWatermark: deletionWatermark,
      );
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'BACKUP_UPLOADED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(jsonEncode({'message': 'Backup stored successfully'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _downloadBackupHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final accountId = auth['account_id'] as String;
      final backup = db.getBackup(accountId);

      if (backup == null) {
        return Response.notFound(
          jsonEncode({'error': 'No backup found for this account'}),
        );
      }

      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'BACKUP_DOWNLOADED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'backup_id': backup['backup_id'],
          'version': backup['version'],
          'kdf': backup['kdf'],
          'salt': backup['salt'],
          'backup_key_hint': backup['backup_key_hint'],
          'backup_data': backup['backup_data'],
          'created_at': backup['created_at'],
          'deletion_watermark': backup['deletion_watermark'],
          'requires_reupload': backup['requires_reupload'] == 1,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _getAttachmentUploadUrlHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final filename =
        request.url.queryParameters['filename'] ?? 'attachment.bin';
    final mockUrl =
        'https://mock-s3.helix.remote/attachments/${DateTime.now().millisecondsSinceEpoch}_$filename';

    return Response.ok(
      jsonEncode({
        'upload_url': mockUrl,
        'download_url': mockUrl,
        'headers': {
          'Content-Type': 'application/octet-stream',
          'x-amz-acl': 'private',
        },
      }),
    );
  }
}
