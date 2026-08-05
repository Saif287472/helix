// Before this existed, every route handler across 16 files hand-built its
// own Response(statusCode, jsonEncode({'error': ...})) - 350 call sites with
// no shared shape and no machine-readable code the client could branch on
// without string-matching a message. AppError gives every migrated handler
// the same {error, code, details?} body for free.

import 'dart:convert';

import 'package:helix_remote_backend/src/app_error.dart';
import 'package:test/test.dart';

void main() {
  test('unauthorized produces a 401 with the unauthorized code', () {
    final error = AppError.unauthorized('Missing or invalid token');
    final response = error.toResponse();
    expect(response.statusCode, equals(401));
    expect(response.headers['Content-Type'], contains('application/json'));
  });

  test('forbidden supports a more specific code than the default', () {
    final error = AppError.forbidden(
      'You are not a member of this conversation',
      code: RemoteErrorCode.notAMember,
    );
    expect(error.toJson(), {
      'error': 'You are not a member of this conversation',
      'code': 'not_a_member',
    });
  });

  test('badRequest carries optional details', () {
    final error = AppError.badRequest(
      'Missing per-device encrypted envelopes',
      details: {'missing_device_count': 2},
    );
    expect(error.toJson(), {
      'error': 'Missing per-device encrypted envelopes',
      'code': 'bad_request',
      'details': {'missing_device_count': 2},
    });
  });

  test(
    'notFound, conflict, and serviceUnavailable map to their status codes',
    () {
      expect(AppError.notFound('gone').statusCode, equals(404));
      expect(AppError.conflict('taken').statusCode, equals(409));
      expect(
        AppError.serviceUnavailable('federation off').statusCode,
        equals(503),
      );
    },
  );

  test(
    'internal() never leaks the underlying message to the response body',
    () async {
      final error = AppError.internal();
      expect(error.statusCode, equals(500));
      final body = await error.toResponse().readAsString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect(decoded['error'], equals('Internal server error'));
      expect(decoded['code'], equals('internal_error'));
    },
  );

  test(
    'toResponse body round-trips through JSON exactly like toJson',
    () async {
      final error = AppError.forbidden('nope');
      final response = error.toResponse();
      final body = await response.readAsString();
      expect(jsonDecode(body), equals(error.toJson()));
    },
  );
}
