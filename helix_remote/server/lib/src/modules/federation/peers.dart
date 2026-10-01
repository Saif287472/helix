import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/federation/config.dart';
import 'package:helix_remote_server/src/modules/federation/data/federation_store.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:http/http.dart' as http;

/// The other server could not be reached (network, timeout, 5xx). Relays
/// retry; live operations report `federation_unavailable`.
final class PeerUnavailable implements Exception {
  const PeerUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'PeerUnavailable($reason)';
}

/// The other server answered with a protocol error.
final class PeerRefused implements Exception {
  const PeerRefused(this.error);

  final ApiError error;

  @override
  String toString() => 'PeerRefused(${error.code.wire})';
}

/// Who a domain's server is. The trust root is the domain itself: a peer's
/// key is whatever `https://<domain>/.well-known/helix-server` serves (TLS
/// authenticates the domain). Keys are cached for a day and re-fetched, at
/// most every ten minutes per domain, when a signature does not verify.
final class PeerDirectory {
  PeerDirectory({
    required this.config,
    required this.store,
    required this.db,
    required this.ephemeral,
    required this.clock,
    required this.httpClient,
    required this.log,
  });

  final FederationConfig config;
  final FederationStore store;
  final Db db;
  final EphemeralStore ephemeral;
  final Clock clock;
  final http.Client httpClient;
  final Log log;

  static const cacheLifetime = Duration(hours: 24);
  static const refreshGap = Duration(minutes: 10);
  static const downGap = Duration(minutes: 1);

  /// Refuses domains this server must not talk to.
  void checkAllowed(String domain) {
    if (!AccountAddress.isValidDomain(domain) ||
        domain == config.localDomain ||
        (config.allow.isNotEmpty && !config.allow.contains(domain))) {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: 'that server is not a federation peer',
      );
    }
  }

  /// The peer for [domain], from the cache or its well-known document.
  /// With [refresh], re-fetches (rate-limited) even if cached.
  Future<Peer> resolve(String domain, {bool refresh = false}) async {
    checkAllowed(domain);
    final cached = await store.peer(db, domain);
    final fresh =
        cached != null &&
        clock.now().difference(cached.fetchedAt) < cacheLifetime;
    if (cached != null && fresh && !refresh) return cached;
    if (cached != null && refresh) {
      final allowed = await ephemeral.putIfAbsent(
        'fed:refresh:$domain',
        '1',
        refreshGap,
      );
      if (!allowed) return cached;
    }
    // A domain that just failed is not fetched again for a minute, so
    // forged S2S headers cannot make this server hammer a domain.
    if (cached == null && await ephemeral.get('fed:down:$domain') != null) {
      throw const PeerUnavailable('recently unreachable');
    }
    final Peer fetched;
    try {
      fetched = await _fetch(domain);
    } on PeerUnavailable {
      if (cached != null) return cached;
      await ephemeral.put('fed:down:$domain', '1', downGap);
      rethrow;
    }
    if (cached != null &&
        !constantTimeEquals(cached.publicKey, fetched.publicKey)) {
      log.warn('peer_key_changed', {'peer': domain});
    }
    await store.savePeer(db, fetched);
    return fetched;
  }

  Future<Peer> _fetch(String domain) async {
    final uri = Uri.parse(
      '${config.scheme}://$domain/.well-known/helix-server',
    );
    await checkTarget(uri);
    final http.Response response;
    try {
      response = await httpClient
          .get(uri, headers: {'accept': 'application/json'})
          .timeout(config.timeout);
    } on Object catch (e) {
      throw PeerUnavailable(e.runtimeType.toString());
    }
    if (response.statusCode != 200) {
      throw PeerUnavailable('identity document status ${response.statusCode}');
    }
    final ServerIdentityDocument doc;
    try {
      doc = ServerIdentityDocument.fromJson(JsonReader.decode(response.body));
    } on FormatException {
      throw const PeerUnavailable('malformed identity document');
    }
    final apiBase = Uri.tryParse(doc.apiBase);
    final key = _decodeKey(doc.publicKey);
    final apiAuthority = apiBase == null
        ? null
        : (apiBase.hasPort
              ? '${apiBase.host.toLowerCase()}:${apiBase.port}'
              : apiBase.host.toLowerCase());
    // The document must describe this domain and keep its API on it.
    if (doc.serverId != domain ||
        key == null ||
        apiBase == null ||
        apiBase.scheme != config.scheme ||
        apiAuthority != domain) {
      throw const PeerUnavailable('identity document does not match');
    }
    var base = doc.apiBase;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Peer(
      domain: domain,
      publicKey: key,
      apiBase: base,
      fetchedAt: clock.now(),
    );
  }

  static Uint8List? _decodeKey(String encoded) {
    try {
      final key = decodeBytes(encoded);
      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    }
  }

  /// Refuses targets that resolve to link-local addresses (cloud metadata
  /// services) and, unless [FederationConfig.allowPrivate], loopback and
  /// private ones: a domain in an account address is user input.
  Future<void> checkTarget(Uri uri) async {
    List<InternetAddress> addresses;
    final literal = InternetAddress.tryParse(uri.host);
    if (literal != null) {
      addresses = [literal];
    } else {
      try {
        addresses = await InternetAddress.lookup(uri.host);
      } on SocketException {
        throw const PeerUnavailable('cannot resolve');
      }
    }
    for (final address in addresses) {
      if (address.isLinkLocal || _isUnspecified(address)) {
        throw const ApiError(
          ErrorCode.federationUnavailable,
          message: 'that server is not a federation peer',
        );
      }
      if (!config.allowPrivate && (address.isLoopback || _isPrivate(address))) {
        throw const ApiError(
          ErrorCode.federationUnavailable,
          message: 'that server is not a federation peer',
        );
      }
    }
  }

  static bool _isUnspecified(InternetAddress a) =>
      a.rawAddress.every((b) => b == 0);

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    // fc00::/7 unique local.
    return (b[0] & 0xfe) == 0xfc;
  }
}

/// Signed requests to other servers.
final class FederationClient {
  FederationClient({
    required this.config,
    required this.peers,
    required this.signer,
    required this.clock,
    required this.httpClient,
  });

  final FederationConfig config;
  final PeerDirectory peers;
  final Ed25519Signer signer;
  final Clock clock;
  final http.Client httpClient;

  /// The S2S headers for a request (also used by tests).
  Future<Map<String, String>> sign(
    String method,
    String pathAndQuery,
    List<int> body,
  ) async {
    final ts = clock.now().millisecondsSinceEpoch;
    final signature = await signer.sign(
      s2sSigningInput(
        server: config.localDomain,
        timestampMs: ts,
        method: method,
        pathAndQuery: pathAndQuery,
        body: body,
      ),
    );
    return {
      HelixHeaders.s2sServer: config.localDomain,
      HelixHeaders.s2sTimestamp: '$ts',
      HelixHeaders.s2sSignature: encodeBytes(signature),
    };
  }

  /// Sends a signed request to [domain]; the JSON answer (null for 204).
  /// Throws [PeerRefused] for a protocol error, [PeerUnavailable] when the
  /// server cannot be reached or fails.
  Future<JsonReader?> call(
    String domain,
    String method,
    String pathAndQuery, {
    JsonMap? body,
  }) async {
    final peer = await peers.resolve(domain);
    final uri = Uri.parse('${peer.apiBase}$pathAndQuery');
    await peers.checkTarget(uri);
    final bytes = body == null
        ? Uint8List(0)
        : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    final signedPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final request = http.Request(method, uri)
      ..headers.addAll({
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
        ...await sign(method, signedPath, bytes),
      })
      ..bodyBytes = bytes;
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(config.timeout),
      ).timeout(config.timeout);
    } on Object catch (e) {
      throw PeerUnavailable(e.runtimeType.toString());
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return response.body.isEmpty ? null : JsonReader.decode(response.body);
    }
    if (status >= 500 && status != 502) {
      throw PeerUnavailable('status $status');
    }
    try {
      throw PeerRefused(ApiError.fromJson(JsonReader.decode(response.body)));
    } on FormatException {
      throw PeerUnavailable('status $status');
    }
  }
}
