import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final at = DateTime.utc(2026, 10, 1, 12, 30);
  final account = AdminAccount(
    accountId: Uuid.v7(),
    status: AccountStatus.suspended,
    createdAt: at,
    activeDevices: 2,
    helixName: 'alice',
    phoneLast4: '0001',
    lastSeenOn: DateTime.utc(2026, 9, 30),
  );

  test('admin DTOs round-trip', () {
    expectRoundTrip(
      const AdminSetupStatus(configured: true),
      (v) => v.toJson(),
      AdminSetupStatus.fromJson,
    );
    expectRoundTrip(
      AdminSession(token: 'tok', expiresAt: at),
      (v) => v.toJson(),
      AdminSession.fromJson,
    );
    expectRoundTrip(
      const ChangeAdminPasswordRequest(currentPassword: 'a', newPassword: 'b'),
      (v) => v.toJson(),
      ChangeAdminPasswordRequest.fromJson,
    );
    expectRoundTrip(
      AdminAccountDetail(
        account: account,
        devices: [
          AdminDevice(
            deviceId: Uuid.v7(),
            name: 'Pixel',
            platform: DevicePlatform.android,
            active: false,
            createdAt: at,
            revokedAt: at,
          ),
        ],
        hasPassword: true,
        openReports: 3,
      ),
      (v) => v.toJson(),
      AdminAccountDetail.fromJson,
    );
    expectRoundTrip(
      Page(items: [account], nextCursor: account.accountId),
      (v) => v.toJson((a) => a.toJson()),
      (j) => Page.fromJson(j, AdminAccount.fromJson),
    );
    expectRoundTrip(
      AdminInvite(
        inviteId: Uuid.v7(),
        issuer: 'admin',
        status: InviteStatus.used,
        createdAt: at,
        expiresAt: at,
        redeemedBy: account.accountId,
      ),
      (v) => v.toJson(),
      AdminInvite.fromJson,
    );
    expectRoundTrip(
      AdminReport(
        reportId: Uuid.v7(),
        reporter: Uuid.v7(),
        subject: account.accountId,
        category: ReportCategory.impersonation,
        status: ReportStatus.open,
        createdAt: at,
        note: 'pretends to be support',
      ),
      (v) => v.toJson(),
      AdminReport.fromJson,
    );
    expectRoundTrip(
      AuditEntry(
        id: Uuid.v7(),
        action: 'account.suspend',
        at: at,
        target: account.accountId,
        details: const {'reason': 'spam'},
      ),
      (v) => v.toJson(),
      AuditEntry.fromJson,
    );
    expectRoundTrip(
      const AdminConfig(
        serverName: 'Helix',
        version: '2.0.0',
        registration: RegistrationMode.invite,
        maintenance: true,
        federationEnabled: true,
        maxAttachmentBytes: 1 << 20,
        nodeId: 'node-1',
        federationDomain: 'helix.example',
        integrations: AdminIntegrations(
          push: AdminIntegrationStatus(configured: true, provider: 'fcm'),
          sms: AdminIntegrationStatus(configured: false),
          turn: AdminIntegrationStatus(configured: true, count: 2),
        ),
      ),
      (v) => v.toJson(),
      AdminConfig.fromJson,
    );
    // An older server does not send the block at all.
    expect(
      AdminConfig.fromJson(
        JsonReader.of({
          'server_name': 'Helix',
          'version': '1',
          'registration': 'phone',
          'maintenance': false,
          'federation_enabled': false,
          'max_attachment_bytes': 1,
          'node_id': 'n',
        }),
      ).integrations,
      isNull,
    );
    expectRoundTrip(
      const FeatureFlags(flags: {'group_calls': true}),
      (v) => v.toJson(),
      FeatureFlags.fromJson,
    );
    expectRoundTrip(
      const PurgeResult(removed: {'dead_jobs': 2}),
      (v) => v.toJson(),
      PurgeResult.fromJson,
    );
    expectRoundTrip(
      const ServerInfo(
        name: 'Helix',
        version: '2.0.0',
        registration: RegistrationMode.phone,
        maxAttachmentBytes: 1,
        termsVersion: 't',
        privacyVersion: 'p',
        features: {'crash_reporting_upload': false},
      ),
      (v) => v.toJson(),
      ServerInfo.fromJson,
    );
    expectRoundTrip(
      AccountExport(
        accountId: account.accountId,
        exportedAt: at,
        sections: const {
          'people': {'contacts': 3},
        },
      ),
      (v) => v.toJson(),
      AccountExport.fromJson,
    );
  });

  test('a config patch carries only the fields given', () {
    const patch = AdminConfigPatch(maintenance: false);
    expect(patch.toJson(), {'maintenance': false});
    final decoded = AdminConfigPatch.fromJson(
      JsonReader.of(const <String, Object?>{'server_name': 'X'}),
    );
    expect(decoded.serverName, 'X');
    expect(decoded.maintenance, isNull);
    expect(const AdminConfigPatch().isEmpty, isTrue);
  });

  test('unknown statuses decode as unknown', () {
    final invite = AdminInvite.fromJson(
      JsonReader.of({
        'invite_id': 'i',
        'issuer': 'admin',
        'status': 'teleported',
        'created_at': toWireTime(DateTime.utc(2026, 10)),
        'expires_at': toWireTime(DateTime.utc(2026, 10, 2)),
      }),
    );
    expect(invite.status, InviteStatus.unknown);
  });
}
