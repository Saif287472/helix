import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/kernel/relay.dart';
import 'package:helix_remote_server/src/modules/calls/api.dart';
import 'package:helix_remote_server/src/modules/federation/config.dart';
import 'package:helix_remote_server/src/modules/federation/data/federation_store.dart';
import 'package:helix_remote_server/src/modules/federation/peers.dart';
import 'package:helix_remote_server/src/modules/groups/api.dart';
import 'package:helix_remote_server/src/modules/keys/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// Server-to-server federation (REST_V2.md "federation"): this server's
/// Ed25519 identity, peer discovery, signed requests in both directions,
/// and relays for messages, key bundles and call signals. Accounts on other
/// servers are `uuid@domain`. Schema `federation`.
///
/// Groups federate through their home server (groups module,
/// `federation.dart`); this module carries its S2S calls.
final class FederationModule extends ModuleBase
    implements ProvidesAuthentication {
  FederationModule(
    super.context, {
    required this.ops,
    required this.messaging,
    required this.keys,
    required this.calls,
    required this.groups,
    http.Client? httpClient,
  }) : config = FederationConfig.from(context.config),
       _httpOverride = httpClient {
    _store = FederationStore(schema);
    peers = PeerDirectory(
      config: config,
      store: _store,
      db: context.db,
      ephemeral: context.ephemeral,
      clock: context.clock,
      httpClient: _http,
      log: log,
    );
    authenticator = _ServerAuthenticator(this);
    final relay = _Relay(this);
    messaging.setRelay(relay);
    keys.setRemoteSource(relay);
    calls.setRelay(relay);
    groups.setRelay(relay);
  }

  final OpsApi ops;
  final MessagingApi messaging;
  final KeysApi keys;
  final CallsApi calls;
  final GroupsApi groups;
  final FederationConfig config;
  final http.Client? _httpOverride;
  late final http.Client _http = _httpOverride ?? federationHttpClient(config);
  late final FederationStore _store;
  late final PeerDirectory peers;

  /// Ready after [start].
  late final FederationClient client;
  late final Ed25519Signer _signer;

  @override
  late final Authenticator authenticator;

  static const relayJob = 'federation.relay';

  static final _identityLimit = RateLimitPolicy.per(
    'federation.identity',
    120,
    const Duration(minutes: 1),
  );
  static final _messagesLimit = RateLimitPolicy.per(
    'federation.messages',
    3000,
    const Duration(minutes: 1),
  );
  static final _keysLimit = RateLimitPolicy.per(
    'federation.keys',
    600,
    const Duration(minutes: 1),
  );
  static final _keysTargetLimit = RateLimitPolicy.per(
    'federation.keys_target',
    30,
    const Duration(minutes: 1),
  );
  static final _signalsLimit = RateLimitPolicy.per(
    'federation.signals',
    1200,
    const Duration(minutes: 1),
  );

  @override
  String get name => 'federation';

  @override
  List<Migration> get migrations => federationMigrations;

  @override
  Map<String, JobHandler> get jobs => {relayJob: _retryRelay};

  @override
  Future<void> start() async {
    final seed = await _store.setting(
      context.db,
      'server_key',
      () => randomBytes(32),
    );
    _signer = await Ed25519Signer.fromSeed(seed);
    client = FederationClient(
      config: config,
      peers: peers,
      signer: _signer,
      clock: context.clock,
      httpClient: _http,
    );
  }

  @override
  Future<void> stop() async {
    _http.close();
  }

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.serverIdentity, _identity, rateLimit: _identityLimit)
      ..add(
        name,
        Routes.s2sMessages,
        _inboundMessages,
        rateLimit: _messagesLimit,
        maxBodyBytes: 8 * 1024 * 1024,
      )
      ..add(name, Routes.s2sKeys, _inboundKeys, rateLimit: _keysLimit)
      ..add(
        name,
        Routes.s2sCallSignals,
        _inboundSignal,
        rateLimit: _signalsLimit,
        maxBodyBytes: 1024 * 1024,
      );
    r
      ..add(
        name,
        Routes.s2sGroupMessages,
        _inboundGroupMessage,
        rateLimit: _messagesLimit,
        maxBodyBytes: 8 * 1024 * 1024,
      )
      ..add(name, Routes.s2sGroup, _inboundGroup, rateLimit: _signalsLimit)
      ..add(
        name,
        Routes.s2sGroupActions,
        _inboundGroupAction,
        rateLimit: _signalsLimit,
        maxBodyBytes: 8 * 1024 * 1024,
      )
      ..add(
        name,
        Routes.s2sGroupSync,
        _inboundGroupSync,
        rateLimit: _signalsLimit,
        maxBodyBytes: 1024 * 1024,
      );
  }

  Future<bool> get enabled async => (await ops.settings()).federationEnabled;

  Future<void> _requireEnabled() async {
    if (!await enabled) {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: 'federation is turned off on this server',
      );
    }
  }

  // --------------------------------------------------------------- inbound

  Future<Response> _identity(HelixRequest q) async => jsonResponse(
    ServerIdentityDocument(
      serverId: config.localDomain,
      publicKey: encodeBytes(_signer.publicKey),
      apiBase: config.apiBase,
    ).toJson(),
  );

  Future<Response> _inboundMessages(HelixRequest q) async {
    final batch = q.json(S2SMessageBatch.fromJson);
    final accepted = await messaging.receive(q.server.serverId, batch);
    return jsonResponse(accepted.toJson());
  }

  Future<Response> _inboundKeys(HelixRequest q) async {
    var address = AccountAddress.tryParse(q.param('account'));
    if (address != null) address = address.relativeTo(config.localDomain);
    if (address == null || address.isRemote) {
      throw const ApiError(ErrorCode.notFound);
    }
    final decision = await context.rateLimiter.hit(
      _keysTargetLimit,
      '${q.server.serverId}|${address.id}',
    );
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final wanted = q.queryAll('device').toSet();
    final bundles = await keys.remoteBundles(
      address.id,
      devices: wanted.isEmpty ? null : wanted,
    );
    if (bundles == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(bundles.toJson());
  }

  Future<Response> _inboundSignal(HelixRequest q) async {
    final signal = q.json(S2SCallSignal.fromJson);
    final answer = await calls.receive(
      q.server.serverId,
      q.param('call_id'),
      signal,
    );
    return jsonResponse(answer.toJson());
  }

  Future<Response> _inboundGroupMessage(HelixRequest q) async {
    await groups.receiveMessage(
      q.server.serverId,
      q.uuidParam('group_id'),
      q.json(S2SGroupMessage.fromJson),
    );
    return noContent();
  }

  Future<Response> _inboundGroup(HelixRequest q) async {
    final group = await groups.viewFor(
      q.server.serverId,
      q.uuidParam('group_id'),
    );
    if (group == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(group.toJson());
  }

  Future<Response> _inboundGroupAction(HelixRequest q) async => jsonResponse(
    (await groups.receiveAction(
      q.server.serverId,
      q.uuidParam('group_id'),
      q.json(S2SGroupAction.fromJson),
    )).toJson(),
  );

  Future<Response> _inboundGroupSync(HelixRequest q) async => jsonResponse(
    (await groups.receiveSync(
      q.server.serverId,
      q.uuidParam('group_id'),
      q.json(S2SGroupSync.fromJson),
    )).toJson(),
  );

  /// A group call: refusals become ApiError, unreachable servers
  /// [RelayUnavailable] (queued group work retries on it).
  Future<JsonReader?> _groupCall(
    String domain,
    String method,
    String path, {
    JsonMap? body,
  }) async {
    await _requireEnabled();
    try {
      return await client.call(domain, method, path, body: body);
    } on PeerRefused catch (e) {
      throw _mapRefusal(e.error, domain);
    } on PeerUnavailable catch (e) {
      throw RelayUnavailable(e.reason);
    }
  }

  // -------------------------------------------------------------- outbound

  /// Rewrites a peer's `device_list_stale` so accounts carry its domain.
  static ApiError _qualifyStale(ApiError error, String domain) {
    final details = error.details;
    if (details == null) return error;
    final stale = StaleDevices.fromJson(JsonReader.of(details));
    return ApiError(
      ErrorCode.deviceListStale,
      message: 'the device list changed',
      details: StaleDevices(
        accounts: [
          for (final a in stale.accounts)
            StaleAccountDevices(
              account: AccountAddress.tryParse(a.account)?.domain == null
                  ? '${a.account}@$domain'
                  : a.account,
              missing: a.missing,
              extra: a.extra,
            ),
        ],
      ).toJson(),
    );
  }

  /// A peer's refusal, as this server reports it to its own client.
  static ApiError _mapRefusal(ApiError error, String domain) =>
      switch (error.code) {
        ErrorCode.deviceListStale => _qualifyStale(error, domain),
        ErrorCode.notFound => const ApiError(
          ErrorCode.notFound,
          message: 'a recipient account does not exist',
        ),
        ErrorCode.rateLimited || ErrorCode.quotaExceeded => error,
        _ => const ApiError(
          ErrorCode.federationUnavailable,
          message: 'the other server refused the request',
        ),
      };

  Future<void> _relayMessages(String domain, S2SMessageBatch batch) async {
    await _requireEnabled();
    peers.checkAllowed(domain);
    try {
      await client.call(
        domain,
        'POST',
        Routes.s2sMessages.path,
        body: batch.toJson(),
      );
    } on PeerRefused catch (e) {
      throw _mapRefusal(e.error, domain);
    } on PeerUnavailable catch (e) {
      // Typing and other live-only sends are not worth keeping.
      if (batch.ephemeral) return;
      log.info('relay_queued', {'peer': domain, 'why': e.reason});
      await context.db.tx(
        (tx) => context.outbox.enqueue(
          tx,
          relayJob,
          {'domain': domain, 'batch': batch.toJson()},
          delay: const Duration(seconds: 5),
          maxAttempts: 12,
          dedupeKey: 'relay:$domain:${batch.id}',
        ),
      );
    }
  }

  /// Retries a queued relay; after acceptance there is no sender to tell, so
  /// a refusal is logged and dropped.
  Future<void> _retryRelay(Map<String, Object?> payload) async {
    final domain = payload['domain']! as String;
    if (!await enabled) return;
    final batch = S2SMessageBatch.fromJson(JsonReader.of(payload['batch']));
    try {
      await client.call(
        domain,
        'POST',
        Routes.s2sMessages.path,
        body: batch.toJson(),
      );
    } on PeerRefused catch (e) {
      log.warn('relay_refused', {'peer': domain, 'code': e.error.code.wire});
    } on ApiError catch (e) {
      log.warn('relay_dropped', {'peer': domain, 'code': e.code.wire});
    }
  }

  Future<AccountKeys?> _fetchKeys(
    String domain,
    String accountId,
    Set<String>? devices,
  ) async {
    await _requireEnabled();
    final query = devices == null || devices.isEmpty
        ? ''
        : '?${[for (final d in devices) 'device=${Uri.encodeQueryComponent(d)}'].join('&')}';
    try {
      final json = await client.call(
        domain,
        'GET',
        '${Routes.s2sKeys.expand({'account': accountId})}$query',
      );
      return json == null ? null : AccountKeys.fromJson(json);
    } on PeerRefused catch (e) {
      if (e.error.code == ErrorCode.notFound) return null;
      throw _mapRefusal(e.error, domain);
    } on PeerUnavailable {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: 'the other server cannot be reached',
      );
    }
  }

  Future<CallSignalResponse> _relaySignal(
    String domain,
    String callId,
    S2SCallSignal signal,
  ) async {
    await _requireEnabled();
    try {
      final json = await client.call(
        domain,
        'POST',
        Routes.s2sCallSignals.expand({'call_id': callId}),
        body: signal.toJson(),
      );
      return json == null
          ? const CallSignalResponse(delivered: [], pending: [])
          : CallSignalResponse.fromJson(json);
    } on PeerRefused catch (e) {
      throw _mapRefusal(e.error, domain);
    } on PeerUnavailable {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: 'the other server cannot be reached',
      );
    }
  }

  // ------------------------------------------------------- verification

  Future<ServerPrincipal?> _verify(Request request, Uint8List body) async {
    final server = request.headers[HelixHeaders.s2sServer]?.toLowerCase();
    final ts = int.tryParse(request.headers[HelixHeaders.s2sTimestamp] ?? '');
    final rawSignature = request.headers[HelixHeaders.s2sSignature];
    if (server == null || ts == null || rawSignature == null) return null;
    final Uint8List signature;
    try {
      signature = decodeBytes(rawSignature);
    } on FormatException {
      return null;
    }
    if (signature.length != 64) return null;
    final skew = context.clock.now().millisecondsSinceEpoch - ts;
    if (skew.abs() > s2sMaxSkew.inMilliseconds) return null;
    if (!await enabled) return null;

    final uri = request.requestedUri;
    final input = s2sSigningInput(
      server: server,
      timestampMs: ts,
      method: request.method,
      pathAndQuery: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
      body: body,
    );
    Future<bool> verifiedBy(Peer peer) => verifyEd25519(
      publicKey: peer.publicKey,
      message: input,
      signature: signature,
    );
    try {
      var peer = await peers.resolve(server);
      if (!await verifiedBy(peer)) {
        peer = await peers.resolve(server, refresh: true);
        if (!await verifiedBy(peer)) return null;
      }
    } on Object {
      return null;
    }
    // Each signature is accepted once within the skew window.
    final fresh = await context.ephemeral.putIfAbsent(
      'fed:replay:${encodeBytes(sha256Bytes(signature))}',
      '1',
      s2sMaxSkew * 2,
    );
    if (!fresh) return null;
    unawaited(_store.touch(context.db, server).catchError((_) {}));
    return ServerPrincipal(serverId: server);
  }
}

/// The hooks the federation module installs in messaging, keys and calls.
final class _Relay
    implements MessageRelay, RemoteKeySource, CallRelay, GroupRelay {
  _Relay(this._m);

  final FederationModule _m;

  @override
  String get localDomain => _m.config.localDomain;

  @override
  Future<void> relay(String domain, S2SMessageBatch batch) =>
      _m._relayMessages(domain, batch);

  @override
  Future<AccountKeys?> fetch(
    String domain,
    String accountId, {
    Set<String>? devices,
  }) => _m._fetchKeys(domain, accountId, devices);

  @override
  Future<CallSignalResponse> relayCall(
    String domain,
    String callId,
    S2SCallSignal signal,
  ) => _m._relaySignal(domain, callId, signal);

  @override
  Future<S2SGroupActionResult> action(
    String home,
    String groupId,
    S2SGroupAction action,
  ) async {
    final json = await _m._groupCall(
      home,
      'POST',
      Routes.s2sGroupActions.expand({'group_id': groupId}),
      body: action.toJson(),
    );
    if (json == null) throw const RelayUnavailable('empty action answer');
    return S2SGroupActionResult.fromJson(json);
  }

  @override
  Future<Group?> fetchGroup(String home, String groupId) async {
    try {
      final json = await _m._groupCall(
        home,
        'GET',
        Routes.s2sGroup.expand({'group_id': groupId}),
      );
      return json == null ? null : Group.fromJson(json);
    } on ApiError catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<S2SGroupSyncResponse> sync(
    String domain,
    String groupId,
    S2SGroupSync sync,
  ) async {
    final json = await _m._groupCall(
      domain,
      'POST',
      Routes.s2sGroupSync.expand({'group_id': groupId}),
      body: sync.toJson(),
    );
    return json == null
        ? const S2SGroupSyncResponse()
        : S2SGroupSyncResponse.fromJson(json);
  }

  @override
  Future<void> message(
    String domain,
    String groupId,
    S2SGroupMessage message,
  ) async {
    await _m._groupCall(
      domain,
      'POST',
      Routes.s2sGroupMessages.expand({'group_id': groupId}),
      body: message.toJson(),
    );
  }
}

final class _ServerAuthenticator implements Authenticator {
  _ServerAuthenticator(this._m);

  final FederationModule _m;

  @override
  Future<DevicePrincipal?> device(String bearerToken) async => null;

  @override
  Future<AdminPrincipal?> admin(String bearerToken) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) =>
      _m._verify(request, body);
}
