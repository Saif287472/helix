// FCM access tokens last an hour, and the backend used to read one out of
// an environment variable with a comment saying the caller should refresh
// it. For a long-running server that meant push worked until the token
// lapsed and then failed quietly.
//
// These tests cover the part that replaced it: when a cached token is
// reused, when it is thrown away, and what happens when Google says no.
// The exchange itself is injected, so none of this needs a network or a
// real service-account key.

import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/fcm_access_token.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceAccountFcmAccessToken', () {
    late DateTime now;
    late int exchanges;

    setUp(() {
      now = DateTime.utc(2026, 1, 1, 12);
      exchanges = 0;
    });

    ServiceAccountFcmAccessToken build({
      Duration validFor = const Duration(hours: 1),
      Duration refreshMargin = const Duration(minutes: 5),
      Future<FcmAccessToken> Function(Map<String, dynamic>)? exchange,
    }) {
      return ServiceAccountFcmAccessToken(
        serviceAccountJson: const {
          'client_email': 'svc@example.iam.gserviceaccount.com',
          'private_key': '-----BEGIN PRIVATE KEY-----',
        },
        clock: () => now,
        refreshMargin: refreshMargin,
        exchange:
            exchange ??
            (_) async {
              exchanges++;
              return FcmAccessToken(
                value: 'token-$exchanges',
                expiresAt: now.add(validFor),
              );
            },
      );
    }

    test('fetches once and reuses the token until it nears expiry', () async {
      final source = build();

      expect(await source.bearerToken(), equals('token-1'));
      now = now.add(const Duration(minutes: 30));
      expect(await source.bearerToken(), equals('token-1'));
      expect(exchanges, equals(1), reason: 'a valid token is not re-fetched');
    });

    test('refreshes before expiry, not after it', () async {
      // 54 minutes in, the token is still valid for 6 - but only 5 of those
      // are inside the margin, so it is still used.
      final source = build();
      await source.bearerToken();

      now = now.add(const Duration(minutes: 54));
      expect(await source.bearerToken(), equals('token-1'));
      expect(exchanges, equals(1));

      // 56 minutes in, it expires in 4. A request authorised with it could
      // easily arrive after it lapses, so it is replaced now rather than
      // being allowed to fail in flight.
      now = now.add(const Duration(minutes: 2));
      expect(await source.bearerToken(), equals('token-2'));
      expect(exchanges, equals(2));
    });

    test('an already-expired token is replaced', () async {
      final source = build();
      await source.bearerToken();

      now = now.add(const Duration(hours: 2));
      expect(await source.bearerToken(), equals('token-2'));
    });

    test('concurrent callers share one exchange', () async {
      // An incoming call pushes to every one of the callee's devices at
      // once. On a cold cache that must not become one token request per
      // device.
      var started = 0;
      final source = build(
        exchange: (_) async {
          started++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return FcmAccessToken(
            value: 'shared',
            expiresAt: now.add(const Duration(hours: 1)),
          );
        },
      );

      final tokens = await Future.wait([
        source.bearerToken(),
        source.bearerToken(),
        source.bearerToken(),
      ]);

      expect(tokens, equals(['shared', 'shared', 'shared']));
      expect(started, equals(1));
    });

    test('a failed exchange propagates and is retried, not cached', () async {
      var attempt = 0;
      final source = build(
        exchange: (_) async {
          attempt++;
          if (attempt == 1) throw SocketException('network down');
          return FcmAccessToken(
            value: 'recovered',
            expiresAt: now.add(const Duration(hours: 1)),
          );
        },
      );

      await expectLater(source.bearerToken(), throwsA(isA<SocketException>()));
      // The failure must not leave a permanently-poisoned source: a push
      // some minutes later has to be able to succeed on its own.
      expect(await source.bearerToken(), equals('recovered'));
    });

    test('a failure does not discard a token that is still good', () async {
      var attempt = 0;
      final source = build(
        exchange: (_) async {
          attempt++;
          if (attempt == 1) {
            return FcmAccessToken(
              value: 'first',
              expiresAt: now.add(const Duration(hours: 1)),
            );
          }
          throw SocketException('network down');
        },
      );

      expect(await source.bearerToken(), equals('first'));
      now = now.add(const Duration(minutes: 58));
      await expectLater(source.bearerToken(), throwsA(isA<SocketException>()));

      // Refresh failed, but the old token has not actually expired yet, so
      // stepping back inside its validity must still serve it rather than
      // having dropped it on the way.
      now = now.subtract(const Duration(minutes: 30));
      expect(await source.bearerToken(), equals('first'));
    });
  });

  group('readFcmServiceAccount', () {
    const validKey = {
      'type': 'service_account',
      'project_id': 'helix-test',
      'client_email': 'svc@helix-test.iam.gserviceaccount.com',
      'private_key': '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END-----\n',
    };

    test('an unset value means push is simply not configured', () {
      expect(readFcmServiceAccount(''), isNull);
      expect(readFcmServiceAccount('   '), isNull);
    });

    test('reads the key inline', () {
      final parsed = readFcmServiceAccount(jsonEncode(validKey));
      expect(parsed!['client_email'], equals(validKey['client_email']));
    });

    test('reads the key from a file path', () {
      final dir = Directory.systemTemp.createTempSync('helix_fcm_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/service-account.json')
        ..writeAsStringSync(jsonEncode(validKey));

      final parsed = readFcmServiceAccount(file.path);
      expect(parsed!['project_id'], equals('helix-test'));
    });

    test('a missing file is reported, not silently ignored', () {
      expect(
        () => readFcmServiceAccount('/nonexistent/service-account.json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('malformed JSON is reported', () {
      expect(
        () => readFcmServiceAccount('{"client_email": '),
        throwsA(isA<FormatException>()),
      );
    });

    test('the wrong kind of credential is caught at startup', () {
      // An OAuth client-secret file is valid JSON and a plausible thing to
      // grab from the Cloud console by mistake. It has no private_key, so
      // it can never sign a JWT - better to say so now than at 3am.
      final oauthClient = jsonEncode({
        'installed': {'client_id': 'x', 'client_secret': 'y'},
      });
      expect(
        () => readFcmServiceAccount(oauthClient),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('client_email'),
          ),
        ),
      );
    });
  });
}
