import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
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

  Router get router {
    final router = Router();
    router.post('/upload', _requestUploadHandler);
    router.get('/upload/status/<fileId>', _uploadStatusHandler);
    router.put('/upload/file/<fileId>', _uploadFileHandler);
    router.get('/download/<fileId>', _requestDownloadHandler);
    router.get('/download/file/<fileId>', _downloadFileHandler);
    router.post('/register-reference', _registerReferenceHandler);
    return router;
  }

  Future<Response> _requestUploadHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final fileSize = body['file_size'] as int?;
      final fileHash = body['file_hash'] as String?;

      if (fileSize == null || fileHash == null || fileHash.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing file_size or file_hash'}),
        );
      }

      if (fileSize > maxFileSize) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'File size exceeds maximum limit of 10MB',
          }),
        );
      }

      final accountId = auth['account_id'] as String;
      final currentUsage = db.getAccountStorageUsage(accountId);
      if (currentUsage + fileSize > maxQuota) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Upload exceeds account storage quota of 50MB',
          }),
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
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _registerReferenceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final fileId = body['file_id'] as String?;
      final messageId = body['message_id'] as String?;

      if (fileId == null ||
          messageId == null ||
          fileId.isEmpty ||
          messageId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing file_id or message_id'}),
        );
      }

      db.registerAttachmentReference(fileId, messageId);
      return Response.ok(jsonEncode({'message': 'Reference registered'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  void cleanAttachmentReferences(String messageId) {
    try {
      final fileIds = db.getReferencedFileIds(messageId);
      db.deleteAttachmentReferences(messageId);

      for (final fileId in fileIds) {
        final count = db.getAttachmentReferenceCount(fileId);
        if (count == 0) {
          final file = File('${storageDir.path}/$fileId');
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
    final threshold =
        DateTime.now().subtract(staleAfter).millisecondsSinceEpoch;
    final orphanIds = db.getOrphanAttachmentIds(threshold);
    var count = 0;
    for (final fileId in orphanIds) {
      final file = File('${storageDir.path}/$fileId');
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
    final threshold =
        DateTime.now().subtract(retainFor).millisecondsSinceEpoch;
    final candidateIds = db.getAttachmentsOlderThan(threshold);
    var count = 0;
    for (final fileId in candidateIds) {
      if (db.getAttachmentReferenceCount(fileId) == 0) {
        final file = File('${storageDir.path}/$fileId');
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
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      return Response.notFound(jsonEncode({'error': 'Attachment not found'}));
    }

    final file = File('${storageDir.path}/$fileId');
    int uploadedBytes = 0;
    if (file.existsSync()) {
      uploadedBytes = file.lengthSync();
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
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final attachment = db.getAttachment(fileId);
    if (attachment == null) {
      return Response.notFound(jsonEncode({'error': 'Attachment not found'}));
    }

    final queryParams = request.url.queryParameters;
    final offsetStr = queryParams['offset'];
    final offset = offsetStr != null ? int.tryParse(offsetStr) ?? 0 : 0;

    final file = File('${storageDir.path}/$fileId');
    IOSink sink;

    if (offset == 0) {
      if (file.existsSync()) {
        file.deleteSync();
      }
      sink = file.openWrite(mode: FileMode.write);
    } else {
      if (!file.existsSync()) {
        return Response.badRequest(
          body: jsonEncode({
            'error':
                'File does not exist on server, cannot resume at offset $offset',
          }),
        );
      }
      final currentSize = file.lengthSync();
      if (offset > currentSize) {
        return Response.badRequest(
          body: jsonEncode({
            'error':
                'Offset $offset is greater than server file size $currentSize',
          }),
        );
      }
      // Truncate to offset to support clean resume
      if (currentSize > offset) {
        final raf = file.openSync(mode: FileMode.writeOnlyAppend);
        raf.truncateSync(offset);
        raf.closeSync();
      }
      sink = file.openWrite(mode: FileMode.append);
    }

    try {
      await sink.addStream(request.read());
      await sink.close();

      final finalSize = file.lengthSync();
      final expectedSize = attachment['file_size'] as int;

      if (finalSize > expectedSize) {
        file.deleteSync();
        db.updateAttachmentProgress(fileId, 0, 'FAILED');
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Uploaded file size exceeds expected size',
          }),
        );
      }

      if (finalSize == expectedSize) {
        // Verify hash
        final bytes = file.readAsBytesSync();
        final actualHash = sha256.convert(bytes).toString();
        final expectedHash = attachment['file_hash'] as String;

        if (actualHash != expectedHash) {
          file.deleteSync();
          db.updateAttachmentProgress(fileId, 0, 'FAILED');
          return Response.badRequest(
            body: jsonEncode({
              'error': 'Integrity check failed: hash mismatch',
            }),
          );
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
    } catch (e) {
      await sink.close();
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _requestDownloadHandler(
    Request request,
    String fileId,
  ) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final attachment = db.getAttachment(fileId);
    if (attachment == null || attachment['status'] != 'COMPLETED') {
      return Response.notFound(
        jsonEncode({'error': 'Attachment not found or incomplete'}),
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
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final file = File('${storageDir.path}/$fileId');
    if (!file.existsSync()) {
      return Response.notFound(jsonEncode({'error': 'File not found on disk'}));
    }

    final totalLength = file.lengthSync();
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeValue = rangeHeader.substring(6);
      final parts = rangeValue.split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (totalLength - 1)
          : (totalLength - 1);

      if (start >= totalLength || end >= totalLength || start > end) {
        return Response(
          416,
          body: jsonEncode({'error': 'Requested Range Not Satisfiable'}),
          headers: {
            'Content-Range': 'bytes */$totalLength',
            'Content-Type': 'application/json',
          },
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
