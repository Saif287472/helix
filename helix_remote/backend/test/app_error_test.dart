// Before this existed, every route handler across 16 files hand-built its
// own Response(statusCode, jsonEncode({'error': ...})) - 350 call sites with
// no shared shape and no machine-readable code the client could branch on
// without string-matching a message. AppError gives every migrated handler
// the same {error, code, details?} body for free.

import 'dart:convert';

import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
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

  test('headers ride along with the normalized body', () {
    // A 416 is only useful to a client if it also says how big the object
    // actually is, so the range handler needs to attach one header without
    // giving up the shared error shape.
    final error = AppError(
      'Requested Range Not Satisfiable',
      statusCode: 416,
      headers: {'Content-Range': 'bytes */2048'},
    );
    final response = error.toResponse();
    expect(response.statusCode, equals(416));
    expect(response.headers['Content-Range'], equals('bytes */2048'));
    expect(response.headers['Content-Type'], contains('application/json'));
  });

  group('the four one-off exception types are AppErrors', () {
    // Before this, each of these was its own bare `implements Exception`
    // with no shared base, so one escaping a handler produced an unshaped
    // 500. They still exist as distinct types - callers branch on them
    // (prune a stale push token, forward a peer's status) - but they now
    // leave through the same exit as everything else.

    test('FederationHttpException reports the peer status as its own', () {
      final error = FederationHttpException(
        404,
        '{"error":"no such group"}',
        Uri.parse('https://peer.test/api/v1/s2s/groups/state'),
      );
      expect(error, isA<AppError>());
      expect(error.statusCode, equals(404));
      expect(error.toJson()['code'], equals('federation_error'));
      // The peer's raw body is kept for the caller that forwards it, but is
      // not what the normalized shape surfaces.
      expect(error.body, equals('{"error":"no such group"}'));
      expect(error.toJson()['error'], equals('Federated request failed'));
    });

    test('push failures are 502s that keep the upstream status separate', () {
      final missing = FcmTokenNotFoundException('{"error":"UNREGISTERED"}');
      expect(missing, isA<AppError>());
      expect(missing.statusCode, equals(502));
      expect(missing.toJson()['code'], equals('push_token_not_found'));

      final failed = FcmDeliveryException(429, 'quota');
      expect(failed.statusCode, equals(502), reason: 'ours, not FCM\'s');
      expect(failed.upstreamStatusCode, equals(429));
      expect(failed.toJson()['code'], equals('push_delivery_failed'));
    });

    test('SmsDeliveryException does not echo the gateway body', () {
      final error = SmsDeliveryException(500, 'Bad sender id');
      expect(error, isA<AppError>());
      expect(error.statusCode, equals(502));
      expect(error.upstreamStatusCode, equals(500));
      expect(
        error.toJson()['error'],
        equals('Failed to send verification SMS'),
      );
      expect(error.toJson()['code'], equals('sms_delivery_failed'));
    });
  });
}
