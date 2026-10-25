import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_api/src/v2/transport/auth.dart';
import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_api/src/v2/transport/retry.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;

/// The most a response body may hold unless the call says otherwise (JSON
/// answers are small). Bodies longer than the cap are dropped while they
/// stream in ([ResponseTooLargeException]); media downloads, backups and the
/// account export pass their own, larger caps.
const defaultMaxResponseBytes = 4 * 1024 * 1024;

/// A request whose body or declared response cap is larger than this is a
/// bulk transfer: it gets an inactivity deadline instead of a cap on the whole
/// transfer, because 4 MiB at the normal 30 s already fails below ~1 Mbps
/// (AUD-11a-1). Calls at or below it keep the whole-transfer deadline.
const bulkTransferBytes = defaultMaxResponseBytes;

/// A successful (or explicitly accepted) HTTP response.
final class ApiResponse {
  const ApiResponse({
    required this.status,
    required this.headers,
    required this.body,
    this.requestId,
  });

  final int status;

  /// Lower-case header names.
  final Map<String, String> headers;
  final Uint8List body;
  final String? requestId;

  /// Decodes the JSON body with [decode]. A body that does not match the
  /// contract throws [MalformedResponseException].
  T decode<T>(T Function(JsonReader json) decode) {
    try {
      return decode(JsonReader.decode(utf8.decode(body)));
    } on ProtocolFormatException catch (e) {
      throw MalformedResponseException(path: e.path, requestId: requestId);
    } on FormatException {
      throw MalformedResponseException(path: '', requestId: requestId);
    }
  }

  String get text => utf8.decode(body, allowMalformed: true);
}

/// The HTTP layer every v2 REST client shares.
///
/// Builds URLs from the protocol route catalog, attaches the bearer token
/// for the route's audience (refreshing once on 401), an `Idempotency-Key`
/// on every unsafe request, an `x-request-id` and an `x-helix-client`;
/// retries per [RetryPolicy]; enforces a per-attempt [timeout] - an
/// inactivity limit for a bulk call, see [bulkTransferBytes] - and
/// [CancellationToken]s; and maps error responses to [ApiException].
///
/// It never logs. Tokens and bodies stay out of every exception it throws.
/// [onFailure] is told about each request the server refused, by route
/// template, status, error code and request id only.
final class HelixTransport {
  HelixTransport({
    required this.baseUrl,
    http.Client? client,
    this.auth,
    this.clientName,
    this.retry = const RetryPolicy(),
    this.timeout = const Duration(seconds: 30),
    this.bulkIdleTimeout = const Duration(seconds: 30),
    Future<void> Function(Duration delay)? sleep,
    Random? random,
    String Function()? newId,
    this.onFailure,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random(),
       _newId = newId ?? Uuid.v7;

  /// The server, e.g. `https://helix.agiletechbd.com`. A path prefix is kept.
  final Uri baseUrl;

  /// Told about every request that ends in an error response (after any
  /// retries and the token refresh). Never told a body, a header or a token.
  final void Function(RequestFailure failure)? onFailure;

  /// Tokens for device or admin routes; null for a transport that only
  /// calls public routes.
  final AuthProvider? auth;

  /// `x-helix-client`, e.g. `android/2.0.0`.
  final String? clientName;
  final RetryPolicy retry;

  /// Per attempt, until the whole response body has arrived.
  final Duration timeout;

  /// How long a bulk transfer may stand still. The clock resets on every
  /// chunk sent or received, so a large body may take as long as it needs
  /// while it keeps moving, and a dead link still fails.
  final Duration bulkIdleTimeout;

  final http.Client _client;
  final bool _ownsClient;
  final Future<void> Function(Duration) _sleep;
  final Random _random;
  final String Function() _newId;

  /// The absolute URL of [route].
  Uri url(
    ApiRoute route, {
    Map<String, String> params = const {},
    Map<String, Object> query = const {},
    String scheme = '',
  }) {
    final prefix = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(
      scheme: scheme.isEmpty ? null : scheme,
      path: '$prefix${route.expand(params)}',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  /// Sends one catalog request and returns its 2xx response (or a status in
  /// [accept]); every other status throws [ApiException].
  ///
  /// Exactly one of [json] and [bytes] may be given. [bearer] replaces the
  /// audience token (the link poll token on a public route). [query] values
  /// are a `String` or an `Iterable<String>` (repeated parameter).
  Future<ApiResponse> send(
    ApiRoute route, {
    Map<String, String> params = const {},
    Map<String, Object> query = const {},
    JsonMap? json,
    List<int>? bytes,
    Map<String, String> headers = const {},
    String? bearer,
    String? idempotencyKey,
    Set<int> accept = const {},
    bool followRedirects = true,
    CancellationToken? cancel,
    Duration? timeout,
    int maxResponseBytes = defaultMaxResponseBytes,
  }) async {
    if (json != null && bytes != null) {
      throw ArgumentError('send either json or bytes, not both');
    }
    final usesAudience =
        route.access == RouteAccess.device || route.access == RouteAccess.admin;
    if (route.access == RouteAccess.s2s) {
      throw ArgumentError('$route is server-to-server only');
    }
    if (usesAudience && bearer == null) {
      final provider = auth;
      if (provider == null) {
        throw const SignedOutException(SignedOutReason.noSession);
      }
      if (provider.audience != route.access) {
        throw StateError(
          '$route needs a ${route.access.name} token; this transport holds '
          '${provider.audience.name} tokens',
        );
      }
    }

    final unsafe =
        route.method != HttpMethod.get && route.method != HttpMethod.head;
    final key = unsafe ? (idempotencyKey ?? _newId()) : null;
    final repeatable =
        !unsafe ||
        route.method == HttpMethod.put ||
        route.method == HttpMethod.delete ||
        route.access == RouteAccess.device;
    final requestId = _newId();
    final uri = url(route, params: params, query: query);
    final body = json != null
        ? utf8.encode(jsonEncode(json))
        : bytes == null
        ? null
        : Uint8List.fromList(bytes);
    final bulk =
        maxResponseBytes > bulkTransferBytes ||
        (body?.length ?? 0) > bulkTransferBytes;

    var failures = 0;
    var refreshed = false;
    String? token = bearer;
    while (true) {
      if (cancel?.isCancelled ?? false) throw const RequestCancelledException();
      if (usesAudience && bearer == null) token ??= await auth!.accessToken();

      final http.Response response;
      try {
        response = await _attempt(
          method: route.method.name.toUpperCase(),
          uri: uri,
          headers: {
            'accept': 'application/json',
            if (json != null) 'content-type': 'application/json',
            if (bytes != null) 'content-type': 'application/octet-stream',
            HelixHeaders.requestId: requestId,
            HelixHeaders.client: ?clientName,
            HelixHeaders.idempotencyKey: ?key,
            HelixHeaders.authorization: ?(token == null
                ? null
                : 'Bearer $token'),
            ...headers,
          },
          body: body,
          followRedirects: followRedirects,
          cancel: cancel,
          timeout: bulk
              ? (timeout ?? bulkIdleTimeout)
              : (timeout ?? this.timeout),
          maxBytes: maxResponseBytes,
          idle: bulk,
        );
      } on NetworkException {
        failures++;
        if (!repeatable || failures >= retry.maxAttempts) rethrow;
        await _wait(retry.backoff(failures, _random), cancel);
        continue;
      }

      final status = response.statusCode;
      final responseId = response.headers[HelixHeaders.requestId] ?? requestId;
      if ((status >= 200 && status < 300) || accept.contains(status)) {
        return ApiResponse(
          status: status,
          headers: response.headers,
          body: response.bodyBytes,
          requestId: responseId,
        );
      }

      final error = ApiException.fromResponse(
        status: status,
        body: response.bodyBytes,
        retryAfterHeader: response.headers[HelixHeaders.retryAfter],
        requestId: responseId,
      );

      // `invalid_credentials` is also a 401, but it answers a wrong
      // password in the body (the admin password change), not a rejected
      // token: refreshing, or ending an admin session, would be wrong.
      if (status == 401 &&
          error.code != ErrorCode.invalidCredentials &&
          usesAudience &&
          bearer == null &&
          !refreshed &&
          token != null) {
        refreshed = true;
        token = await auth!.refresh(token);
        continue;
      }

      final transient =
          error.code.isRetryable && error.code != ErrorCode.passwordLocked;
      if (transient && repeatable) {
        failures++;
        final wait = error.retryAfter ?? retry.backoff(failures, _random);
        if (failures < retry.maxAttempts && wait <= retry.maxRetryAfter) {
          await _wait(wait, cancel);
          continue;
        }
      }
      final observe = onFailure;
      if (observe != null) {
        try {
          observe(
            RequestFailure(
              route: route,
              status: status,
              code: error.code.wire,
              requestId: responseId,
            ),
          );
        } on Object {
          // An observer never changes what the caller sees.
        }
      }
      throw error;
    }
  }

  /// Decodes a JSON response.
  Future<T> call<T>(
    ApiRoute route,
    T Function(JsonReader json) decode, {
    Map<String, String> params = const {},
    Map<String, Object> query = const {},
    JsonMap? json,
    String? bearer,
    String? idempotencyKey,
    Set<int> accept = const {},
    CancellationToken? cancel,
    Duration? timeout,
    int maxResponseBytes = defaultMaxResponseBytes,
  }) async => (await send(
    route,
    params: params,
    query: query,
    json: json,
    bearer: bearer,
    idempotencyKey: idempotencyKey,
    accept: accept,
    cancel: cancel,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
  )).decode(decode);

  /// A request whose response has no body (204).
  Future<void> empty(
    ApiRoute route, {
    Map<String, String> params = const {},
    Map<String, Object> query = const {},
    JsonMap? json,
    String? idempotencyKey,
    CancellationToken? cancel,
  }) async {
    await send(
      route,
      params: params,
      query: query,
      json: json,
      idempotencyKey: idempotencyKey,
      cancel: cancel,
    );
  }

  /// A request to a URL outside the catalog: presigned object storage URLs
  /// from `UploadTarget` or a media redirect. Never carries the bearer token
  /// or Helix headers (the URL is its own capability), never retried, never
  /// follows redirects.
  ///
  /// [stream] sends the body as it is produced ([contentLength] is then
  /// required) instead of buffering it first, so a large presigned upload
  /// never has to hold the whole ciphertext in memory.
  Future<ApiResponse> external(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? bytes,
    Stream<List<int>>? stream,
    int? contentLength,
    Set<int> accept = const {},
    CancellationToken? cancel,
    Duration? timeout,
    int maxResponseBytes = defaultMaxResponseBytes,
  }) async {
    if (stream != null && bytes != null) {
      throw ArgumentError('send either bytes or a stream, not both');
    }
    if (stream != null && contentLength == null) {
      throw ArgumentError('a streamed body needs its contentLength');
    }
    final length = stream == null ? bytes?.length : contentLength;
    final bulk =
        maxResponseBytes > bulkTransferBytes ||
        (length ?? 0) > bulkTransferBytes;
    final response = await _attempt(
      method: method,
      uri: uri,
      headers: headers,
      body: stream == null && bytes != null ? Uint8List.fromList(bytes) : null,
      bodyStream: stream,
      bodyLength: contentLength,
      followRedirects: false,
      cancel: cancel,
      timeout: bulk ? (timeout ?? bulkIdleTimeout) : (timeout ?? this.timeout),
      maxBytes: maxResponseBytes,
      idle: bulk,
    );
    final status = response.statusCode;
    if ((status >= 200 && status < 300) || accept.contains(status)) {
      return ApiResponse(
        status: status,
        headers: response.headers,
        body: response.bodyBytes,
      );
    }
    // Object stores answer in XML; only the status class is meaningful.
    throw ApiException(
      status: status,
      code: ApiException.codeForStatus(status),
    );
  }

  Future<http.Response> _attempt({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List? body,
    Stream<List<int>>? bodyStream,
    int? bodyLength,
    required bool followRedirects,
    required CancellationToken? cancel,
    required Duration timeout,
    required int maxBytes,
    bool idle = false,
  }) async {
    final abort = Completer<_Abort>();
    Timer? timer;
    // A normal attempt is capped as a whole; an idle one only while nothing
    // moves, so the clock is re-armed on every chunk in either direction.
    void arm() {
      timer?.cancel();
      timer = Timer(timeout, () {
        if (!abort.isCompleted) abort.complete(_Abort.timeout);
      });
    }

    void progress() {
      if (idle) arm();
    }

    arm();
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!abort.isCompleted) abort.complete(_Abort.cancelled);
      }),
    );
    final source =
        bodyStream ?? (idle && body != null ? _slices(body, progress) : null);
    final http.BaseRequest request;
    if (source == null) {
      final buffered = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )..followRedirects = followRedirects;
      if (body != null) buffered.bodyBytes = body;
      request = buffered;
    } else {
      request = _StreamedBodyRequest(
        method,
        uri,
        _paced(source, progress),
        abortTrigger: abort.future,
      )..followRedirects = followRedirects;
      request.contentLength = bodyStream == null ? body!.length : bodyLength!;
    }
    request.headers.addAll(headers);

    // Some clients ignore the abort trigger; racing it keeps the timeout and
    // cancellation effective anyway.
    Future<T> race<T>(Future<T> work) => Future.any([
      work,
      abort.future.then<T>((reason) => throw _Aborted(reason)),
    ]);

    try {
      final streamed = await race(_client.send(request));
      final bytes = await race(
        _readCapped(streamed, maxBytes, onChunk: idle ? progress : null),
      );
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
    } on _Aborted catch (e) {
      throw e.reason == _Abort.cancelled
          ? const RequestCancelledException()
          : const NetworkException(timedOut: true, cause: TimeoutException);
    } on http.RequestAbortedException {
      throw await abort.future == _Abort.cancelled
          ? const RequestCancelledException()
          : const NetworkException(timedOut: true, cause: TimeoutException);
    } on http.ClientException catch (e) {
      throw NetworkException(cause: e.runtimeType);
    } finally {
      timer?.cancel();
      if (!abort.isCompleted) abort.complete(_Abort.done);
    }
  }

  /// A buffered body for an idle attempt, handed over one slice at a time so
  /// a slow link still counts as progress (and the body is never duplicated).
  static Stream<List<int>> _slices(
    Uint8List body,
    void Function() progress,
  ) async* {
    const slice = 64 * 1024;
    for (var start = 0; start < body.length; start += slice) {
      await Future<void>.delayed(Duration.zero);
      yield Uint8List.sublistView(body, start, min(start + slice, body.length));
      progress();
    }
  }

  /// Re-arms the idle clock as each chunk is pulled by the client, so the
  /// timer follows the socket rather than this loop.
  static Stream<List<int>> _paced(
    Stream<List<int>> source,
    void Function() progress,
  ) async* {
    await for (final chunk in source) {
      yield chunk;
      progress();
    }
  }

  /// Collects the body, giving up as soon as it is longer than [limit]
  /// (declared by `content-length`, or counted while it streams): a hostile
  /// or broken peer cannot make this process buffer an unbounded body.
  Future<Uint8List> _readCapped(
    http.StreamedResponse response,
    int limit, {
    void Function()? onChunk,
  }) async {
    final declared = response.contentLength;
    if (declared != null && declared > limit) {
      unawaited(response.stream.listen(null).cancel());
      throw ResponseTooLargeException(limit: limit);
    }
    final out = BytesBuilder(copy: false);
    final done = Completer<Uint8List>();
    late StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) {
        onChunk?.call();
        if (out.length + chunk.length > limit) {
          unawaited(subscription.cancel());
          if (!done.isCompleted) {
            done.completeError(ResponseTooLargeException(limit: limit));
          }
          return;
        }
        out.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(out.takeBytes());
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Future<void> _wait(Duration delay, CancellationToken? cancel) async {
    if (cancel == null) return _sleep(delay);
    await Future.any([_sleep(delay), cancel.whenCancelled]);
    if (cancel.isCancelled) throw const RequestCancelledException();
  }

  /// Closes the HTTP client if this transport created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// A request whose body is produced lazily, so a bulk upload is not copied
/// into one buffer and its progress can re-arm the idle clock.
final class _StreamedBodyRequest extends http.StreamedRequest
    with http.Abortable {
  _StreamedBodyRequest(super.method, super.url, this.body, {this.abortTrigger});

  final Stream<List<int>> body;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}

enum _Abort { timeout, cancelled, done }

final class _Aborted implements Exception {
  const _Aborted(this.reason);

  final _Abort reason;
}

/// A request the server refused, as [HelixTransport.onFailure] sees it: the
/// route's template (`/v1/groups/{group_id}`, never the real ids), the
/// status, the error code and the request id the server logged it under.
final class RequestFailure {
  const RequestFailure({
    required this.route,
    required this.status,
    required this.code,
    required this.requestId,
  });

  final ApiRoute route;
  final int status;
  final String code;
  final String requestId;
}
