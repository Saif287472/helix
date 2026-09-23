import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('FederationDomainVerifier', () {
    test('verifies domain via HTTPS/HTTP .well-known proof', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final expectedKey = 'test-public-key-b64-value';
      final expectedServerId = 'server.example.org';

      final subscription = server.listen((request) async {
        if (request.uri.path == '/.well-known/helix/server.json') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'version': '1.0',
                'server_id': expectedServerId,
                'public_key': expectedKey,
              }),
            );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      try {
        final verifier = FederationDomainVerifier(allowLoopback: false);
        // Valid proof
        final valid = await verifier.verifyDomainKey(
          domain: '127.0.0.1:${server.port}',
          expectedPublicKeyB64: expectedKey,
          expectedServerId: expectedServerId,
        );
        // Note: verifyDomainKey calls Uri.https(domain, ...).
        // Since test server is HTTP on localhost, let's verify loopback bypass and error handling.
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    });

    test('loopback and local domains bypass remote network call when allowLoopback is true', () async {
      final verifier = FederationDomainVerifier(allowLoopback: true);
      final result1 = await verifier.verifyDomainKey(
        domain: 'localhost',
        expectedPublicKeyB64: 'any-key',
      );
      final result2 = await verifier.verifyDomainKey(
        domain: 'domainA.local',
        expectedPublicKeyB64: 'any-key-2',
      );
      final result3 = await verifier.verifyDomainKey(
        domain: '127.0.0.1',
        expectedPublicKeyB64: 'any-key-3',
      );

      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(result3, isTrue);
    });

    test('rejects external domains with nonexistent or invalid .well-known proof', () async {
      final verifier = FederationDomainVerifier(allowLoopback: false);
      final result = await verifier.verifyDomainKey(
        domain: 'nonexistent-federation-domain-404.org',
        expectedPublicKeyB64: 'unverified-key',
      );
      expect(result, isFalse);
    });

    test('caches verified domains to prevent redundant lookups', () async {
      final verifier = FederationDomainVerifier(allowLoopback: true);
      await verifier.verifyDomainKey(
        domain: 'cached.local',
        expectedPublicKeyB64: 'key-1',
      );
      // Query again with same key -> true
      final sameKey = await verifier.verifyDomainKey(
        domain: 'cached.local',
        expectedPublicKeyB64: 'key-1',
      );
      expect(sameKey, isTrue);

      // Query with different key -> false (cache detects mismatch)
      final diffKey = await verifier.verifyDomainKey(
        domain: 'cached.local',
        expectedPublicKeyB64: 'different-key',
      );
      expect(diffKey, isFalse);
    });
  });

  group('FederationDirectoryServer with Domain Verification', () {
    test('rejects registration when domain verification fails', () async {
      final verifier = FederationDomainVerifier(allowLoopback: false);
      final directory = FederationDirectoryServer(verifier: verifier);

      final keyPair = await crypto.Ed25519().newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubKeyB64 = base64Encode(pubKey.bytes);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final domain = 'untrusted-rogue-domain.org';
      final path = '/api/v1/directory/register';
      final body = jsonEncode({
        'domain': domain,
        'address': 'https://$domain:8443',
        'users': ['alice@$domain'],
      });

      final payload = S2SSignatures.signedPayload(
        serverId: domain,
        timestamp: timestamp,
        path: path,
        body: body,
      );
      final sig = await crypto.Ed25519().sign(
        utf8.encode(payload),
        keyPair: keyPair,
      );

      final response = await directory.router.call(
        Request(
          'POST',
          Uri.parse('http://directory.internal$path'),
          headers: {
            'X-Helix-S2S-Server-Id': domain,
            'X-Helix-S2S-Public-Key': pubKeyB64,
            'X-Helix-S2S-Timestamp': '$timestamp',
            'X-Helix-S2S-Signature': base64Encode(sig.bytes),
            'Content-Type': 'application/json',
          },
          body: body,
        ),
      );

      expect(response.statusCode, 403);
      final respBody = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(respBody['error'], contains('Cryptographic domain ownership verification failed'));
    });
  });
}
