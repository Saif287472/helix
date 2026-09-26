import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/push_registration_service.dart';
import 'package:helix_remote/services/push_token_source.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'support/group_call_rest_stubs.dart';

/// The server half of push wake was built and tested long before the client
/// half existed: the backend enqueues a wake notification, finds no token
/// registered for the device, and completes the outbox entry silently. A
/// closed app therefore never rang.
///
/// These cover the three ways the client half dies quietly once it exists:
/// never registering, not re-registering after the SDK rotates the token,
/// and not deregistering before sign-out destroys the credentials needed to
/// do so.
void main() {
  late _FakeRestClient rest;

  setUp(() => rest = _FakeRestClient());

  PushRegistrationService serviceFor(PushTokenSource source) =>
      PushRegistrationService(source: source, restClient: () => rest);

  group('registration', () {
    test('registers the current token on start', () async {
      final service = serviceFor(_FakeSource(token: 'token-a'));
      await service.start();

      expect(service.isAvailable, isTrue);
      expect(rest.registered, equals(['token-a']));
      expect(rest.tokenTypes, equals(['FCM']));
    });

    test('a rotated token is re-registered', () async {
      final source = _FakeSource(token: 'token-a');
      final service = serviceFor(source);
      await service.start();
      expect(rest.registered, equals(['token-a']));

      source.rotate('token-b');
      await Future<void>.delayed(Duration.zero);

      expect(
        rest.registered,
        equals(['token-a', 'token-b']),
        reason:
            'a rotated token that is never re-registered is how push '
            'silently stops working weeks later',
      );
    });

    test('an unchanged token is not re-sent on every start', () async {
      final service = serviceFor(_FakeSource(token: 'token-a'));
      await service.start();
      await service.start();
      await service.start();

      expect(rest.registered, equals(['token-a']));
    });

    test('a registration failure leaves the token unregistered so the next '
        'start retries', () async {
      rest.failRegister = true;
      final service = serviceFor(_FakeSource(token: 'token-a'));
      await service.start();

      expect(service.registeredToken, isNull);

      rest.failRegister = false;
      await service.start();
      expect(service.registeredToken, equals('token-a'));
    });
  });

  group('push unavailable', () {
    test(
      'an unavailable source registers nothing and does not throw',
      () async {
        final service = serviceFor(const UnavailablePushTokenSource());
        await service.start();

        expect(service.isAvailable, isFalse);
        expect(rest.registered, isEmpty);
      },
    );

    test('a source that throws on init leaves the app usable', () async {
      final service = serviceFor(_ThrowingSource());
      await service.start();

      expect(
        service.isAvailable,
        isFalse,
        reason: 'a missing google-services.json must not take down startup',
      );
      expect(rest.registered, isEmpty);
    });

    test('a null token registers nothing', () async {
      final service = serviceFor(_FakeSource(token: null));
      await service.start();
      expect(rest.registered, isEmpty);
    });
  });

  group('deregistration', () {
    test('deregisters when a token was registered', () async {
      final service = serviceFor(_FakeSource(token: 'token-a'));
      await service.start();

      await service.deregister();

      expect(rest.deregisterCalls, equals(1));
      expect(service.registeredToken, isNull);
    });

    test('deregistering without a registration is a no-op', () async {
      final service = serviceFor(const UnavailablePushTokenSource());
      await service.start();

      await service.deregister();

      expect(rest.deregisterCalls, equals(0));
    });

    test('a failing deregistration still clears local state, so sign-out is '
        'never blocked by an unreachable server', () async {
      final service = serviceFor(_FakeSource(token: 'token-a'));
      await service.start();
      rest.failDeregister = true;

      await service.deregister();

      expect(service.registeredToken, isNull);
    });

    test(
      'dispose does not deregister — app shutdown must keep call wakes',
      () async {
        final service = serviceFor(_FakeSource(token: 'token-a'));
        await service.start();

        await service.dispose();

        expect(
          rest.deregisterCalls,
          equals(0),
          reason: 'closing the app must not stop it being woken for a call',
        );
      },
    );

    test('a rotation after dispose is ignored', () async {
      final source = _FakeSource(token: 'token-a');
      final service = serviceFor(source);
      await service.start();
      await service.dispose();

      source.rotate('token-b');
      await Future<void>.delayed(Duration.zero);

      expect(rest.registered, equals(['token-a']));
    });
  });
}

class _FakeSource implements PushTokenSource {
  _FakeSource({required this.token});

  String? token;
  final StreamController<String> _refreshes =
      StreamController<String>.broadcast();

  void rotate(String next) {
    token = next;
    // Guarded: a real SDK stream simply stops emitting once torn down, it
    // does not throw at the caller. Without this the post-dispose test would
    // fail on the fake rather than on the behaviour under test.
    if (!_refreshes.isClosed) _refreshes.add(next);
  }

  @override
  String get tokenType => 'FCM';

  @override
  Future<bool> initialize() async => true;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Future<void> dispose() async => _refreshes.close();
}

class _ThrowingSource implements PushTokenSource {
  @override
  String get tokenType => 'FCM';

  @override
  Future<bool> initialize() async => throw StateError('no firebase config');

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  final List<String> registered = [];
  final List<String> tokenTypes = [];
  int deregisterCalls = 0;
  bool failRegister = false;
  bool failDeregister = false;

  @override
  Future<Map<String, dynamic>> registerPushToken({
    required String pushToken,
    String tokenType = 'FCM',
  }) async {
    if (failRegister) throw StateError('offline');
    registered.add(pushToken);
    tokenTypes.add(tokenType);
    return {'status': 'registered'};
  }

  @override
  Future<Map<String, dynamic>> deregisterPushToken() async {
    deregisterCalls++;
    if (failDeregister) throw StateError('offline');
    return {'status': 'deregistered'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used by this test',
  );
}
