import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One object on the fake media server.
final class FakeObject {
  FakeObject(this.id, this.size, this.kind);

  final String id;
  final int size;
  final String kind;
  final BytesBuilder _data = BytesBuilder(copy: false);

  int get stored => _data.length;
  bool get complete => stored == size;
  Uint8List get bytes => _data.toBytes();

  void append(List<int> more) => _data.add(more);
}

/// What the fake saw of one media request.
final class MediaRequest {
  const MediaRequest(this.method, this.id, {this.offset, this.length});

  final String method;
  final String? id;
  final int? offset;
  final int? length;

  @override
  String toString() => '$method $id offset=$offset length=$length';
}

/// The media module of the server, in memory, behind an `http.Client`:
/// `POST /v1/media`, resumable local `PUT` with `Upload-Offset` (409 with the
/// stored offset on a mismatch), `HEAD`, ranged `GET`, `DELETE`, or the S3
/// flavour (a presigned `PUT` of exactly `size` bytes, a 302 to a presigned
/// `GET`), with the limits and the faults the transfer tests need.
final class FakeMedia {
  FakeMedia({
    this.maxBytes = 100 * 1024 * 1024,
    this.quotaBytes = 4 * 1024 * 1024 * 1024,
    this.presigned = false,
    this.redirectDownloads = false,
  });

  static const s3Host = 's3.fake';

  int maxBytes;
  int quotaBytes;

  /// Answer `POST /v1/media` with a presigned (non-resumable) target.
  bool presigned;

  /// Answer downloads with a 302 to a presigned URL.
  bool redirectDownloads;

  final Map<String, FakeObject> objects = {};
  final List<MediaRequest> requests = [];
  int _ids = 0;
  int _puts = 0;
  int _gets = 0;

  /// Numbers (1-based, over all local `PUT`s) of the requests to drop
  /// before they store anything (the connection dies).
  final Set<int> dropPuts = {};

  /// Numbers of the `PUT`s whose bytes are stored but whose answer is lost.
  final Set<int> loseResponsePuts = {};

  /// The next [offlineNext] requests of any kind fail with no answer.
  int offlineNext = 0;

  /// The next requests answer with an error: [times] of them, [code], and
  /// `Retry-After` when [retryAfter] is set.
  void failNext(ErrorCode code, {int times = 1, Duration? retryAfter}) {
    _faults
      ..clear()
      ..addAll([for (var i = 0; i < times; i++) (code, retryAfter)]);
  }

  final List<(ErrorCode, Duration?)> _faults = [];

  /// Downloads return damaged bytes.
  bool corruptDownloads = false;

  /// Downloads ignore `Range` and send the whole object (200).
  bool ignoreRange = false;

  /// Numbers (1-based, over all local and redirected `GET`s) of the requests
  /// to drop (the connection dies).
  final Set<int> dropGets = {};

  /// Runs inside every local `PUT`, before it is checked (tests pause here,
  /// or store bytes behind the client's back).
  Future<void> Function(FakeObject object, int offset, Uint8List bytes)? onPut;

  /// Runs inside every `GET` that finds its object (tests pause here).
  Future<void> Function(FakeObject object)? onGet;

  /// How many local `PUT`s arrived.
  int get putCount => _puts;

  List<MediaRequest> of(String method) => [
    for (final r in requests)
      if (r.method == method) r,
  ];

  int get usedBytes => objects.values.fold(0, (sum, o) => sum + o.size);

  /// Removes every object (the 30 days passed).
  void expireAll() => objects.clear();

  /// Routes media requests here and everything else to [inner].
  http.Client wrap(http.Client inner) => MockClient((request) async {
    final response = await handle(request);
    if (response != null) return response;
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..bodyBytes = request.bodyBytes;
    return http.Response.fromStream(await inner.send(copy));
  });

  /// The response to a media request, or null when [r] is not one.
  Future<http.Response?> handle(http.Request r) async {
    final external = r.url.host == s3Host;
    final path = r.url.path;
    if (!external && !path.startsWith('/v1/media')) return null;
    if (offlineNext > 0) {
      offlineNext--;
      throw http.ClientException('offline');
    }
    if (_faults.isNotEmpty && !external) {
      final (code, after) = _faults.removeAt(0);
      return http.Response(
        jsonEncode(ApiError(code, retryAfter: after).toJson()),
        code.status,
        headers: {
          'content-type': 'application/json',
          if (after != null) 'retry-after': '${after.inSeconds}',
        },
      );
    }
    if (external) return _external(r);
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    // /v1/media, /v1/media/{id}, /v1/media/{id}/content
    final id = parts.length > 2 ? parts[2] : null;
    switch (r.method) {
      case 'POST' when id == null:
        return _create(r);
      case 'PUT' when id != null:
        return _put(r, id);
      case 'HEAD' when id != null:
        requests.add(MediaRequest('HEAD', id));
        final o = objects[id];
        if (o == null) return _error(ErrorCode.notFound);
        return http.Response(
          '',
          200,
          headers: {
            'upload-offset': '${o.stored}',
            'upload-length': '${o.size}',
          },
        );
      case 'GET' when id != null:
        return _get(r, id);
      case 'DELETE' when id != null:
        requests.add(MediaRequest('DELETE', id));
        if (objects.remove(id) == null) return _error(ErrorCode.notFound);
        return http.Response('', 204);
    }
    return _error(ErrorCode.notFound);
  }

  http.Response _create(http.Request r) {
    requests.add(const MediaRequest('POST', null));
    final request = CreateUploadRequest.fromJson(JsonReader.decode(r.body));
    if (request.size <= 0 || request.size > maxBytes) {
      return _error(
        ErrorCode.payloadTooLarge,
        details: {'max_bytes': maxBytes},
      );
    }
    if (usedBytes + request.size > quotaBytes) {
      return _error(
        ErrorCode.quotaExceeded,
        details: {'quota_bytes': quotaBytes},
      );
    }
    final id = 'media-${_ids++}';
    objects[id] = FakeObject(id, request.size, request.kind.wire);
    final target = presigned
        ? UploadTarget(
            mediaId: id,
            url: 'https://$s3Host/put/$id',
            expiresAt: DateTime.utc(2026, 10, 3),
            resumable: false,
          )
        : UploadTarget(
            mediaId: id,
            url: '/v1/media/$id/content',
            expiresAt: DateTime.utc(2026, 10, 3),
          );
    return http.Response(
      jsonEncode(target.toJson()),
      201,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<http.Response> _put(http.Request r, String id) async {
    final offset = int.tryParse(r.headers['upload-offset'] ?? '0') ?? 0;
    requests.add(
      MediaRequest('PUT', id, offset: offset, length: r.bodyBytes.length),
    );
    final number = ++_puts;
    final o = objects[id];
    if (o == null) return _error(ErrorCode.notFound);
    if (dropPuts.remove(number)) throw http.ClientException('connection lost');
    await onPut?.call(o, offset, r.bodyBytes);
    if (o.complete) return _error(ErrorCode.conflict);
    if (offset != o.stored) {
      return _error(ErrorCode.conflict, details: {'upload_offset': o.stored});
    }
    if (offset + r.bodyBytes.length > o.size) {
      return _error(ErrorCode.payloadTooLarge);
    }
    o.append(r.bodyBytes);
    if (loseResponsePuts.remove(number)) {
      throw http.ClientException('connection lost');
    }
    return http.Response(
      '',
      204,
      headers: {'upload-offset': '${o.stored}', 'upload-length': '${o.size}'},
    );
  }

  Future<http.Response> _get(http.Request r, String id) async {
    requests.add(MediaRequest('GET', id, offset: _rangeStart(r)));
    final o = objects[id];
    if (o == null || !o.complete) return _error(ErrorCode.notFound);
    if (dropGets.remove(++_gets)) throw http.ClientException('connection lost');
    await onGet?.call(o);
    if (redirectDownloads) {
      return http.Response(
        '',
        302,
        headers: {'location': 'https://$s3Host/get/$id'},
      );
    }
    return _serve(o, r.headers['range']);
  }

  int? _rangeStart(http.Request r) {
    final m = RegExp(r'^bytes=(\d+)-').firstMatch(r.headers['range'] ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  Future<http.Response> _external(http.Request r) async {
    final parts = r.url.path.split('/').where((p) => p.isNotEmpty).toList();
    final id = parts.last;
    requests.add(
      MediaRequest(
        'S3 ${r.method}',
        id,
        offset: _rangeStart(r),
        length: r.method == 'PUT' ? r.bodyBytes.length : null,
      ),
    );
    final o = objects[id];
    if (o == null) return http.Response('', 404);
    if (r.method == 'GET' && dropGets.remove(++_gets)) {
      throw http.ClientException('connection lost');
    }
    if (r.method == 'GET') await onGet?.call(o);
    if (r.method == 'PUT') {
      if (r.bodyBytes.length != o.size) return http.Response('', 403);
      o.append(r.bodyBytes);
      return http.Response('', 200);
    }
    return _serve(o, r.headers['range']);
  }

  http.Response _serve(FakeObject o, String? range) {
    var bytes = o.bytes;
    if (corruptDownloads) {
      bytes = Uint8List.fromList(bytes);
      bytes[bytes.length ~/ 2] ^= 0xFF;
    }
    final match = range == null || ignoreRange
        ? null
        : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match == null) return http.Response.bytes(bytes, 200);
    final start = int.parse(match.group(1)!);
    var end = match.group(2)!.isEmpty
        ? bytes.length - 1
        : int.parse(match.group(2)!);
    if (end >= bytes.length) end = bytes.length - 1;
    if (start >= bytes.length || start > end) {
      return http.Response(
        '',
        416,
        headers: {'content-range': 'bytes */${bytes.length}'},
      );
    }
    return http.Response.bytes(
      bytes.sublist(start, end + 1),
      206,
      headers: {'content-range': 'bytes $start-$end/${bytes.length}'},
    );
  }

  http.Response _error(ErrorCode code, {JsonMap? details}) => http.Response(
    jsonEncode(ApiError(code, details: details).toJson()),
    code.status,
    headers: {'content-type': 'application/json'},
  );
}
