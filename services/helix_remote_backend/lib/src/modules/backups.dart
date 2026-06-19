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

      if (backupData == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing backup_data'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.setBackup(accountId, backupData);
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
        body: jsonEncode({'error': e.toString()}),
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
          'backup_data': backup['backup_data'],
          'created_at': backup['created_at'],
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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
