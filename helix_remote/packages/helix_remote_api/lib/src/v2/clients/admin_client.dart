import 'dart:async';

import 'package:helix_remote_api/src/v2/realtime/socket.dart';
import 'package:helix_remote_api/src/v2/transport/auth.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `admin` module, for the operator console (Phase AD), plus the
/// admin-only `GET /v1/ops/metrics`.
///
/// It runs on a transport holding [AdminTokenAuth] (the `helix.admin`
/// audience): device tokens never open admin routes, nor admin tokens
/// device routes. [setup], [signIn] and [changePassword] store the session
/// they return in that auth, so later calls are authenticated. Admin
/// tokens are not refreshed; a 401 throws `SignedOutException`.
final class AdminClient {
  AdminClient(this._t, {this._sockets = defaultSocketFactory}) {
    if (_t.auth is! AdminTokenAuth) {
      throw ArgumentError.value(_t.auth, 'transport', 'needs AdminTokenAuth');
    }
  }

  final HelixTransport _t;
  final RealtimeSocketFactory _sockets;

  AdminTokenAuth get auth => _t.auth! as AdminTokenAuth;

  // ----------------------------------------------------------------- session

  Future<AdminSetupStatus> setupStatus() =>
      _t.call(Routes.adminSetupStatus, AdminSetupStatus.fromJson);

  /// First-run setup (`already_exists` once configured).
  Future<AdminSession> setup(String password) => _keep(
    _t.call(
      Routes.adminSetup,
      AdminSession.fromJson,
      json: AdminPasswordRequest(password: password).toJson(),
    ),
  );

  Future<AdminSession> signIn(String password) => _keep(
    _t.call(
      Routes.adminSignIn,
      AdminSession.fromJson,
      json: AdminPasswordRequest(password: password).toJson(),
    ),
  );

  /// Ends every other admin session; this one continues with the returned
  /// token.
  Future<AdminSession> changePassword({
    required String current,
    required String next,
  }) => _keep(
    _t.call(
      Routes.adminPassword,
      AdminSession.fromJson,
      json: ChangeAdminPasswordRequest(
        currentPassword: current,
        newPassword: next,
      ).toJson(),
    ),
  );

  Future<AdminSession> _keep(Future<AdminSession> request) async {
    final session = await request;
    auth.use(session);
    return session;
  }

  // ---------------------------------------------------------------- accounts

  /// Accounts, filtered by [status] and [query] (name prefix or last four
  /// digits).
  Future<Page<AdminAccount>> accounts({
    AccountStatus? status,
    String? query,
    PageRequest page = const PageRequest(),
  }) => _t.call(
    Routes.adminAccounts,
    (json) => Page.fromJson(json, AdminAccount.fromJson),
    query: {...page.toQuery(), 'status': ?status?.wire, 'q': ?query},
  );

  Future<AdminAccountDetail> account(String accountId) => _t.call(
    Routes.adminAccount,
    AdminAccountDetail.fromJson,
    params: {'account': accountId},
  );

  Future<void> suspend(String accountId, {String? reason}) => _t.empty(
    Routes.adminSuspend,
    params: {'account': accountId},
    json: AdminActionRequest(reason: reason).toJson(),
  );

  Future<void> unsuspend(String accountId) =>
      _t.empty(Routes.adminUnsuspend, params: {'account': accountId});

  /// Bans the phone number and deletes the account.
  Future<void> ban(String accountId, {String? reason}) => _t.empty(
    Routes.adminBan,
    params: {'account': accountId},
    json: AdminActionRequest(reason: reason).toJson(),
  );

  Future<void> deleteAccount(String accountId) =>
      _t.empty(Routes.adminDeleteAccount, params: {'account': accountId});

  Future<void> revokeDevice(String accountId, String deviceId) => _t.empty(
    Routes.adminRevokeDevice,
    params: {'account': accountId, 'device_id': deviceId},
  );

  /// A single-use 48-hour recovery code, shown once.
  Future<AdminRecoveryCode> createRecoveryCode(String accountId) => _t.call(
    Routes.adminRecoveryCode,
    AdminRecoveryCode.fromJson,
    params: {'account': accountId},
  );

  // ----------------------------------------------------------------- invites

  Future<Page<AdminInvite>> invites({PageRequest page = const PageRequest()}) =>
      _t.call(
        Routes.adminInvites,
        (json) => Page.fromJson(json, AdminInvite.fromJson),
        query: page.toQuery(),
      );

  /// The code is shown once.
  Future<CreatedInvite> createInvite() =>
      _t.call(Routes.adminCreateInvite, CreatedInvite.fromJson);

  Future<void> cancelInvite(String inviteId) =>
      _t.empty(Routes.adminCancelInvite, params: {'invite_id': inviteId});

  // ----------------------------------------------------------------- reports

  Future<Page<AdminReport>> reports({
    ReportStatus? status,
    PageRequest page = const PageRequest(),
  }) => _t.call(
    Routes.adminReports,
    (json) => Page.fromJson(json, AdminReport.fromJson),
    query: {...page.toQuery(), 'status': ?status?.wire},
  );

  /// [status] is `resolved` or `dismissed`.
  Future<void> resolveReport(String reportId, ReportStatus status) => _t.empty(
    Routes.adminResolveReport,
    params: {'report_id': reportId},
    json: ResolveReportRequest(status: status).toJson(),
  );

  // ------------------------------------------------------------------ server

  /// Newest first.
  Future<Page<AuditEntry>> audit({PageRequest page = const PageRequest()}) =>
      _t.call(
        Routes.adminAudit,
        (json) => Page.fromJson(json, AuditEntry.fromJson),
        query: page.toQuery(),
      );

  Future<AdminConfig> config() =>
      _t.call(Routes.adminConfig, AdminConfig.fromJson);

  Future<AdminConfig> updateConfig(AdminConfigPatch patch) => _t.call(
    Routes.adminSetConfig,
    AdminConfig.fromJson,
    json: patch.toJson(),
  );

  Future<FeatureFlags> featureFlags() =>
      _t.call(Routes.adminFeatureFlags, FeatureFlags.fromJson);

  Future<void> setFeatureFlag(String name, {required bool enabled}) => _t.empty(
    Routes.adminSetFeatureFlag,
    params: {'name': name},
    json: SetFeatureFlagRequest(enabled: enabled).toJson(),
  );

  /// Recent redacted log lines of the answering node (1-500).
  Future<AdminLogLines> logs({int limit = 200}) => _t.call(
    Routes.adminLogs,
    AdminLogLines.fromJson,
    query: {'limit': '${limit.clamp(1, 500)}'},
  );

  /// Live redacted log lines (WebSocket). Cancelling the subscription closes
  /// the socket. A refused upgrade is added as the stream's error.
  Stream<String> logStream() {
    RealtimeSocket? socket;
    StreamSubscription<String>? lines;
    var cancelled = false;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        try {
          final token = await auth.accessToken();
          final opened = await _sockets(
            _t.url(
              Routes.adminLogStream,
              scheme: _t.baseUrl.scheme == 'https' ? 'wss' : 'ws',
            ),
            headers: {HelixHeaders.authorization: 'Bearer $token'},
            protocols: const [],
          );
          if (cancelled) {
            unawaited(opened.close(1000));
            return;
          }
          socket = opened;
          lines = opened.messages.listen(
            controller.add,
            onDone: controller.close,
            onError: (Object _) {},
          );
        } on RealtimeUpgradeException catch (e) {
          controller.addError(e.error);
          await controller.close();
        } on Object catch (e) {
          controller.addError(e);
          await controller.close();
        }
      },
      onCancel: () async {
        cancelled = true;
        await lines?.cancel();
        await socket?.close(1000);
      },
    );
    return controller.stream;
  }

  /// Dead jobs and expired identity rows.
  Future<PurgeResult> purge() =>
      _t.call(Routes.adminPurge, PurgeResult.fromJson);

  /// Prometheus text (an `ops` route that needs the admin audience).
  Future<String> metrics() async => (await _t.send(Routes.metrics)).text;
}
