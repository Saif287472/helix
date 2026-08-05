import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';

class AttachmentsModule {
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const int maxQuota = 50 * 1024 * 1024; // 50MB

  final BackendDatabase db;
  final Directory storageDir;

  AttachmentsModule(this.db, {Directory? storageDir})
    : storageDir = storageDir ?? Directory('attachments_storage') {
    if (!this.storageDir.existsSync()) {
      this.storageDir.createSync(recursive: true);
    }
  }

  Handler get router {
    final router = Router();
    router.post('/upload', _requestUploadHandler);
    router.get('/upload/status/<fileId>', _uploadStatusHandler);
    router.put('/upload/file/<fileId>', _uploadFileHandler);
    router.get('/download/<fileId>', _requestDownloadHandler);
    router.get('/download/file/<fileId>', _downloadFileHandler);
    router.post('/register-reference', _registerReferenceHandler);
    return withAppErrorHandling(router.call);
  }

  Future<Response> _requestUploadHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fileSize = body['file_size'] as int?;
    final fileHash = body['file_hash'] as String?;

    if (fileSize == null || fileHash == null || fileHash.isEmpty) {
      throw AppError.badRequest('Missing file_size or file_hash');
    }

    if (fileSize > maxFileSize) {
      throw AppError.badRequest('File size exceeds maximum limit of 10MB');
    }

    final accountId = auth['account_id'] as String;
    final currentUsage = db.getAccountStorageUsage(accountId);
    if (currentUsage + fileSize > maxQuota) {
      throw AppError.badRequest(
        'Upload exceeds account storage quota of 50MB',
        code: RemoteErrorCode.quotaExceeded,
      );
    }

    // Content-addressed: file_id is derived from file_hash
    final fileId = fileHash;

    db.createAttachment(
      fileId: fileId,
      accountId: accountId,
      fileSize: fileSize,
      fileHash: fileHash,
    );

    final uploadUrl = '/api/v1/attachments/upload/file/$fileId';
    return Response.ok(
      jsonEncode({
        'file_id': fileId,
        'upload_url': uploadUrl,
        'headers': {'Content-Type': 'application/octet-stream'},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _registerReferenceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final accountId = auth['account_id'] as String;

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fileId = body['file_id'] as String?;
    final messageId = body['message_id'] as String?;

    if (fileId == null ||
        messageId == null ||
        fileId.isEmpty ||
        messageId.isEmpty) {
      throw AppError.badRequest('Missing file_id or message_id');
    }

    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      throw AppError.notFound('Attachment not found');
    }
    if (attachment['account_id'] != accountId) {
      throw AppError.forbidden(
        'Access denied: attachment belongs to another account',
      );
    }

    final message = db.getMessage(messageId);
    if (message == null) {
      throw AppError.badRequest('Referenced message not found');
    }
    if (message['sender_account_id'] != accountId) {
      throw AppError.forbidden(
        'Only the attachment uploader can register reference grants',
      );
    }

    final conversationId = message['conversation_id'] as String;
    db.registerAttachmentReference(fileId, messageId);
    for (final memberId in db.getConversationMembers(conversationId)) {
      db.grantAttachmentAccess(fileId: fileId, accountId: memberId);
    }
    return Response.ok(jsonEncode({'message': 'Reference registered'}));
  }

  void cleanAttachmentReferences(String messageId) {
    try {
      final fileIds = db.getReferencedFileIds(messageId);
      db.deleteAttachmentReferences(messageId);

      for (final fileId in fileIds) {
        final count = db.getAttachmentReferenceCount(fileId);
        if (count == 0) {
          final file = File('${storageDir.path}/${p.basename(fileId)}');
          if (file.existsSync()) {
            file.deleteSync();
          }
          db.deleteAttachmentRow(fileId);
        }
      }
    } catch (e) {
      // Ignore or log error gracefully
    }
  }

  /// Deletes uploads that never completed and are older than [staleAfter].
  /// Returns the count of orphans removed.
  int cleanupOrphans({required Duration staleAfter}) {
    final threshold = DateTime.now()
        .subtract(staleAfter)
        .millisecondsSinceEpoch;
    final orphanIds = db.getOrphanAttachmentIds(threshold);
    var count = 0;
    for (final fileId in orphanIds) {
      final file = File('${storageDir.path}/${p.basename(fileId)}');
      if (file.existsSync()) {
        file.deleteSync();
      }
      db.deleteAttachmentRow(fileId);
      count++;
    }
    return count;
  }

  /// Expires completed attachments that have no message references and are
  /// older than [retainFor]. Returns the count of objects removed.
  int runLifecycleRules({required Duration retainFor}) {
    final threshold = DateTime.now().subtract(retainFor).millisecondsSinceEpoch;
    final candidateIds = db.getAttachmentsOlderThan(threshold);
    var count = 0;
    for (final fileId in candidateIds) {
      if (db.getAttachmentReferenceCount(fileId) == 0) {
        final file = File('${storageDir.path}/${p.basename(fileId)}');
        if (file.existsSync()) {
          file.deleteSync();
        }
        db.deleteAttachmentRow(fileId);
        count++;
      }
    }
    return count;
  }

  Future<Response> _uploadStatusHandler(Request request, String fileId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      throw AppError.notFound('Attachment not found');
    }
    final accountId = auth['account_id'] as String;
    if (attachment['account_id'] != accountId) {
      throw AppError.forbidden(
        'Access denied: attachment belongs to another account',
      );
    }

    final file = File('${storageDir.path}/${p.basename(fileId)}');
    int uploadedBytes = 0;
    if (await file.exists()) {
      uploadedBytes = await file.length();
    }

    // Sync database state if mismatch
    if (attachment['uploaded_bytes'] != uploadedBytes) {
      db.updateAttachmentProgress(
        fileId,
        uploadedBytes,
        uploadedBytes == attachment['file_size'] ? 'COMPLETED' : 'UPLOADING',
      );
    }

    return Response.ok(
      jsonEncode({
        'file_id': fileId,
        'uploaded_bytes': uploadedBytes,
        'file_size': attachment['file_size'],
        'status': attachment['status'],
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _uploadFileHandler(Request request, String fileId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      throw AppError.notFound('Attachment not found');
    }
    final accountId = auth['account_id'] as String;
    if (attachment['account_id'] != accountId) {
      throw AppError.forbidden('Access denied');
    }

    final queryParams = request.url.queryParameters;
    final offsetStr = queryParams['offset'];
    final offset = offsetStr != null ? int.tryParse(offsetStr) ?? 0 : 0;

    final file = File('${storageDir.path}/${p.basename(fileId)}');
    IOSink sink;

    if (offset == 0) {
      if (await file.exists()) {
        await file.delete();
      }
      sink = file.openWrite(mode: FileMode.write);
    } else {
      if (!await file.exists()) {
        throw AppError.badRequest(
          'File does not exist on server, cannot resume at offset $offset',
        );
      }
      final currentSize = await file.length();
      if (offset > currentSize) {
        throw AppError.badRequest(
          'Offset $offset is greater than server file size $currentSize',
        );
      }
      // Truncate to offset to support clean resume
      if (currentSize > offset) {
        final raf = await file.open(mode: FileMode.writeOnlyAppend);
        await raf.truncate(offset);
        await raf.close();
      }
      sink = file.openWrite(mode: FileMode.append);
    }

    try {
      await sink.addStream(request.read());
      await sink.close();

      final finalSize = await file.length();
      final expectedSize = attachment['file_size'] as int;

      if (finalSize > expectedSize) {
        await file.delete();
        db.updateAttachmentProgress(fileId, 0, 'FAILED');
        throw AppError.badRequest('Uploaded file size exceeds expected size');
      }

      if (finalSize == expectedSize) {
        // Verify hash
        final actualHash = (await sha256.bind(file.openRead()).first)
            .toString();
        final expectedHash = attachment['file_hash'] as String;

        if (actualHash != expectedHash) {
          await file.delete();
          db.updateAttachmentProgress(fileId, 0, 'FAILED');
          throw AppError.badRequest('Integrity check failed: hash mismatch');
        }

        db.updateAttachmentProgress(fileId, finalSize, 'COMPLETED');
        return Response.ok(
          jsonEncode({
            'file_id': fileId,
            'uploaded_bytes': finalSize,
            'status': 'COMPLETED',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        db.updateAttachmentProgress(fileId, finalSize, 'UPLOADING');
        return Response.ok(
          jsonEncode({
            'file_id': fileId,
            'uploaded_bytes': finalSize,
            'status': 'UPLOADING',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } on AppError {
      // Thrown only after `sink.close()` above has already run - closing it
      // again here would be a double close, and the error is already in the
      // shape the middleware wants.
      rethrow;
    } catch (e) {
      await sink.close();
      throw AppError.internal();
    }
  }

  Future<Response> _requestDownloadHandler(
    Request request,
    String fileId,
  ) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final accountId = auth['account_id'] as String;

    final attachment = db.getAttachment(fileId);
    if (attachment == null || attachment['status'] != 'COMPLETED') {
      throw AppError.notFound('Attachment not found or incomplete');
    }
    if (!db.canAccessAttachment(fileId, accountId)) {
      throw AppError.forbidden(
        'Access denied: attachment is not shared with this account',
      );
    }

    final downloadUrl = '/api/v1/attachments/download/file/$fileId';
    return Response.ok(
      jsonEncode({'download_url': downloadUrl}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _downloadFileHandler(Request request, String fileId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final accountId = auth['account_id'] as String;

    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      throw AppError.notFound('Attachment not found');
    }
    if (!db.canAccessAttachment(fileId, accountId)) {
      throw AppError.forbidden(
        'Access denied: attachment is not shared with this account',
      );
    }

    final file = File('${storageDir.path}/${p.basename(fileId)}');
    if (!await file.exists()) {
      throw AppError.notFound('File not found on disk');
    }

    final totalLength = await file.length();
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeValue = rangeHeader.substring(6);
      final parts = rangeValue.split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (totalLength - 1)
          : (totalLength - 1);

      if (start >= totalLength || end >= totalLength || start > end) {
        throw AppError(
          'Requested Range Not Satisfiable',
          statusCode: 416,
          code: RemoteErrorCode.badRequest,
          headers: {'Content-Range': 'bytes */$totalLength'},
        );
      }

      final chunkLength = end - start + 1;
      final stream = file.openRead(start, end + 1);

      return Response(
        206,
        body: stream,
        headers: {
          'Content-Range': 'bytes $start-$end/$totalLength',
          'Content-Length': chunkLength.toString(),
          'Content-Type': 'application/octet-stream',
          'Accept-Ranges': 'bytes',
        },
      );
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Length': totalLength.toString(),
        'Content-Type': 'application/octet-stream',
        'Accept-Ranges': 'bytes',
      },
    );
  }
}
