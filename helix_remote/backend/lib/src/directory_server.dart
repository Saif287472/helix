import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/federation_verifier.dart';

class FederationDirectoryServer {
  FederationDirectoryServer({
    FederationDomainVerifier? verifier,
  }) : _verifier = verifier ?? FederationDomainVerifier();

  final FederationDomainVerifier _verifier;
  final Map<String, Map<String, dynamic>> _servers = {}; // key: domain
  final Map<String, String> _userDomains =
      {}; // key: user@domain, value: domain
  HttpServer? _server;
  HttpServer? get httpServer => _server;

  Router get router {
    final router = Router();
    router.post('/api/v1/directory/register', _registerHandler);
    router.get('/api/v1/directory/lookup', _lookupHandler);
    return router;
  }

  Future<Response> _registerHandler(Request request) async {
    final senderId = request.headers['X-Helix-S2S-Server-Id'];
    final pubKeyB64 = request.headers['X-Helix-S2S-Public-Key'];
    final timestampStr = request.headers['X-Helix-S2S-Timestamp'];
    final signatureB64 = request.headers['X-Helix-S2S-Signature'];

    if (senderId == null ||
        pubKeyB64 == null ||
        timestampStr == null ||
        signatureB64 == null) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized: Missing S2S headers'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final timestamp = int.tryParse(timestampStr);
    if (timestamp == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Bad Request: Invalid timestamp'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - timestamp).abs() > 300000) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized: Signature expired'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final bodyStr = await request.readAsString();
    final signedPayload = S2SSignatures.signedPayload(
      serverId: senderId,
      timestamp: timestamp,
      path: request.requestedUri.path,
      body: bodyStr,
    );
    final payloadBytes = utf8.encode(signedPayload);

    try {
      final pubBytes = base64Decode(pubKeyB64);
      final sigBytes = base64Decode(signatureB64);

      final ed25519 = crypto.Ed25519();
      final publicKey = crypto.SimplePublicKey(
        pubBytes,
        type: crypto.KeyPairType.ed25519,
      );
      final signature = crypto.Signature(sigBytes, publicKey: publicKey);

      final isValid = await ed25519.verify(payloadBytes, signature: signature);
      if (!isValid) {
        return Response(
          401,
          body: jsonEncode({'error': 'Unauthorized: Invalid signature'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized: Verification failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final body = jsonDecode(bodyStr) as Map<String, dynamic>;
    final domain = body['domain'] as String?;
    final address = body['address'] as String?;
    final users = (body['users'] as List?)?.cast<String>() ?? const <String>[];

    if (domain == null || address == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing domain or address'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final isDomainVerified = await _verifier.verifyDomainKey(
      domain: domain,
      expectedPublicKeyB64: pubKeyB64,
      expectedServerId: senderId,
    );
    if (!isDomainVerified) {
      return Response(
        403,
        body: jsonEncode({
          'error': 'Forbidden: Cryptographic domain ownership verification failed for $domain',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final existing = _servers[domain];
    if (existing != null && existing['server_public_key'] != pubKeyB64) {
      return Response(
        409,
        body: jsonEncode({
          'error':
              'Conflict: Domain already registered with a different public key',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    _servers[domain] = {
      'server_id': senderId,
      'server_public_key': pubKeyB64,
      'address': address,
      'users': users,
    };
    for (final user in users) {
      _userDomains[user.toLowerCase()] = domain;
    }

    return Response.ok(
      jsonEncode({'message': 'Server registered successfully'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _lookupHandler(Request request) {
    final requestedDomain = request.url.queryParameters['domain'];
    final accountId = request.url.queryParameters['account_id']?.toLowerCase();
    final domain =
        requestedDomain ?? (accountId == null ? null : _userDomains[accountId]);
    if (domain == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing domain or account_id parameter'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final meta = _servers[domain];
    if (meta == null) {
      return Response.notFound(
        jsonEncode({'error': 'Domain not found in directory'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(meta),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<void> start(String host, int port) async {
    final handler = const Pipeline().addHandler(router.call);
    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
