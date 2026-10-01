import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Where encrypted media and backup blobs live (ADR-025). Keys are
/// server-chosen (`<kind>/<uuid>`), never client paths.
abstract interface class ObjectStorage {
  /// Presigned URLs: clients transfer directly to the store (S3). When
  /// false, clients go through `PUT/GET /v1/media/{id}/content` and the
  /// server streams with [append] and [read].
  bool get supportsPresign;

  /// Stored size in bytes, or null if the object does not exist.
  Future<int?> size(String key);

  /// Appends [data] at [offset], which must equal the current size (or 0 for
  /// a new object). Stops with [ObjectTooLarge] beyond [maxSize]. Returns the
  /// new size.
  Future<int> append(
    String key,
    Stream<List<int>> data, {
    required int offset,
    required int maxSize,
  });

  /// Reads bytes `[start, endInclusive]` (whole object by default).
  Stream<List<int>> read(String key, {int start = 0, int? endInclusive});

  Future<void> delete(String key);

  /// A presigned PUT for exactly [contentLength] bytes: the length is a
  /// signed header, so the store refuses any other size.
  Uri presignPut(String key, Duration ttl, {required int contentLength});

  Uri presignGet(String key, Duration ttl);

  Future<bool> ping();
}

final class ObjectTooLarge implements Exception {
  const ObjectTooLarge();
}

final class OffsetMismatch implements Exception {
  const OffsetMismatch(this.actual);

  final int actual;
}

final RegExp _key = RegExp(r'^[a-z0-9_-]+(/[a-z0-9_-]+)*$');

void _checkKey(String key) {
  if (!_key.hasMatch(key) || key.length > 200) {
    throw ArgumentError.value(key, 'key', 'is not a valid object key');
  }
}

/// Files under one directory (single host, and dev). The key grammar has no
/// `.` segments, and the resolved path is checked to stay inside [root].
final class LocalObjectStorage implements ObjectStorage {
  LocalObjectStorage(String root) : root = p.normalize(p.absolute(root)) {
    Directory(this.root).createSync(recursive: true);
  }

  final String root;

  File _file(String key) {
    _checkKey(key);
    final path = p.normalize(p.join(root, key));
    if (!p.isWithin(root, path)) {
      throw ArgumentError('key escapes the storage root');
    }
    return File(path);
  }

  @override
  bool get supportsPresign => false;

  @override
  Future<int?> size(String key) async {
    final file = _file(key);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<int> append(
    String key,
    Stream<List<int>> data, {
    required int offset,
    required int maxSize,
  }) async {
    final file = _file(key);
    final current = await file.exists() ? await file.length() : 0;
    if (current != offset) throw OffsetMismatch(current);
    await file.parent.create(recursive: true);
    final sink = await file.open(mode: FileMode.append);
    var written = current;
    try {
      await for (final chunk in data) {
        if (written + chunk.length > maxSize) throw const ObjectTooLarge();
        await sink.writeFrom(chunk);
        written += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return written;
  }

  @override
  Stream<List<int>> read(String key, {int start = 0, int? endInclusive}) =>
      _file(
        key,
      ).openRead(start, endInclusive == null ? null : endInclusive + 1);

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Uri presignPut(String key, Duration ttl, {required int contentLength}) =>
      throw UnsupportedError('local storage does not presign');

  @override
  Uri presignGet(String key, Duration ttl) =>
      throw UnsupportedError('local storage does not presign');

  @override
  Future<bool> ping() async => Directory(root).exists();
}

/// Any S3-compatible store, signed with SigV4 (`aws_signature_v4`). Clients
/// upload and download with presigned URLs; the server only signs, checks
/// sizes and deletes.
final class S3ObjectStorage implements ObjectStorage {
  S3ObjectStorage(this.config, {http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? (() => DateTime.now().toUtc()),
      _signer = AWSSigV4Signer(
        credentialsProvider: AWSCredentialsProvider(
          AWSCredentials(config.accessKeyId, config.secretAccessKey),
        ),
      );

  final S3Config config;
  final http.Client _client;
  final DateTime Function() _now;
  final AWSSigV4Signer _signer;

  static final _service = S3ServiceConfiguration(signPayload: false);

  AWSCredentialScope _scope() => AWSCredentialScope(
    region: config.region,
    service: AWSService.s3,
    dateTime: AWSDateTime(_now()),
  );

  Uri _objectUri(String key) {
    _checkKey(key);
    final base = config.endpoint;
    return config.pathStyle
        ? base.replace(path: '/${config.bucket}/$key')
        : base.replace(host: '${config.bucket}.${base.host}', path: '/$key');
  }

  Uri _bucketUri() => config.pathStyle
      ? config.endpoint.replace(path: '/${config.bucket}')
      : config.endpoint.replace(
          host: '${config.bucket}.${config.endpoint.host}',
          path: '/',
        );

  Uri _presign(
    AWSHttpMethod method,
    Uri uri,
    Duration ttl, {
    Map<String, String> headers = const {},
  }) => _signer.presignSync(
    AWSHttpRequest(method: method, uri: uri, headers: headers),
    credentialScope: _scope(),
    serviceConfiguration: _service,
    expiresIn: ttl,
  );

  @override
  bool get supportsPresign => true;

  @override
  Uri presignPut(String key, Duration ttl, {required int contentLength}) {
    if (contentLength < 0) throw ArgumentError.value(contentLength);
    return _presign(
      AWSHttpMethod.put,
      _objectUri(key),
      ttl,
      headers: {'content-length': '$contentLength'},
    );
  }

  @override
  Uri presignGet(String key, Duration ttl) =>
      _presign(AWSHttpMethod.get, _objectUri(key), ttl);

  Future<http.Response> _signed(AWSHttpMethod method, Uri uri) async {
    final signed = _signer.signSync(
      AWSHttpRequest(method: method, uri: uri),
      credentialScope: _scope(),
      serviceConfiguration: _service,
    );
    final request = http.Request(method.value, signed.uri)
      ..headers.addAll(signed.headers);
    return http.Response.fromStream(await _client.send(request));
  }

  @override
  Future<int?> size(String key) async {
    final response = await _signed(AWSHttpMethod.head, _objectUri(key));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw HttpException('S3 HEAD failed (${response.statusCode})');
    }
    return int.tryParse(response.headers['content-length'] ?? '');
  }

  @override
  Future<int> append(
    String key,
    Stream<List<int>> data, {
    required int offset,
    required int maxSize,
  }) => throw UnsupportedError('S3 uploads go directly to presigned URLs');

  @override
  Stream<List<int>> read(
    String key, {
    int start = 0,
    int? endInclusive,
  }) async* {
    final response = await _signed(AWSHttpMethod.get, _objectUri(key));
    if (response.statusCode != 200) {
      throw HttpException('S3 GET failed (${response.statusCode})');
    }
    final bytes = response.bodyBytes;
    final end = endInclusive == null ? bytes.length : endInclusive + 1;
    yield Uint8List.sublistView(bytes, start, end);
  }

  @override
  Future<void> delete(String key) async {
    final response = await _signed(AWSHttpMethod.delete, _objectUri(key));
    if (response.statusCode != 204 &&
        response.statusCode != 200 &&
        response.statusCode != 404) {
      throw HttpException('S3 DELETE failed (${response.statusCode})');
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final response = await _signed(AWSHttpMethod.head, _bucketUri());
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }
}
