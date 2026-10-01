import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:shelf/shelf.dart';

/// Who is calling.
sealed class Principal {
  const Principal();

  /// Stable key for idempotency records and per-principal rate limits.
  String get key;
}

final class DevicePrincipal extends Principal {
  const DevicePrincipal({required this.accountId, required this.deviceId});

  final String accountId;
  final String deviceId;

  @override
  String get key => 'device:$deviceId';
}

final class AdminPrincipal extends Principal {
  const AdminPrincipal({required this.adminId});

  final String adminId;

  @override
  String get key => 'admin:$adminId';
}

final class ServerPrincipal extends Principal {
  const ServerPrincipal({required this.serverId});

  final String serverId;

  @override
  String get key => 'server:$serverId';
}

final class AnonymousPrincipal extends Principal {
  const AnonymousPrincipal(this.clientIp);

  final String clientIp;

  @override
  String get key => 'ip:$clientIp';
}

/// What a route handler receives.
final class HelixRequest {
  HelixRequest({
    required this.raw,
    required this.route,
    required this.principal,
    required this.requestId,
    required this.clientIp,
    required this.params,
    this.body,
  });

  final Request raw;
  final ApiRoute route;
  final Principal principal;
  final String requestId;
  final String clientIp;

  /// Path parameters by name (already percent-decoded).
  final Map<String, String> params;

  /// The request body, read up to the route's limit (null for streaming
  /// routes, whose handlers read [raw] themselves).
  final Uint8List? body;

  String param(String name) {
    final value = params[name];
    if (value == null) {
      throw StateError('route ${route.path} has no parameter $name');
    }
    return value;
  }

  /// A path parameter that must be a canonical UUID.
  String uuidParam(String name) {
    final value = param(name);
    if (!Uuid.isValid(value)) {
      throw ApiError(
        ErrorCode.invalidField,
        message: '$name is not a valid id',
      );
    }
    return value;
  }

  DevicePrincipal get device => switch (principal) {
    final DevicePrincipal d => d,
    _ => throw StateError('route ${route.path} is not a device route'),
  };

  AdminPrincipal get admin => switch (principal) {
    final AdminPrincipal a => a,
    _ => throw StateError('route ${route.path} is not an admin route'),
  };

  ServerPrincipal get server => switch (principal) {
    final ServerPrincipal s => s,
    _ => throw StateError('route ${route.path} is not an s2s route'),
  };

  String? query(String name) => raw.url.queryParameters[name];

  List<String> queryAll(String name) =>
      raw.url.queryParametersAll[name] ?? const [];

  /// Decodes the JSON body with [decode]. Malformed bodies become
  /// `invalid_field` / `bad_request` errors naming the field.
  T json<T>(T Function(JsonReader json) decode) {
    final bytes = body;
    if (bytes == null || bytes.isEmpty) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'a JSON body is required',
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ApiError(ErrorCode.badRequest, message: 'body is not UTF-8');
    }
    try {
      return decode(JsonReader.decode(text));
    } on ProtocolFormatException catch (e) {
      throw ApiError(
        ErrorCode.invalidField,
        message: e.path.isEmpty ? 'malformed body' : 'invalid ${e.path}',
        details: e.path.isEmpty ? null : {'field': e.path},
      );
    }
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// A JSON response from a DTO's `toJson()`.
Response jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response noContent() => Response(204);

Response errorResponse(ApiError error) => Response(
  error.status,
  body: jsonEncode(error.toJson()),
  headers: {
    ..._jsonHeaders,
    if (error.retryAfter != null)
      HelixHeaders.retryAfter: '${error.retryAfter!.inSeconds}',
  },
);
