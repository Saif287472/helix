import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
  /// new size as the store measures it, not as the caller counted.
  ///
  /// Calls for one key are serialized: the writer behind another re-checks the
  /// length once it is its turn and gets [OffsetMismatch] rather than writing
  /// into the middle of the upload ahead of it.
  Future<int> append(
    String key,
    Stream<List<int>> data, {
    required int offset,
    required int maxSize,
  });

  /// Reads bytes `[start, endInclusive]` (whole object by default) as a
  /// stream, asking the store for exactly that range. [ObjectMissing] when the
  /// object is gone, [ObjectShort] when it is shorter than the range.
  Stream<List<int>> read(String key, {int start = 0, int? endInclusive});

  /// Deletes [key]; nothing happens if it does not exist.
  Future<void> delete(String key);

  /// Every object under the key prefix [prefix] (`attachment/`), with the
  /// time it last changed. For the media module's orphan sweep; order is
  /// not defined.
  Stream<StoredObject> list(String prefix);

  /// A presigned PUT for exactly [contentLength] bytes: the length is a
  /// signed header, so the store refuses any other size.
  Uri presignPut(String key, Duration ttl, {required int contentLength});

  Uri presignGet(String key, Duration ttl);

  Future<bool> ping();
}

/// One entry of [ObjectStorage.list].
final class StoredObject {
  const StoredObject(this.key, this.modified);

  final String key;
  final DateTime modified;
}

final class ObjectTooLarge implements Exception {
  const ObjectTooLarge();
}

final class OffsetMismatch implements Exception {
  const OffsetMismatch(this.actual);

  final int actual;
}

/// The object is not in the store at all (deleted, or never uploaded).
final class ObjectMissing implements Exception {
  const ObjectMissing();
}

/// The object is shorter than the bytes asked for: the row's declared size is
/// ahead of what was stored.
final class ObjectShort implements Exception {
  const ObjectShort();
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
    // One writer per key, in this process: the local backend is single-node by
    // construction (cluster mode requires S3), so this is the whole protocol.
    // Two requests at one offset used to both pass the length check below and
    // both append, and the route marked the object complete on bytes that were
    // two uploads interleaved (AUD-1c-2).
    final waiting = _appends[key];
    final gate = Completer<void>();
    _appends[key] = gate.future;
    if (waiting != null) {
      try {
        await waiting;
      } on Object {
        // The writer ahead of us failed; the file holds what it managed to
        // write, and the check below reads that length rather than trusting
        // either caller.
      }
    }
    try {
      return await _appendNow(key, data, offset: offset, maxSize: maxSize);
    } finally {
      gate.complete();
      if (identical(_appends[key], gate.future)) _appends.remove(key);
    }
  }

  final Map<String, Future<void>> _appends = {};

  Future<int> _appendNow(
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
    // The file's own length, never this writer's counter: the media route
    // marks the object complete when the returned number equals the declared
    // size, so a counter that drifted would seal a corrupt object.
    return await file.length();
  }

  @override
  Stream<List<int>> read(
    String key, {
    int start = 0,
    int? endInclusive,
  }) async* {
    final file = _file(key);
    if (!await file.exists()) throw const ObjectMissing();
    // The same contract as the S3 backend: a range the object cannot answer is
    // an error, not a silently short stream.
    if (start > 0 && start >= await file.length()) throw const ObjectShort();
    yield* file.openRead(start, endInclusive == null ? null : endInclusive + 1);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Stream<StoredObject> list(String prefix) async* {
    final dir = Directory(p.join(root, prefix));
    if (!p.isWithin(root, p.normalize(dir.path)) || !await dir.exists()) {
      return;
    }
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final key = p.relative(entry.path, from: root).replaceAll(r'\', '/');
      if (!_key.hasMatch(key)) continue;
      yield StoredObject(key, (await entry.lastModified()).toUtc());
    }
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
  S3ObjectStorage(
    this.config, {
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? _storeClient(),
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

  /// How long a request may go without its response headers, and how long the
  /// body may then go without another chunk. Nothing here used to have a
  /// deadline at all: a store that accepts the connection and stops answering
  /// hung the media status and download routes, the orphan sweep, and left one
  /// more HEAD in flight per readiness probe, for ever (AUD-1c-1).
  final Duration timeout;

  /// The connection phase is bounded too, so a blackholed endpoint fails in
  /// seconds rather than the operating system's own (minutes).
  static http.Client _storeClient() =>
      IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 5));

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

  /// Every request to the store: signed, then bounded. [headers] are passed to
  /// the signer, so a `Range` is part of the signed request rather than
  /// something appended after it.
  Future<http.StreamedResponse> _send(
    AWSHttpMethod method,
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final signed = _signer.signSync(
      AWSHttpRequest(method: method, uri: uri, headers: headers),
      credentialScope: _scope(),
      serviceConfiguration: _service,
    );
    final request = http.Request(method.value, signed.uri)
      ..headers.addAll(signed.headers);
    try {
      return await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw _timedOut(method);
    }
  }

  /// A whole, small response: the body is drained under the same [timeout], so
  /// a store that stops mid-body fails like one that never answered.
  Future<http.Response> _signed(AWSHttpMethod method, Uri uri) async {
    final response = await _send(method, uri);
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        builder.add(chunk);
      }
    } on TimeoutException {
      throw _timedOut(method);
    }
    return http.Response.bytes(
      builder.toBytes(),
      response.statusCode,
      headers: response.headers,
    );
  }

  HttpException _timedOut(AWSHttpMethod method) =>
      HttpException('S3 ${method.value} timed out after ${timeout.inSeconds}s');

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
  Stream<List<int>> read(String key, {int start = 0, int? endInclusive}) =>
      _streamed(
        _objectUri(key),
        ranged: start != 0 || endInclusive != null,
        window: endInclusive == null ? null : endInclusive + 1 - start,
        headers: start == 0 && endInclusive == null
            ? const {}
            : {
                'range': endInclusive == null
                    ? 'bytes=$start-'
                    : 'bytes=$start-$endInclusive',
              },
      );

  /// A response streamed rather than buffered, bounded the same way as every
  /// other request. Asking for a range gets a range: this used to download the
  /// whole object and slice it in memory, so a range read cost the object's
  /// size, and a stored object shorter than the row claimed threw `RangeError`
  /// (AUD-1c-4). [window] is the most the caller asked for, so a store that
  /// answers more than that is stopped at the boundary rather than passing the
  /// extras on.
  Stream<List<int>> _streamed(
    Uri uri, {
    required bool ranged,
    required Map<String, String> headers,
    int? window,
  }) async* {
    final response = await _send(AWSHttpMethod.get, uri, headers: headers);
    try {
      if (response.statusCode == 404) throw const ObjectMissing();
      if (response.statusCode == 416) throw const ObjectShort();
      if (ranged && response.statusCode == 200) {
        throw const HttpException('the store ignored the requested range');
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('S3 GET failed (${response.statusCode})');
      }
      var left = window;
      await for (final chunk in response.stream.timeout(timeout)) {
        if (left == null) {
          yield chunk;
          continue;
        }
        if (left <= 0) break;
        yield chunk.length <= left
            ? chunk
            : chunk is Uint8List
            ? Uint8List.sublistView(chunk, 0, left)
            : chunk.sublist(0, left);
        left -= chunk.length;
      }
    } on TimeoutException {
      throw _timedOut(AWSHttpMethod.get);
    }
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

  /// ListObjectsV2, a page of up to 1000 keys at a time.
  @override
  Stream<StoredObject> list(String prefix) async* {
    String? token;
    do {
      final uri = _bucketUri().replace(
        queryParameters: {
          'list-type': '2',
          'prefix': prefix,
          'continuation-token': ?token,
        },
      );
      final response = await _signed(AWSHttpMethod.get, uri);
      if (response.statusCode != 200) {
        throw HttpException('S3 LIST failed (${response.statusCode})');
      }
      final body = response.body;
      for (final m in _contents.allMatches(body)) {
        final entry = m.group(1)!;
        final key = _tag('Key', entry);
        final modified = DateTime.tryParse(_tag('LastModified', entry) ?? '');
        if (key == null || modified == null) continue;
        yield StoredObject(key, modified.toUtc());
      }
      token = _tag('IsTruncated', body) == 'true'
          ? _tag('NextContinuationToken', body)
          : null;
    } while (token != null);
  }

  static final _contents = RegExp(r'<Contents>(.*?)</Contents>', dotAll: true);

  /// The text of the first `<name>` element in [xml] (keys here are
  /// `[a-z0-9_/-]`, so no entity decoding is needed).
  static String? _tag(String name, String xml) =>
      RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml)?.group(1);

  /// The readiness probe is cheap and shared: one request at a time, and its
  /// answer reused for 5 s. A dead store is therefore probed once per window
  /// instead of once per `GET /v1/health/ready`, and the probes cannot pile up
  /// behind a request that never returns (AUD-1c-1).
  @override
  Future<bool> ping() {
    final answer = _pingAnswer;
    final at = _pingedAt;
    if (answer != null && at != null && _uptime.elapsed - at < _pingTtl) {
      return Future.value(answer);
    }
    final running = _pingRequest;
    if (running != null) return running;
    final request = _probe();
    _pingRequest = request;
    return request.whenComplete(() => _pingRequest = null);
  }

  Future<bool> _probe() async {
    var ok = false;
    try {
      ok = (await _signed(AWSHttpMethod.head, _bucketUri())).statusCode == 200;
    } on Object {
      // Refused, unreachable or timed out: the store is not healthy, and the
      // answer is cached so the next probe waits rather than spawning.
    }
    _pingedAt = _uptime.elapsed;
    _pingAnswer = ok;
    return ok;
  }

  static const _pingTtl = Duration(seconds: 5);
  final Stopwatch _uptime = Stopwatch()..start();
  Duration? _pingedAt;
  bool? _pingAnswer;
  Future<bool>? _pingRequest;
}
