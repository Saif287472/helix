import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_api/src/v2/transport/retry.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Bytes stored so far for an upload.
final class UploadProgress {
  const UploadProgress({required this.offset, this.length});

  final int offset;

  /// The object's declared size, when the server said.
  final int? length;

  bool get complete => length != null && offset >= length!;

  static UploadProgress _of(ApiResponse r) => UploadProgress(
    offset: int.tryParse(r.headers[MediaHeaders.uploadOffset] ?? '') ?? 0,
    length: int.tryParse(r.headers[MediaHeaders.uploadLength] ?? ''),
  );
}

/// A downloaded object, or the requested range of it.
final class MediaDownload {
  const MediaDownload({required this.bytes, required this.partial, this.size});

  final Uint8List bytes;

  /// Only the requested range was returned (206).
  final bool partial;

  /// The whole object's size, from `content-range` or the full body.
  final int? size;
}

/// The `media` module. Objects are already encrypted by the engine
/// (CRYPTO_V2.md §12); the server sees a random id and bytes.
///
/// [upload] and [download] are the flows the engine's transfer queue uses:
/// resumable uploads to this server or a single presigned `PUT`, and ranged
/// downloads that follow the server's redirect to a presigned `GET` without
/// sending the device token there.
final class MediaClient {
  const MediaClient(this._t);

  final HelixTransport _t;

  /// Reserves an object and says where to upload it.
  Future<UploadTarget> createUpload(CreateUploadRequest request) => _t.call(
    Routes.createUpload,
    UploadTarget.fromJson,
    json: request.toJson(),
  );

  /// Stores [bytes] at [offset] (local storage only). A wrong offset throws
  /// `ApiException` `conflict` whose `details.upload_offset` is the stored
  /// offset.
  Future<UploadProgress> uploadContent(
    String mediaId,
    List<int> bytes, {
    int offset = 0,
    CancellationToken? cancel,
  }) async => UploadProgress._of(
    await _t.send(
      Routes.uploadContent,
      params: {'media_id': mediaId},
      bytes: bytes,
      headers: {MediaHeaders.uploadOffset: '$offset'},
      cancel: cancel,
    ),
  );

  /// How much of an upload the server has (`HEAD`).
  Future<UploadProgress> uploadStatus(String mediaId) async =>
      UploadProgress._of(
        await _t.send(Routes.uploadStatus, params: {'media_id': mediaId}),
      );

  /// Downloads the object, or bytes [start] to [end] inclusive. A redirect to
  /// object storage is followed without the bearer token.
  Future<MediaDownload> download(
    String mediaId, {
    int? start,
    int? end,
    CancellationToken? cancel,
  }) async {
    final range = start == null && end == null
        ? const <String, String>{}
        : {'range': 'bytes=${start ?? 0}-${end ?? ''}'};
    var response = await _t.send(
      Routes.downloadContent,
      params: {'media_id': mediaId},
      headers: range,
      accept: const {301, 302, 303, 307, 308},
      followRedirects: false,
      cancel: cancel,
    );
    if (response.status >= 300 && response.status < 400) {
      final location = response.headers['location'];
      if (location == null) {
        throw MalformedResponseException(
          path: 'location',
          requestId: response.requestId,
        );
      }
      response = await _t.external(
        'GET',
        _t.baseUrl.resolve(location),
        headers: range,
        cancel: cancel,
      );
    }
    return MediaDownload(
      bytes: response.body,
      partial: response.status == 206,
      size: _size(response),
    );
  }

  static int? _size(ApiResponse r) {
    final range = r.headers['content-range'];
    if (range != null) return int.tryParse(range.split('/').last);
    return r.status == 200 ? r.body.length : null;
  }

  /// Owner only.
  Future<void> delete(String mediaId) =>
      _t.empty(Routes.deleteMedia, params: {'media_id': mediaId});

  /// Uploads [bytes] to [target]: one presigned `PUT` (absolute URL, exactly
  /// `size` bytes with the target's headers), or chunks to this server that
  /// resume from the stored offset after a conflict or a dropped connection.
  /// [resume] first asks the server how much it already has.
  Future<void> upload(
    UploadTarget target,
    List<int> bytes, {
    int chunkSize = 1024 * 1024,
    bool resume = false,
    int maxResumes = 5,
    CancellationToken? cancel,
    void Function(int sent, int total)? onProgress,
  }) async {
    final url = Uri.parse(target.url);
    if (url.hasScheme) {
      await _t.external(
        target.method,
        url,
        headers: target.headers,
        bytes: bytes,
        cancel: cancel,
      );
      onProgress?.call(bytes.length, bytes.length);
      return;
    }
    final all = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    var offset = resume ? (await uploadStatus(target.mediaId)).offset : 0;
    var resumes = 0;
    while (offset < bytes.length) {
      final end = min(offset + chunkSize, bytes.length);
      try {
        final progress = await uploadContent(
          target.mediaId,
          Uint8List.sublistView(all, offset, end),
          offset: offset,
          cancel: cancel,
        );
        offset = progress.offset;
        resumes = 0;
        onProgress?.call(offset, bytes.length);
      } on ApiException catch (e) {
        final stored = e.details?['upload_offset'];
        if (e.code != ErrorCode.conflict || stored is! int) rethrow;
        if (++resumes > maxResumes) rethrow;
        offset = stored;
      } on NetworkException {
        if (++resumes > maxResumes) rethrow;
        offset = (await uploadStatus(target.mediaId)).offset;
      }
    }
  }
}
