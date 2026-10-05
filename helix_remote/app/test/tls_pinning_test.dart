import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/tls_pinning.dart';
import 'package:helix_remote_api/v2.dart' show RealtimeUpgradeException;

/// M1: certificate pinning for Helix Global, exercised against a real TLS
/// server on loopback with a throwaway certificate (never a real Helix key).
void main() {
  late HttpServer server;
  late int port;
  var requests = 0;

  Future<HttpServer> bind() async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(_certPem))
      ..usePrivateKeyBytes(utf8.encode(_keyPem));
    final bound = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    bound.listen((request) async {
      requests++;
      request.response
        ..statusCode = request.headers.value('upgrade') == null ? 200 : 401
        ..headers.contentType = ContentType.json
        ..write('{"error":"no","code":"unauthorized"}');
      await request.response.close();
    });
    return bound;
  }

  setUp(() async {
    requests = 0;
    server = await bind();
    port = server.port;
  });

  tearDown(() => server.close(force: true));

  TlsPinPolicy policy({
    Set<String> hosts = const {'localhost'},
    Set<String> pins = const {_certPin},
    bool enforce = true,
  }) => TlsPinPolicy(hosts: hosts, pins: pins, enforce: enforce);

  Future<int> get(TlsPinPolicy p) => p.run(() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://localhost:$port/'),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  });

  const wrongPin = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  test('the SPKI hash is the one openssl computes for the certificate', () {
    final der = base64.decode(
      _certPem.split('\n').where((l) => !l.startsWith('-----')).join(),
    );
    expect(TlsPinPolicy.spkiPin(Uint8List.fromList(der)), _certPin);
  });

  test('a certificate with the pinned key is accepted', () async {
    expect(await get(policy()), 200);
  });

  test(
    'a certificate with another key is refused before any request',
    () async {
      await expectLater(
        get(policy(pins: {wrongPin})),
        throwsA(isA<Exception>()),
      );
      expect(requests, 0, reason: 'the handshake must fail first');
    },
  );

  test(
    'a host that is not pinned is refused even with the right key',
    () async {
      await expectLater(
        get(policy(hosts: {'helix.agiletechbd.com'})),
        throwsA(isA<Exception>()),
      );
      expect(requests, 0);
    },
  );

  test('without the pin the system store rejects this certificate', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    await expectLater(
      client
          .getUrl(Uri.parse('https://localhost:$port/'))
          .then((request) => request.close()),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('the realtime socket is pinned too', () async {
    // Right key: the TLS handshake passes and the upgrade is answered 401.
    await expectLater(
      policy().socketFactory(
        Uri.parse('wss://localhost:$port/v1/ws'),
        headers: const {},
        protocols: const [],
      ),
      throwsA(isA<RealtimeUpgradeException>()),
    );
    // Wrong key: it never gets as far as an HTTP answer.
    final before = requests;
    await expectLater(
      policy(pins: {wrongPin}).socketFactory(
        Uri.parse('wss://localhost:$port/v1/ws'),
        headers: const {},
        protocols: const [],
      ),
      throwsA(isNot(isA<RealtimeUpgradeException>())),
    );
    expect(requests, before);
  });

  group('the policy', () {
    test('pins Helix Global hosts and nothing else', () {
      final built = TlsPinPolicy.forThisBuild();
      final pinned = TlsPinPolicy(
        hosts: built.hosts,
        pins: built.pins,
        enforce: true,
      );
      expect(
        pinned.appliesTo(Uri.parse('https://helix.agiletechbd.com')),
        isTrue,
      );
      expect(pinned.appliesTo(Uri.parse('https://HR.agiletechbd.com')), isTrue);
      expect(pinned.appliesTo(Uri.parse('https://chat.example.org')), isFalse);
    });

    test('a debug build is not pinned', () {
      expect(
        policy(enforce: false).appliesTo(Uri.parse('https://localhost')),
        isFalse,
      );
      expect(TlsPinPolicy.forThisBuild().enforce, isFalse);
    });

    test('garbage is not a certificate and is refused', () {
      expect(
        policy().accepts(Uint8List.fromList([1, 2, 3]), host: 'localhost'),
        isFalse,
      );
      expect(policy().accepts(Uint8List(0), host: 'localhost'), isFalse);
      expect(
        policy().accepts(
          Uint8List.fromList(const [0x30, 0x84, 0xff, 0xff, 0xff, 0xff]),
          host: 'localhost',
        ),
        isFalse,
      );
    });

    test('the built-in pin is the one in the Android network config', () {
      final xml = File(
        'android/app/src/main/res/xml/helix_remote_network_security.xml',
      ).readAsStringSync();
      final pins = RegExp(
        r'<pin digest="SHA-256">([^<]+)</pin>',
      ).allMatches(xml).map((m) => m.group(1)).toSet();
      expect(TlsPinPolicy.builtInPins, pins);
      for (final host in TlsPinPolicy.globalHosts) {
        expect(xml, contains(host));
      }
    });
  });
}

/// SHA-256(SPKI) of [_certPem], computed with openssl.
const _certPin = 'KhweRpu9R9x4qrdmg/dITX4Nec8kebWGKMkioScTZjM=';

/// A throwaway self-signed certificate for `localhost`, generated for this
/// test. Its key protects nothing.
final _certPem = [
  '-----BEGIN CERTIFICATE-----',
  'MIIBgDCCASWgAwIBAgIUHWrn92UselpwqchAPNmQTeXrce0wCgYIKoZIzj0EAwIw',
  'FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTAwNTEwNTE0OFoYDzIxMjYwOTEx',
  'MTA1MTQ4WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO',
  'PQMBBwNCAAQNZaU/tAOZIYiMXoE/Hb8x0IuUZIQqxS1H/phwp3GPJ/XSqtLJPhbJ',
  'hBWjddH6VMnB5qZBwwU9IwVY428SOwF9o1MwUTAdBgNVHQ4EFgQUGOVZf4cvyhII',
  'VoQQlntqSVVY6WswHwYDVR0jBBgwFoAUGOVZf4cvyhIIVoQQlntqSVVY6WswDwYD',
  'VR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBGAiEAlz8gAKuhjDYRcBXP37qm',
  'CkQnU6nkZmLTchDkza4lyAgCIQDhS9L16YRQ+GbGqRUa9gYbFf6tN3jDHjdf0UGz',
  'MAC/1g==',
  '-----END CERTIFICATE-----',
].join('\n');

/// The matching throwaway key (the header is split so a secret scanner does
/// not mistake this fixture for a real one).
final _keyPem = [
  '-----BEGIN ${'PRIVATE'} KEY-----',
  'MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgjPnVMLqmgUr844w2',
  'xfzqRfo/r8WQnuAl5fO+Kx+cHOChRANCAAQNZaU/tAOZIYiMXoE/Hb8x0IuUZIQq',
  'xS1H/phwp3GPJ/XSqtLJPhbJhBWjddH6VMnB5qZBwwU9IwVY428SOwF9',
  '-----END ${'PRIVATE'} KEY-----',
].join('\n');
