import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_api/src/v2/transport/auth.dart';
import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_api/src/v2/transport/retry.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;

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
/// retries per [RetryPolicy]; enforces a per-attempt [timeout] and
/// [CancellationToken]s; and maps error responses to [ApiException].
///
/// It never logs. Tokens and bodies stay out of every exception it throws.
final class HelixTransport {
  HelixTransport({
    required this.baseUrl,
    http.Client? client,
    this.auth,
    this.clientName,
    this.retry = const RetryPolicy(),
    this.timeout = const Duration(seconds: 30),
    Future<void> Function(Duration delay)? sleep,
    Random? random,
    String Function()? newId,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random(),
       _newId = newId ?? Uuid.v7;

  /// The server, e.g. `https://helix.agiletechbd.com`. A path prefix is kept.
  final Uri baseUrl;

  /// Tokens for device or admin routes; null for a transport that only
  /// calls public routes.
  final AuthProvider? auth;

  /// `x-helix-client`, e.g. `android/2.0.0`.
  final String? clientName;
  final RetryPolicy retry;

  /// Per attempt, until the whole response body has arrived.
  final Duration timeout;

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
          timeout: timeout ?? this.timeout,
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

      if (status == 401 &&
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
  Future<ApiResponse> external(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? bytes,
    Set<int> accept = const {},
    CancellationToken? cancel,
    Duration? timeout,
  }) async {
    final response = await _attempt(
      method: method,
      uri: uri,
      headers: headers,
      body: bytes == null ? null : Uint8List.fromList(bytes),
      followRedirects: false,
      cancel: cancel,
      timeout: timeout ?? this.timeout,
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
    required bool followRedirects,
    required CancellationToken? cancel,
    required Duration timeout,
  }) async {
    final abort = Completer<_Abort>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete(_Abort.timeout);
    });
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!abort.isCompleted) abort.complete(_Abort.cancelled);
      }),
    );
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..followRedirects = followRedirects;
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;

    // Some clients ignore the abort trigger; racing it keeps the timeout and
    // cancellation effective anyway.
    Future<T> race<T>(Future<T> work) => Future.any([
      work,
      abort.future.then<T>((reason) => throw _Aborted(reason)),
    ]);

    try {
      final streamed = await race(_client.send(request));
      final bytes = await race(streamed.stream.toBytes());
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
      timer.cancel();
      if (!abort.isCompleted) abort.complete(_Abort.done);
    }
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

enum _Abort { timeout, cancelled, done }

final class _Aborted implements Exception {
  const _Aborted(this.reason);

  final _Abort reason;
}
