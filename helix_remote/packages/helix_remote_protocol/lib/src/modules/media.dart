import 'package:helix_remote_protocol/src/json.dart';

/// How long the server keeps an object.
enum MediaKind implements WireEnum {
  /// Message attachments: deleted 30 days after upload (the server keeps no
  /// message history, so it has nothing to keep them for).
  attachment('attachment'),

  /// Avatars and group pictures: kept until the owner deletes them; small
  /// per-account quota.
  persistent('persistent'),

  /// Backup media: 90 days, refreshed on each backup, 1 GB quota.
  backup('backup');

  const MediaKind(this.wire);

  @override
  final String wire;
}

/// `POST /v1/media`. Objects are already encrypted (CRYPTO_V2.md §12); the
/// server gets a random id, a size and bytes, and never learns which message
/// uses an object.
final class CreateUploadRequest {
  const CreateUploadRequest({
    required this.size,
    this.kind = MediaKind.attachment,
  });

  final int size;
  final MediaKind kind;

  JsonMap toJson() => {'size': size, 'kind': kind.wire};

  factory CreateUploadRequest.fromJson(JsonReader json) => CreateUploadRequest(
    size: json.integer('size'),
    kind: json.enumValue('kind', MediaKind.values),
  );
}

/// Where and how to upload. With local storage [url] is this server's
/// `PUT /v1/media/{id}/content` (resumable with `Upload-Offset`); with S3 it
/// is a presigned URL and [headers] must be sent as given.
final class UploadTarget {
  const UploadTarget({
    required this.mediaId,
    required this.url,
    required this.expiresAt,
    this.method = 'PUT',
    this.headers = const {},
    this.resumable = true,
  });

  final String mediaId;
  final String url;
  final String method;
  final Map<String, String> headers;
  final DateTime expiresAt;
  final bool resumable;

  JsonMap toJson() => {
    'media_id': mediaId,
    'url': url,
    'method': method,
    'headers': headers,
    'expires_at': toWireTime(expiresAt),
    'resumable': resumable,
  };

  factory UploadTarget.fromJson(JsonReader json) {
    final headers = json.optObject('headers');
    return UploadTarget(
      mediaId: json.nonEmpty('media_id'),
      url: json.nonEmpty('url'),
      method: json.optString('method') ?? 'PUT',
      headers: {
        if (headers != null)
          for (final key in headers.json.keys) key: headers.string(key),
      },
      expiresAt: json.time('expires_at'),
      resumable: json.flag('resumable', orElse: true),
    );
  }
}

/// Header names for resumable media transfer.
abstract final class MediaHeaders {
  /// On `HEAD`/`PUT` responses: bytes stored so far. On `PUT` requests: the
  /// offset this chunk starts at.
  static const uploadOffset = 'upload-offset';

  /// On `HEAD`: the object's declared size.
  static const uploadLength = 'upload-length';
}
