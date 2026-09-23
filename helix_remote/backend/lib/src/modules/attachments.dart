import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/server_log.dart';

class AttachmentsModule {
  /// Defaults when the deployment sets no override. Both are operator
  /// choices rather than protocol constants, which is why they are
  /// configurable at all: raising them used to require an app release,
  /// because the client hard-coded its own copy of the file limit.
  static const int defaultMaxFileSize = 100 * 1024 * 1024; // 100MB
  static const int defaultMaxQuota = 5 * 1024 * 1024 * 1024; // 5GB

  /// Maintenance sweep cadence and the ages it enforces.
  ///
  /// [cleanupOrphans] and [runLifecycleRules] have existed for a long time
  /// and are covered by tests, but nothing outside those tests ever called
  /// them - so in a running deployment neither had ever removed a single
  /// byte. Attachments accumulated on disk forever. Raising the per-file
  /// limit to 100 MB and the account quota to 5 GB made that the largest
  /// unbounded growth risk on the box, so the sweep is now actually
  /// scheduled.
  static const Duration defaultSweepInterval = Duration(hours: 1);

  /// An upload that was announced but never finished. A day is generous for
  /// a 100 MB file on a phone uplink while still bounding the debris left by
  /// clients that vanish mid-upload.
  static const Duration defaultOrphanStaleAfter = Duration(hours: 24);

  /// A completed attachment no message refers to any more. References are
  /// dropped when the referencing message is deleted
  /// ([cleanAttachmentReferences]), so this is the backstop for objects
  /// whose last reference went away.
  static const Duration defaultUnreferencedRetention = Duration(days: 30);

  final BackendDatabase db;
  final Directory storageDir;

  /// Largest single attachment, measured as **ciphertext** - which is what
  /// actually arrives here. The client checks the same number against the
  /// ciphertext size it is about to send, so the two agree; comparing a
  /// plaintext length here would be comparing different things.
  final int maxFileSize;

  /// Cumulative per-account ciphertext budget.
  final int maxQuota;

  /// How often [sweepOnce] runs once [startMaintenance] is called.
  final Duration sweepInterval;

  /// Age at which an unfinished upload is treated as abandoned.
  final Duration orphanStaleAfter;

  /// How long a completed but unreferenced attachment is kept.
  final Duration unreferencedRetention;

  Timer? _sweepTimer;

  AttachmentsModule(
    this.db, {
    Directory? storageDir,
    int? maxFileSize,
    int? maxQuota,
    Duration? sweepInterval,
    Duration? orphanStaleAfter,
    Duration? unreferencedRetention,
  }) : maxFileSize = maxFileSize ?? defaultMaxFileSize,
       maxQuota = maxQuota ?? defaultMaxQuota,
       sweepInterval = sweepInterval ?? defaultSweepInterval,
       orphanStaleAfter = orphanStaleAfter ?? defaultOrphanStaleAfter,
       unreferencedRetention =
           unreferencedRetention ?? defaultUnreferencedRetention,
       storageDir = storageDir ?? Directory('attachments_storage') {
    if (!this.storageDir.existsSync()) {
      this.storageDir.createSync(recursive: true);
    }
  }

  /// Starts the periodic storage sweep. Sweeps once immediately as well: a
  /// server restarted more often than [sweepInterval] would otherwise never
  /// reach the first tick, which is exactly the deployment that most needs
  /// the disk reclaimed.
  void startMaintenance() {
    _sweepTimer?.cancel();
    _sweepTimer = Timer.periodic(sweepInterval, (_) => sweepOnce());
    sweepOnce();
  }

  void stopMaintenance() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  /// Runs one storage sweep and returns what it removed. Never throws - a
  /// failed sweep must not take down the timer or the request that triggered
  /// it.
  Map<String, int> sweepOnce() {
    var orphans = 0;
    var expired = 0;
    try {
      orphans = cleanupOrphans(staleAfter: orphanStaleAfter);
      expired = runLifecycleRules(retainFor: unreferencedRetention);
    } catch (e) {
      logServerError('[Attachments] maintenance sweep error: $e');
    }
    if (orphans > 0 || expired > 0) {
      logServerInfo(
        '[Attachments] sweep removed $orphans abandoned upload(s) and '
        '$expired unreferenced attachment(s)',
      );
    }
    return {'orphans_removed': orphans, 'unreferenced_removed': expired};
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
      throw AppError.badRequest(
        'File size exceeds the maximum of ${_mb(maxFileSize)}MB',
      ).withDetails({'max_attachment_bytes': maxFileSize});
    }

    final accountId = auth['account_id'] as String;
    final currentUsage = db.getAccountStorageUsage(accountId);
    if (currentUsage + fileSize > maxQuota) {
      throw AppError.badRequest(
        'Upload exceeds the account storage quota of ${_mb(maxQuota)}MB',
        code: RemoteErrorCode.quotaExceeded,
      ).withDetails({
        'account_quota_bytes': maxQuota,
        'account_bytes_used': currentUsage,
      });
    }

    // Content-addressed: file_id is derived from file_hash
    final fileId = fileHash;

    final existing = db.getAttachment(fileId);
    if (existing != null && existing['status'] == 'COMPLETED') {
      // Content already exists and is complete: grant access and deduplicate
      db.grantAttachmentAccess(fileId: fileId, accountId: accountId);
      final uploadUrl = '/api/v1/attachments/upload/file/$fileId';
      return Response.ok(
        jsonEncode({
          'file_id': fileId,
          'upload_url': uploadUrl,
          'status': 'COMPLETED',
          'headers': {'Content-Type': 'application/octet-stream'},
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

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

  static int _mb(int bytes) => bytes ~/ (1024 * 1024);

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
      if (attachment['status'] == 'COMPLETED') {
        throw AppError.badRequest('Attachment is already completed');
      }
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
      final expectedSize = attachment['file_size'] as int;
      var bytesReceived = offset;

      await for (final chunk in request.read()) {
        bytesReceived += chunk.length;
        if (bytesReceived > expectedSize) {
          await sink.close();
          if (await file.exists()) await file.delete();
          db.updateAttachmentProgress(fileId, 0, 'FAILED');
          throw AppError.badRequest('Uploaded file size exceeds expected size');
        }
        sink.add(chunk);
      }
      await sink.close();

      final finalSize = await file.length();

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
