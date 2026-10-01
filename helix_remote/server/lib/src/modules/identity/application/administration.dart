import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/application/registration.dart';
import 'package:helix_remote_server/src/modules/identity/application/sign_up.dart';
import 'package:helix_remote_server/src/modules/identity/data/admin_store.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Operator actions on accounts, devices, invites and recovery codes
/// (admin module, through [IdentityAdminApi]).
final class Administration implements IdentityAdminApi {
  Administration(
    this.c, {
    required this.store,
    required this.signUp,
    required this.registration,
    required this.deleteAccount,
  });

  final IdentityContext c;
  final AdminStore store;
  final SignUp signUp;
  final Registration registration;

  /// The facade's full account deletion (hooks included).
  final Future<void> Function(Tx tx, String accountId) deleteAccount;

  @override
  Future<Page<AdminAccount>> accounts(
    SqlSession s, {
    required PageRequest page,
    AccountStatus? status,
    String? query,
  }) => store.accounts(s, page: page, status: status, query: query);

  @override
  Future<({AdminAccount account, List<AdminDevice> devices, bool hasPassword})?>
  accountDetail(SqlSession s, String accountId) async {
    final account = await store.account(s, accountId);
    if (account == null) return null;
    return (
      account: account,
      devices: await store.devices(s, accountId),
      hasPassword: await c.credentials.password(s, accountId) != null,
    );
  }

  @override
  Future<bool> setSuspended(
    Tx tx,
    String accountId, {
    required bool suspended,
  }) async {
    if (await c.store.account(tx, accountId) == null) return false;
    await c.store.setStatus(tx, accountId, suspended ? 'suspended' : 'active');
    return true;
  }

  @override
  Future<bool> ban(Tx tx, String accountId) async {
    if (await c.store.account(tx, accountId) == null) return false;
    final phoneHash = await c.store.phoneHashOf(tx, accountId);
    if (phoneHash != null) await c.credentials.ban(tx, phoneHash);
    await deleteAccount(tx, accountId);
    return true;
  }

  @override
  Future<bool> revokeDevice(Tx tx, String accountId, String deviceId) async {
    final target = await c.store.deviceById(tx, deviceId);
    if (target == null || target.accountId != accountId || !target.active) {
      return false;
    }
    final revoked = await c.store.revokeDevice(tx, deviceId, 'admin');
    if (revoked == null) return false;
    await c.hooks.deviceRevoked(tx, revoked);
    await c.hooks.deviceListChanged(tx, accountId);
    await c.store.addEvent(
      tx,
      accountId,
      SecurityEventKind.deviceRevoked,
      deviceId: revoked.id,
      deviceName: revoked.name,
    );
    await c.hooks.accountSignal(
      tx,
      accountId,
      AccountSignalEvent(
        signal: AccountSignalKind.deviceRevoked,
        at: c.clock.now(),
        device: revoked.id,
        deviceName: revoked.name,
      ),
    );
    tx.afterCommit(
      () => c.bus.publish('device.revoked', {'device': revoked.id}),
    );
    return true;
  }

  @override
  Future<AdminRecoveryCode?> issueRecoveryCode(String accountId) =>
      c.db.tx((tx) async {
        if (await c.store.account(tx, accountId) == null) return null;
        final issued = await registration.issueRecoveryCode(tx, accountId);
        return AdminRecoveryCode(
          recoveryCode: issued.code,
          expiresAt: issued.expiresAt,
        );
      });

  @override
  Future<Page<AdminInvite>> invites(
    SqlSession s, {
    required PageRequest page,
  }) => store.invites(s, page: page, now: c.clock.now());

  @override
  Future<CreatedInvite> createInvite() async {
    final invite = await signUp.issueInvite(c.db);
    return CreatedInvite(
      inviteId: invite.id,
      inviteCode: invite.code,
      expiresAt: invite.expiresAt,
    );
  }

  @override
  Future<bool> cancelInvite(SqlSession s, String inviteId) =>
      store.cancelInvite(s, inviteId);

  @override
  Future<Map<String, int>> purgeExpired(SqlSession s) => store.purgeExpired(s);
}
