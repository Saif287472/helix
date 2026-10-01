import 'dart:typed_data';

import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/identity/application/accounts.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/application/hooks.dart';
import 'package:helix_remote_server/src/modules/identity/application/registration.dart';
import 'package:helix_remote_server/src/modules/identity/application/sessions.dart';
import 'package:helix_remote_server/src/modules/identity/application/sign_in.dart';
import 'package:helix_remote_server/src/modules/identity/application/sign_up.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/data/credential_store.dart';
import 'package:helix_remote_server/src/modules/identity/data/identity_store.dart';
import 'package:helix_remote_server/src/modules/identity/domain/jwt.dart';
import 'package:helix_remote_server/src/modules/identity/http/identity_routes.dart';
import 'package:helix_remote_server/src/modules/identity/migrations.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';

/// Accounts, devices, sessions and every way of signing in (ADR-026).
final class IdentityModule extends ModuleBase
    implements ProvidesAuthentication {
  IdentityModule(super.context, {SmsProvider? sms}) {
    final config = IdentityConfig.from(context.config, sms: sms);
    _store = IdentityStore(schema);
    _credentials = CredentialStore(schema);
    final jwt = JwtCodec(keys: config.jwtKeys, activeKid: config.activeJwtKid);
    final sessions = SessionIssuer(
      jwt: jwt,
      credentials: _credentials,
      clock: context.clock,
    );
    _ctx = IdentityContext(
      db: context.db,
      store: _store,
      credentials: _credentials,
      ephemeral: context.ephemeral,
      rateLimiter: context.rateLimiter,
      bus: context.bus,
      config: config,
      clock: context.clock,
      hooks: _hooks,
      sessions: sessions,
      log: log,
    );
    signUp = SignUp(_ctx);
    registration = Registration(_ctx);
    signIn = SignIn(_ctx);
    accounts = Accounts(_ctx);
    authenticator = IdentityAuthenticator(
      db: context.db,
      jwt: jwt,
      store: _store,
      clock: context.clock,
    );
    api = _IdentityFacade(this);
  }

  final IdentityHooks _hooks = IdentityHooks();
  late final IdentityStore _store;
  late final CredentialStore _credentials;
  late final IdentityContext _ctx;
  late final SignUp signUp;
  late final Registration registration;
  late final SignIn signIn;
  late final Accounts accounts;

  @override
  late final Authenticator authenticator;

  /// The facade other modules receive.
  late final IdentityApi api;

  @override
  String get name => 'identity';

  @override
  List<Migration> get migrations => identityMigrations;

  @override
  void routes(RouteRegistry routes) => registerIdentityRoutes(
    routes,
    signUp: signUp,
    registration: registration,
    signIn: signIn,
    accounts: accounts,
  );

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob('identity.purge_expired', const Duration(hours: 6), () async {
      await _credentials.purgeExpiredRefresh(context.db);
      await _credentials.purgeChallenges(context.db);
    }),
  ];
}

final class _IdentityFacade implements IdentityApi {
  _IdentityFacade(this._m);

  final IdentityModule _m;

  IdentityStore get _store => _m._store;

  @override
  Future<AccountRecord?> account(SqlSession s, String accountId) =>
      _store.account(s, accountId);

  @override
  Future<DeviceRecord?> device(SqlSession s, String deviceId) =>
      _store.deviceById(s, deviceId);

  @override
  Future<List<DeviceRecord>> activeDevices(SqlSession s, String accountId) =>
      _store.activeDevices(s, accountId);

  @override
  Future<Map<String, List<DeviceRecord>>> activeDevicesOf(
    SqlSession s,
    Iterable<String> accountIds,
  ) => _store.activeDevicesOf(s, accountIds);

  @override
  Future<Map<String, String>> accountsByDiscoveryHash(
    SqlSession s,
    Iterable<String> hashes,
  ) => _store.accountsByDiscoveryHash(s, hashes);

  @override
  Future<String?> accountByHelixName(SqlSession s, String name) =>
      _store.accountByHelixName(s, name);

  @override
  Future<Uint8List> discoverySalt() => _m._ctx.discoverySalt();

  @override
  Future<PushTarget?> pushTarget(SqlSession s, String deviceId) =>
      _store.pushTarget(s, deviceId);

  @override
  Future<void> dropPushToken(SqlSession s, String deviceId) =>
      _store.clearPushToken(s, deviceId);

  @override
  Future<void> deleteAccount(Tx tx, String accountId) async {
    await _m._ctx.revokeAll(tx, accountId, 'account_deleted');
    await _m._hooks.accountDeleted(tx, accountId);
    await _store.deleteAccount(tx, accountId);
  }

  @override
  void onDeviceAdded(DeviceAddedHook hook) => _m._hooks.onDeviceAdded(hook);

  @override
  void onDeviceRevoked(DeviceRevokedHook hook) =>
      _m._hooks.onDeviceRevoked(hook);

  @override
  void onIdentityKeyChanged(IdentityKeyChangedHook hook) =>
      _m._hooks.onIdentityKeyChanged(hook);

  @override
  void onAccountSignal(AccountSignalHook hook) =>
      _m._hooks.onAccountSignal(hook);

  @override
  void onDeviceListChanged(DeviceListChangedHook hook) =>
      _m._hooks.onDeviceListChanged(hook);

  @override
  void onAccountDeleted(AccountDeletedHook hook) =>
      _m._hooks.onAccountDeleted(hook);
}
