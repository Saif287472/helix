import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/server_identity.dart';

class S2SSignatures {
  static String bodyHash(String body) =>
      crypto_pkg.sha256.convert(utf8.encode(body)).toString();

  static String signedPayload({
    required String serverId,
    required int timestamp,
    required String path,
    required String body,
  }) {
    return '$serverId|$timestamp|$path|${bodyHash(body)}';
  }

  static Future<Map<String, String>> signHeaders({
    required ServerIdentity identity,
    required String path,
    String body = '',
  }) async {
    final publicKey = await identity.serverKeyPair.extractPublicKey();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = signedPayload(
      serverId: identity.serverId,
      timestamp: timestamp,
      path: path,
      body: body,
    );
    final signature = await crypto.Ed25519().sign(
      utf8.encode(payload),
      keyPair: identity.serverKeyPair,
    );
    return {
      'X-Helix-S2S-Server-Id': identity.serverId,
      'X-Helix-S2S-Public-Key': base64Encode(publicKey.bytes),
      'X-Helix-S2S-Timestamp': '$timestamp',
      'X-Helix-S2S-Signature': base64Encode(signature.bytes),
    };
  }
}

class FederationClient {
  FederationClient({
    required this.db,
    required this.identity,
    required this.directoryUrl,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final BackendDatabase db;
  final ServerIdentity identity;
  final String directoryUrl;
  final HttpClient _httpClient;

  Future<Map<String, dynamic>> registerDirectory({
    required String domain,
    required String address,
    required List<String> users,
  }) async {
    if (directoryUrl.trim().isEmpty) {
      throw StateError('Federation directory URL is not configured');
    }
    final body = jsonEncode({
      'domain': domain,
      'address': address,
      'users': users,
    });
    final uri = Uri.parse(directoryUrl).resolve('/api/v1/directory/register');
    final headers = await S2SSignatures.signHeaders(
      identity: identity,
      path: uri.path,
      body: body,
    );
    final response = await _requestJson(
      method: 'POST',
      uri: uri,
      body: body,
      headers: headers,
    );
    db.upsertFederationServer(
      serverId: identity.serverId,
      domain: domain,
      publicKey: base64Encode(
        (await identity.serverKeyPair.extractPublicKey()).bytes,
      ),
      address: address,
      trustSource: 'self',
    );
    return response;
  }

  Future<Map<String, dynamic>> lookupDomain(String domain) async {
    final cached = db.getFederationServerByDomain(domain);
    if (cached != null && (cached['address'] as String?)?.isNotEmpty == true) {
      return cached;
    }
    if (directoryUrl.trim().isEmpty) {
      throw StateError('Federation directory URL is not configured');
    }
    final uri = Uri.parse(
      directoryUrl,
    ).resolve('/api/v1/directory/lookup?domain=$domain');
    final response = await _requestJson(method: 'GET', uri: uri);
    db.upsertFederationServer(
      serverId: response['server_id'] as String,
      domain: domain,
      publicKey: response['server_public_key'] as String,
      address: response['address'] as String,
      trustSource: 'directory',
    );
    return db.getFederationServerByDomain(domain)!;
  }

  Future<Map<String, dynamic>> fetchRemotePrekeyBundle(String accountId) async {
    final domain = _domainFromAccountId(accountId);
    if (domain == null) {
      throw ArgumentError('Remote account must be qualified as user@domain');
    }
    final server = await lookupDomain(domain);
    final address = server['address'] as String;
    final uri = Uri.parse(address).resolve(
      '/api/v1/s2s/prekeys/bundle?account_id=${Uri.encodeQueryComponent(accountId)}',
    );
    await _rejectUnsafeFederationTarget(uri);
    final headers = await S2SSignatures.signHeaders(
      identity: identity,
      path: uri.path,
    );
    return _requestJson(method: 'GET', uri: uri, headers: headers);
  }

  Future<Map<String, dynamic>> proxyMessage({
    required String remoteAccountId,
    required Map<String, dynamic> body,
  }) async {
    final domain = _domainFromAccountId(remoteAccountId);
    if (domain == null) {
      throw ArgumentError('Remote account must be qualified as user@domain');
    }
    final server = await lookupDomain(domain);
    final address = server['address'] as String;
    final encodedBody = jsonEncode(body);
    final uri = Uri.parse(address).resolve('/api/v1/s2s/messages/proxy');
    await _rejectUnsafeFederationTarget(uri);
    final headers = await S2SSignatures.signHeaders(
      identity: identity,
      path: uri.path,
      body: encodedBody,
    );
    return _requestJson(
      method: 'POST',
      uri: uri,
      body: encodedBody,
      headers: headers,
    );
  }

  /// Batched variant of [proxyMessage]: delivers every envelope destined for
  /// `domain` in a single signed request instead of one HTTP round-trip per
  /// recipient device (Milestone 4.3 group fan-out).
  Future<Map<String, dynamic>> proxyMessageBatch({
    required String domain,
    required List<Map<String, dynamic>> envelopes,
  }) async {
    return _postToDomain(
      domain: domain,
      path: '/api/v1/s2s/messages/proxy-batch',
      body: {'envelopes': envelopes},
    );
  }

  /// Relays a batch of durable conversation events (edits/reactions/receipts)
  /// or best-effort ones (typing) to federated members hosted on `domain`.
  Future<Map<String, dynamic>> relayConversationEventBatch({
    required String domain,
    required List<Map<String, dynamic>> events,
  }) async {
    return _postToDomain(
      domain: domain,
      path: '/api/v1/s2s/conversations/event-relay-batch',
      body: {'events': events},
    );
  }

  /// Delivers a batch of pairwise-wrapped group epoch keys to devices hosted
  /// on `domain` (Milestone 4.2).
  Future<Map<String, dynamic>> deliverEpochKeyBatch({
    required String domain,
    required List<Map<String, dynamic>> deliveries,
  }) async {
    return _postToDomain(
      domain: domain,
      path: '/api/v1/s2s/groups/epoch-key/deliver-batch',
      body: {'deliveries': deliveries},
    );
  }

  /// Pushes a full group state snapshot (roster + optional pending invites)
  /// from the group's home server to a participant server (Milestone 4.1).
  Future<Map<String, dynamic>> syncGroupState({
    required String domain,
    required Map<String, dynamic> body,
  }) async {
    return _postToDomain(
      domain: domain,
      path: '/api/v1/s2s/groups/sync',
      body: body,
    );
  }

  /// Pulls the current group state snapshot from the home server — used by a
  /// participant to self-heal if it suspects its mirror has drifted.
  Future<Map<String, dynamic>> fetchGroupState({
    required String domain,
    required String groupId,
  }) async {
    final server = await lookupDomain(domain);
    final address = server['address'] as String;
    final uri = Uri.parse(address).resolve(
      '/api/v1/s2s/groups/state?group_id=${Uri.encodeQueryComponent(groupId)}',
    );
    await _rejectUnsafeFederationTarget(uri);
    final headers = await S2SSignatures.signHeaders(
      identity: identity,
      path: uri.path,
    );
    return _requestJson(method: 'GET', uri: uri, headers: headers);
  }

  /// A participant server asking the group's home server to apply an admin
  /// action (invite, role change, leave, etc.) on its behalf, since only the
  /// home server may authoritatively mutate group membership/roles.
  Future<Map<String, dynamic>> proxyGroupAction({
    required String homeDomain,
    required String groupId,
    required String action,
    required String actingAccountId,
    required Map<String, dynamic> payload,
  }) async {
    return _postToDomain(
      domain: homeDomain,
      path: '/api/v1/s2s/groups/action',
      body: {
        'group_id': groupId,
        'action': action,
        'acting_account_id': actingAccountId,
        'payload': payload,
      },
    );
  }

  /// Milestone 5.1: relays a single WebRTC call signal (offer/answer/ice/
  /// decline/busy/cancel/end) to the domain hosting the other party. Calls
  /// are bilateral (no home-server-authority concept, unlike groups) — each
  /// server just forwards signals to whichever domain the *other* leg of
  /// the call lives on, mirroring [proxyMessage]'s bilateral relay pattern.
  Future<Map<String, dynamic>> proxyCallSignal({
    required String domain,
    required String senderAccountId,
    required String senderDeviceId,
    required Map<String, dynamic> signal,
    String? requestId,
  }) async {
    return _postToDomain(
      domain: domain,
      path: '/api/v1/s2s/calls/signal',
      body: {
        'sender_account_id': senderAccountId,
        'sender_device_id': senderDeviceId,
        'signal': signal,
        if (requestId != null) 'request_id': requestId,
      },
    );
  }

  Future<Map<String, dynamic>> _postToDomain({
    required String domain,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final server = await lookupDomain(domain);
    final address = server['address'] as String;
    final encodedBody = jsonEncode(body);
    final uri = Uri.parse(address).resolve(path);
    await _rejectUnsafeFederationTarget(uri);
    final headers = await S2SSignatures.signHeaders(
      identity: identity,
      path: uri.path,
      body: encodedBody,
    );
    return _requestJson(
      method: 'POST',
      uri: uri,
      body: encodedBody,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required Uri uri,
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = switch (method) {
      'GET' => await _httpClient.getUrl(uri),
      'POST' => await _httpClient.postUrl(uri),
      _ => throw ArgumentError('Unsupported HTTP method: $method'),
    };
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FederationHttpException(response.statusCode, responseBody, uri);
    }
    if (responseBody.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Rejects federation requests whose resolved target is a link-local
  /// address (RFC 3927 `169.254.0.0/16`, RFC 4291 `fe80::/10`) — the address
  /// class cloud providers expose their instance-metadata service on (e.g.
  /// `169.254.169.254`). A peer's `address` is learned from the federation
  /// directory, which may be compromised or malicious, so it must not be
  /// trusted enough to reach a class of address with no legitimate use as a
  /// federation partner. Loopback/private ranges are deliberately NOT
  /// blocked here: this deployment legitimately federates multiple
  /// self-hosted servers on private or same-host addresses.
  Future<void> _rejectUnsafeFederationTarget(Uri uri) async {
    final host = uri.host;
    List<InternetAddress> candidates;
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      candidates = [literal];
    } else {
      try {
        candidates = await InternetAddress.lookup(host);
      } catch (_) {
        // Let the actual request surface the DNS failure naturally.
        return;
      }
    }
    for (final addr in candidates) {
      if (addr.isLinkLocal) {
        throw FederationHttpException(
          403,
          'SSRF blocked: federation target $host resolves to a link-local address',
          uri,
        );
      }
    }
  }

  String? _domainFromAccountId(String accountId) => domainOf(accountId);

  /// Extracts the lowercased domain from a `user@domain` qualified account
  /// id, or null if `accountId` isn't qualified. Shared parsing logic for
  /// grouping federated recipients/members by destination server.
  static String? domainOf(String accountId) {
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return null;
    return accountId.substring(at + 1).toLowerCase();
  }
}

/// Thrown when a signed S2S HTTP request receives a non-2xx response.
/// Carries the remote status code so callers can map it back to an
/// appropriate local response instead of always surfacing a generic error.
class FederationHttpException implements Exception {
  FederationHttpException(this.statusCode, this.body, this.uri);

  final int statusCode;
  final String body;
  final Uri uri;

  @override
  String toString() => 'FederationHttpException($statusCode) $uri: $body';
}
