import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/bodies.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// Reference to an encrypted media object (CONTENT_V2.md §2,
/// CRYPTO_V2.md §12). Lives only inside encrypted content.
final class MediaPointer {
  const MediaPointer({
    required this.id,
    required this.key,
    required this.digest,
    required this.size,
    required this.mime,
    this.name,
    this.blurhash,
    this.thumbnail,
  });

  /// Server media id.
  final String id;

  /// 32-byte attachment key.
  final Uint8List key;

  /// SHA-256 of the ciphertext, checked after download.
  final Uint8List digest;

  /// The largest attachment a pointer may declare (the per-account
  /// attachment quota of the server, 4 GiB).
  static const maxSize = 4 * 1024 * 1024 * 1024;

  /// Plaintext size in bytes.
  final int size;
  final String mime;
  final String? name;
  final String? blurhash;
  final MediaPointer? thumbnail;

  JsonMap toJson() => compact({
    'id': id,
    'key': encodeBytes(key),
    'digest': encodeBytes(digest),
    'size': size,
    'mime': mime,
    'name': name,
    'blurhash': blurhash,
    'thumbnail': thumbnail?.toJson(),
  });

  factory MediaPointer.fromJson(JsonReader json, {bool allowThumbnail = true}) {
    final key = json.bytes('key');
    final digest = json.bytes('digest');
    if (key.length != 32 || digest.length != 32) {
      throw ProtocolFormatException('bad media key or digest', path: json.path);
    }
    return MediaPointer(
      id: json.nonEmpty('id'),
      key: key,
      digest: digest,
      size: json.intIn('size', 0, MediaPointer.maxSize),
      mime: json.nonEmpty('mime'),
      name: json.optString('name'),
      blurhash: json.optString('blurhash'),
      thumbnail: allowThumbnail && json.has('thumbnail')
          ? MediaPointer.fromJson(
              json.object('thumbnail'),
              allowThumbnail: false,
            )
          : null,
    );
  }
}

enum MediaItemKind implements WireEnum {
  image('image'),
  video('video'),
  document('document'),
  voiceNote('voice_note'),
  videoNote('video_note'),
  gif('gif'),

  /// A kind from a newer client; shown as a downloadable file.
  unknown('unknown');

  const MediaItemKind(this.wire);

  @override
  final String wire;
}

final class MediaItem {
  const MediaItem({
    required this.kind,
    required this.media,
    this.caption,
    this.durationMs,
    this.waveform,
    this.width,
    this.height,
  });

  final MediaItemKind kind;
  final MediaPointer media;
  final String? caption;
  final int? durationMs;

  /// Voice notes: one byte (0-255) per sample.
  final Uint8List? waveform;
  final int? width;
  final int? height;

  JsonMap toJson() => compact({
    'kind': kind.wire,
    'media': media.toJson(),
    'caption': caption,
    'duration_ms': durationMs,
    'waveform': waveform == null ? null : encodeBytes(waveform!),
    'width': width,
    'height': height,
  });

  factory MediaItem.fromJson(JsonReader json) => MediaItem(
    kind: json.enumValue(
      'kind',
      MediaItemKind.values,
      orElse: MediaItemKind.unknown,
    ),
    media: MediaPointer.fromJson(json.object('media')),
    caption: json.optString('caption'),
    durationMs: json.optIntIn(
      'duration_ms',
      0,
      ContentLimits.maxMediaDurationMs,
    ),
    waveform: _waveform(json),
    width: json.optIntIn('width', 0, ContentLimits.maxMediaDimension),
    height: json.optIntIn('height', 0, ContentLimits.maxMediaDimension),
  );
}

Uint8List? _waveform(JsonReader json) {
  final bytes = json.optBytes('waveform');
  if (bytes != null && bytes.length > ContentLimits.maxWaveformSamples) {
    throw ProtocolFormatException('waveform too long', path: json.path);
  }
  return bytes;
}
