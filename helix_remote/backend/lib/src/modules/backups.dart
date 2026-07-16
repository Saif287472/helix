import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';

class BackupsModule {
  static const int maxBackupMediaObjectSize = 100 * 1024 * 1024;
  static const int maxBackupMediaQuota = 1024 * 1024 * 1024;

  final BackendDatabase db;
  final Directory mediaStorageDir;

  BackupsModule(this.db, {Directory? mediaStorageDir})
    : mediaStorageDir = mediaStorageDir ?? Directory('backup_media_storage') {
    if (!this.mediaStorageDir.existsSync()) {
      this.mediaStorageDir.createSync(recursive: true);
    }
  }

  Router get router {
    final router = Router();
    router.post('/', _uploadBackupHandler);
    router.get('/', _downloadBackupHandler);
    router.post('/media', _requestMediaUploadHandler);
    router.get('/media/status/<objectId>', _mediaUploadStatusHandler);
    router.put('/media/<objectId>', _uploadMediaObjectHandler);
    router.get('/media/<objectId>', _downloadMediaObjectHandler);
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

    final fileSize = int.tryParse(
      request.url.queryParameters['file_size'] ?? '',
    );
    final fileHash = request.url.queryParameters['sha256'];
    if (fileSize == null || fileHash == null) {
      return Response.badRequest(
        body: jsonEncode({
          'error':
              'Use POST /api/v1/backups/media with byte_size and sha256 metadata',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return _createMediaUploadResponse(
      accountId: auth['account_id'] as String,
      objectId: fileHash,
      byteSize: fileSize,
      sha256Hex: fileHash,
    );
  }

  Future<Response> _requestMediaUploadHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final byteSize = body['byte_size'] as int?;
      final sha256Hex = body['sha256'] as String?;
      final objectId = body['object_id'] as String? ?? sha256Hex;
      if (byteSize == null || sha256Hex == null || objectId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing backup media metadata'}),
        );
      }
      return _createMediaUploadResponse(
        accountId: auth['account_id'] as String,
        objectId: objectId,
        byteSize: byteSize,
        sha256Hex: sha256Hex,
      );
    } catch (_) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Response _createMediaUploadResponse({
    required String accountId,
    required String objectId,
    required int byteSize,
    required String sha256Hex,
  }) {
    if (!_isSafeObjectId(objectId) || !_isSha256Hex(sha256Hex)) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid backup media object id or hash'}),
      );
    }
    if (byteSize <= 0 || byteSize > maxBackupMediaObjectSize) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Backup media object size is not allowed'}),
      );
    }
    final currentUsage = _backupMediaUsage(accountId);
    if (currentUsage + byteSize > maxBackupMediaQuota) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Backup media quota exceeded'}),
      );
    }

    db.createBackupMediaObject(
      objectId: objectId,
      accountId: accountId,
      byteSize: byteSize,
      sha256: sha256Hex,
      retentionUntil: DateTime.now()
          .add(const Duration(days: 90))
          .millisecondsSinceEpoch,
    );
    return Response.ok(
      jsonEncode({
        'object_id': objectId,
        'upload_url': '/api/v1/backups/media/$objectId',
        'status_url': '/api/v1/backups/media/status/$objectId',
        'download_url': '/api/v1/backups/media/$objectId',
        'headers': {'Content-Type': 'application/octet-stream'},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _mediaUploadStatusHandler(
    Request request,
    String objectId,
  ) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final object = db.getBackupMediaObject(objectId);
    if (object == null || object['account_id'] != auth['account_id']) {
      return Response.notFound(jsonEncode({'error': 'Backup media not found'}));
    }
    return Response.ok(
      jsonEncode({
        'object_id': objectId,
        'uploaded_bytes': object['uploaded_bytes'],
        'byte_size': object['byte_size'],
        'status': object['status'],
        'sha256': object['sha256'],
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _uploadMediaObjectHandler(
    Request request,
    String objectId,
  ) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final object = db.getBackupMediaObject(objectId);
    if (object == null || object['account_id'] != auth['account_id']) {
      return Response.notFound(jsonEncode({'error': 'Backup media not found'}));
    }

    final offset =
        int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
    final file = _mediaFile(objectId);
    if (offset == 0 && file.existsSync()) {
      file.deleteSync();
    } else if (offset > 0) {
      if (!file.existsSync()) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Cannot resume missing object'}),
        );
      }
      final currentSize = file.lengthSync();
      if (offset > currentSize) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Resume offset is beyond object size'}),
        );
      }
      if (currentSize > offset) {
        final raf = file.openSync(mode: FileMode.writeOnlyAppend);
        raf.truncateSync(offset);
        raf.closeSync();
      }
    }

    final sink = file.openWrite(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    try {
      await sink.addStream(request.read());
      await sink.close();
      final uploadedBytes = file.lengthSync();
      final expectedSize = object['byte_size'] as int;
      if (uploadedBytes > expectedSize) {
        file.deleteSync();
        db.updateBackupMediaProgress(
          objectId: objectId,
          uploadedBytes: 0,
          status: 'FAILED',
        );
        return Response.badRequest(
          body: jsonEncode({'error': 'Uploaded object exceeds declared size'}),
        );
      }
      if (uploadedBytes < expectedSize) {
        db.updateBackupMediaProgress(
          objectId: objectId,
          uploadedBytes: uploadedBytes,
          status: 'UPLOADING',
        );
        return Response.ok(
          jsonEncode({
            'object_id': objectId,
            'uploaded_bytes': uploadedBytes,
            'status': 'UPLOADING',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final actualHash = sha256.convert(file.readAsBytesSync()).toString();
      if (actualHash != object['sha256']) {
        file.deleteSync();
        db.updateBackupMediaProgress(
          objectId: objectId,
          uploadedBytes: 0,
          status: 'FAILED',
        );
        return Response.badRequest(
          body: jsonEncode({'error': 'Backup media integrity check failed'}),
        );
      }
      db.updateBackupMediaProgress(
        objectId: objectId,
        uploadedBytes: uploadedBytes,
        status: 'COMPLETED',
      );
      return Response.ok(
        jsonEncode({
          'object_id': objectId,
          'uploaded_bytes': uploadedBytes,
          'status': 'COMPLETED',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (_) {
      await sink.close();
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _downloadMediaObjectHandler(
    Request request,
    String objectId,
  ) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final object = db.getBackupMediaObject(objectId);
    if (object == null ||
        object['account_id'] != auth['account_id'] ||
        object['status'] != 'COMPLETED') {
      return Response.notFound(jsonEncode({'error': 'Backup media not found'}));
    }
    final file = _mediaFile(objectId);
    if (!file.existsSync()) {
      return Response.notFound(jsonEncode({'error': 'Object missing on disk'}));
    }
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': file.lengthSync().toString(),
        'X-Content-SHA256': object['sha256'] as String,
      },
    );
  }

  int cleanupExpiredMedia() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = db.getExpiredBackupMediaObjectIds(now);
    for (final objectId in ids) {
      final file = _mediaFile(objectId);
      if (file.existsSync()) file.deleteSync();
      db.deleteBackupMediaObject(objectId);
    }
    return ids.length;
  }

  int _backupMediaUsage(String accountId) {
    return db.getBackupMediaUsage(accountId);
  }

  File _mediaFile(String objectId) => File('${mediaStorageDir.path}/$objectId');

  bool _isSafeObjectId(String objectId) =>
      RegExp(r'^[a-zA-Z0-9_-]{16,128}$').hasMatch(objectId);

  bool _isSha256Hex(String value) =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
}
