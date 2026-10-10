import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/keys/api.dart';
import 'package:helix_remote_server/src/modules/keys/data/prekey_store.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Prekeys and bundles (X3DH key directory, CRYPTO_V2.md §3).
final class KeysModule extends ModuleBase implements ProvidesAccountExport {
  KeysModule(super.context, {required this.identity}) {
    _store = PrekeyStore(schema);
    identity
      ..onDeviceAdded(_onDeviceAdded)
      ..onDeviceRevoked((tx, device) => _store.purgeDevice(tx, device.id));
    api = _KeysFacade(this);
  }

  final IdentityApi identity;
  RemoteKeySource? _remote;
  late final PrekeyStore _store;
  late final KeysApi api;
  final List<PrekeysLowHook> _lowHooks = [];

  static const maxStored = 1000;

  /// Bundle fetches per requesting device, across every target: the
  /// requester's overall cap.
  static final _perRequester = RateLimitPolicy.per(
    'keys.bundle',
    120,
    const Duration(hours: 1),
  );

  /// Bundle fetches per (requesting account, target account) pair, for local
  /// requesters. There is deliberately no bucket shared by everyone who asks
  /// about one target: a few accounts could keep it empty, and then nobody
  /// could start a session with the victim (review finding A-12). Twenty an
  /// hour covers every device of the requester and a few session resets.
  static final _perPair = RateLimitPolicy.per(
    'keys.bundle_pair',
    20,
    const Duration(hours: 1),
  );

  /// Bundle fetches per target account from *other servers*
  /// (`KeysApi.remoteBundles`), on top of the federation module's own
  /// per-server limits, so many servers cannot together drain an account's
  /// one-time prekeys. Local fetches no longer share it.
  static final _perTarget = RateLimitPolicy.per(
    'keys.bundle_target',
    600,
    const Duration(hours: 1),
  );

  /// How long a requesting account waits for another one-time prekey of the
  /// same device. Within it, a fetch still answers the signed prekey, and the
  /// session starts without a one-time prekey (CRYPTO_V2.md §4): draining a
  /// device's one-time prekeys takes one account per prekey per hour.
  static const oneTimePrekeyGap = Duration(hours: 1);

  /// Public prekey material only, per active device.
  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    final devices = await identity.activeDevices(s, accountId);
    return [
      for (final d in devices)
        {
          'device_id': d.id,
          'identity_key': encodeBytes(d.identityKey),
          'signing_key': encodeBytes(d.signingKey),
          'signed_prekey': await _signedPrekeyInfo(s, d.id),
          'one_time_prekeys': (await s.queryOne(
            'SELECT count(*)::int8 AS n FROM $schema.one_time_prekeys WHERE device_id = @d:uuid',
            {'d': d.id},
          ))!.integer('n'),
        },
    ];
  }

  Future<Object?> _signedPrekeyInfo(SqlSession s, String deviceId) async {
    final r = await s.queryOne(
      'SELECT key_id, updated_at FROM $schema.signed_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    return r == null
        ? null
        : {
            'key_id': r.integer('key_id'),
            'updated_at': toWireTime(r.time('updated_at')),
          };
  }

  @override
  String get name => 'keys';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'keys_baseline', _baseline),
  ];

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.signed_prekeys (
  device_id uuid PRIMARY KEY,
  key_id integer NOT NULL,
  public_key bytea NOT NULL,
  signature bytea NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE $s.one_time_prekeys (
  device_id uuid NOT NULL,
  key_id integer NOT NULL,
  public_key bytea NOT NULL,
  PRIMARY KEY (device_id, key_id)
);
''';

  Future<void> _verifySignedPrekey(
    DeviceRecord device,
    SignedPrekey spk,
  ) async {
    if (spk.publicKey.length != 32) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'signed_prekey.public_key'},
      );
    }
    final ok = await verifyEd25519(
      publicKey: device.signingKey,
      message: signedPrekeySignatureBody(spk.id, spk.publicKey),
      signature: spk.signature,
    );
    if (!ok) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'signed_prekey.signature'},
      );
    }
  }

  void _checkOneTime(List<OneTimePrekey> keys) {
    if (keys.length > AddOneTimePrekeysRequest.maxBatch) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'one_time_prekeys'},
      );
    }
    final ids = <int>{};
    for (final k in keys) {
      if (k.publicKey.length != 32 || !ids.add(k.id)) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'one_time_prekeys'},
        );
      }
    }
  }

  Future<void> _onDeviceAdded(
    Tx tx,
    DeviceRecord device,
    PrekeyUpload prekeys,
  ) async {
    await _verifySignedPrekey(device, prekeys.signedPrekey);
    _checkOneTime(prekeys.oneTimePrekeys);
    await _store.setSignedPrekey(tx, device.id, prekeys.signedPrekey);
    await _store.addOneTime(tx, device.id, prekeys.oneTimePrekeys);
  }

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.setSignedPrekey, _setSignedPrekey)
      ..add(name, Routes.addOneTimePrekeys, _addOneTime)
      ..add(name, Routes.keyStatus, _status)
      ..add(name, Routes.accountKeys, _bundle);
  }

  Future<Response> _setSignedPrekey(HelixRequest q) async {
    final spk = q.json(SignedPrekey.fromJson);
    final device = (await identity.device(context.db, q.device.deviceId))!;
    await _verifySignedPrekey(device, spk);
    await _store.setSignedPrekey(context.db, device.id, spk);
    return noContent();
  }

  Future<Response> _addOneTime(HelixRequest q) async {
    final req = q.json(AddOneTimePrekeysRequest.fromJson);
    _checkOneTime(req.keys);
    final deviceId = q.device.deviceId;
    final status = await context.db.tx((tx) async {
      final current = await _store.oneTimeCount(tx, deviceId);
      if (current + req.keys.length > maxStored) {
        throw const ApiError(
          ErrorCode.quotaExceeded,
          message: 'too many one-time prekeys stored',
        );
      }
      await _store.addOneTime(tx, deviceId, req.keys);
      return _store.status(tx, deviceId);
    });
    return jsonResponse(status.toJson());
  }

  Future<Response> _status(HelixRequest q) async => jsonResponse(
    (await _store.status(context.db, q.device.deviceId)).toJson(),
  );

  Future<Response> _bundle(HelixRequest q) async {
    final remote = _remote;
    var address = AccountAddress.tryParse(q.param('account'));
    if (address != null && remote != null) {
      address = address.relativeTo(remote.localDomain);
    }
    if (address == null) throw const ApiError(ErrorCode.notFound);
    if (address.isRemote && remote == null) {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: 'this server does not federate',
      );
    }
    for (final (policy, key) in [
      (_perRequester, q.device.deviceId),
      (_perPair, '${q.device.accountId}/$address'),
    ]) {
      final decision = await context.rateLimiter.hit(policy, key);
      if (!decision.allowed) {
        throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
      }
    }
    final wanted = q.queryAll('device').toSet();
    final devices = wanted.isEmpty ? null : wanted;
    if (address.isRemote) {
      final keys = await remote!.fetch(
        address.domain!,
        address.id,
        devices: devices,
      );
      if (keys == null || keys.account != address.id) {
        throw const ApiError(ErrorCode.notFound);
      }
      return jsonResponse(
        AccountKeys(
          account: address.toString(),
          identityKey: keys.identityKey,
          devices: keys.devices,
        ).toJson(),
      );
    }
    final keys = await _bundles(
      address.id,
      devices: devices,
      requester: q.device.accountId,
    );
    if (keys == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(keys.toJson());
  }

  /// [KeysApi.bundles]. With a [requester] (a local account), each of the
  /// target's devices gives that account at most one one-time prekey per
  /// [oneTimePrekeyGap]; later bundles in the gap carry the signed prekey
  /// only.
  Future<AccountKeys?> _bundles(
    String accountId, {
    Set<String>? devices,
    String? requester,
  }) async {
    final db = context.db;
    final account = await identity.account(db, accountId);
    if (account == null) return null;
    final all = await identity.activeDevices(db, accountId);
    final chosen = devices == null
        ? all
        : all.where((d) => devices.contains(d.id)).toList();
    final bundles = <DeviceBundle>[];
    final low = <(String, int)>[];
    for (final device in chosen) {
      final spk = await _store.signedPrekey(db, device.id);
      if (spk == null) continue;
      final hand =
          requester == null ||
          await context.ephemeral.putIfAbsent(
            'keys:otk:$requester:${device.id}',
            '1',
            oneTimePrekeyGap,
          );
      final otk = hand ? await _store.takeOneTime(db, device.id) : null;
      final remaining = await _store.oneTimeCount(db, device.id);
      if (remaining < KeyStatus.lowWatermark) low.add((device.id, remaining));
      bundles.add(
        DeviceBundle(
          deviceId: device.id,
          identityKey: device.identityKey,
          signingKey: device.signingKey,
          certificate: DeviceCertificate(
            createdAt: device.certificateCreatedAt,
            signature: device.certificate,
          ),
          signedPrekey: spk,
          oneTimePrekey: otk,
        ),
      );
    }
    for (final (deviceId, remaining) in low) {
      // At most one prekeys_low per device per hour.
      if (await context.ephemeral.putIfAbsent(
        'keys:low:$deviceId',
        '1',
        const Duration(hours: 1),
      )) {
        for (final hook in _lowHooks) {
          await hook(deviceId, remaining);
        }
      }
    }
    return AccountKeys(
      account: accountId,
      identityKey: account.identityKey,
      devices: bundles,
    );
  }
}

final class _KeysFacade implements KeysApi {
  _KeysFacade(this._m);

  final KeysModule _m;

  @override
  void setRemoteSource(RemoteKeySource source) => _m._remote = source;

  @override
  Future<AccountKeys?> remoteBundles(
    String accountId, {
    Set<String>? devices,
  }) async {
    final decision = await _m.context.rateLimiter.hit(
      KeysModule._perTarget,
      accountId,
    );
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    return bundles(accountId, devices: devices);
  }

  @override
  Future<AccountKeys?> bundles(String accountId, {Set<String>? devices}) =>
      _m._bundles(accountId, devices: devices);

  @override
  void onPrekeysLow(PrekeysLowHook hook) => _m._lowHooks.add(hook);

  @override
  Future<void> purgeAccount(Tx tx, List<String> deviceIds) async {
    for (final id in deviceIds) {
      await _m._store.purgeDevice(tx, id);
    }
  }
}
