import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/identity.dart';
import 'package:helix_remote_protocol/src/modules/ops.dart';
import 'package:helix_remote_protocol/src/modules/people.dart';

// Operator console (`/v1/admin/*`). The admin password travels only to the
// operator's own server over TLS and is stored as an Argon2id hash; user
// passwords never reach the server (CRYPTO_V2.md §11). Nothing here carries
// a full phone number, a message or a key.

/// `GET /v1/admin/setup`.
final class AdminSetupStatus {
  const AdminSetupStatus({required this.configured});

  /// An admin password exists; setup is closed.
  final bool configured;

  JsonMap toJson() => {'configured': configured};

  factory AdminSetupStatus.fromJson(JsonReader json) =>
      AdminSetupStatus(configured: json.boolean('configured'));
}

/// `POST /v1/admin/setup` (only before setup) and `POST /v1/admin/sessions`.
final class AdminPasswordRequest {
  const AdminPasswordRequest({required this.password});

  static const minLength = 12;
  static const maxLength = 256;

  final String password;

  JsonMap toJson() => {'password': password};

  factory AdminPasswordRequest.fromJson(JsonReader json) =>
      AdminPasswordRequest(password: json.string('password'));
}

/// The 12-hour admin token.
final class AdminSession {
  const AdminSession({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  JsonMap toJson() => {'token': token, 'expires_at': toWireTime(expiresAt)};

  factory AdminSession.fromJson(JsonReader json) => AdminSession(
    token: json.nonEmpty('token'),
    expiresAt: json.time('expires_at'),
  );
}

/// `PUT /v1/admin/password`: ends every other admin session.
final class ChangeAdminPasswordRequest {
  const ChangeAdminPasswordRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;

  JsonMap toJson() => {
    'current_password': currentPassword,
    'new_password': newPassword,
  };

  factory ChangeAdminPasswordRequest.fromJson(JsonReader json) =>
      ChangeAdminPasswordRequest(
        currentPassword: json.string('current_password'),
        newPassword: json.string('new_password'),
      );
}

enum AccountStatus implements WireEnum {
  active('active'),
  suspended('suspended'),
  unknown('unknown');

  const AccountStatus(this.wire);

  @override
  final String wire;
}

/// One row of `GET /v1/admin/accounts` (filters: `status`, `q` = Helix name
/// prefix or last four digits).
final class AdminAccount {
  const AdminAccount({
    required this.accountId,
    required this.status,
    required this.createdAt,
    required this.activeDevices,
    this.helixName,
    this.phoneLast4,
    this.lastSeenOn,
  });

  final String accountId;
  final AccountStatus status;
  final DateTime createdAt;
  final int activeDevices;
  final String? helixName;
  final String? phoneLast4;

  /// The most recent day any device was seen (day precision only).
  final DateTime? lastSeenOn;

  JsonMap toJson() => compact({
    'account_id': accountId,
    'status': status.wire,
    'created_at': toWireTime(createdAt),
    'active_devices': activeDevices,
    'helix_name': helixName,
    'phone_last4': phoneLast4,
    'last_seen_on': lastSeenOn == null ? null : toWireTime(lastSeenOn!),
  });

  factory AdminAccount.fromJson(JsonReader json) => AdminAccount(
    accountId: json.nonEmpty('account_id'),
    status: json.enumValue(
      'status',
      AccountStatus.values,
      orElse: AccountStatus.unknown,
    ),
    createdAt: json.time('created_at'),
    activeDevices: json.integer('active_devices'),
    helixName: json.optString('helix_name'),
    phoneLast4: json.optString('phone_last4'),
    lastSeenOn: json.optTime('last_seen_on'),
  );
}

final class AdminDevice {
  const AdminDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.active,
    required this.createdAt,
    this.lastSeenOn,
    this.revokedAt,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;
  final bool active;
  final DateTime createdAt;
  final DateTime? lastSeenOn;
  final DateTime? revokedAt;

  JsonMap toJson() => compact({
    'device_id': deviceId,
    'name': name,
    'platform': platform.wire,
    'active': active,
    'created_at': toWireTime(createdAt),
    'last_seen_on': lastSeenOn == null ? null : toWireTime(lastSeenOn!),
    'revoked_at': revokedAt == null ? null : toWireTime(revokedAt!),
  });

  factory AdminDevice.fromJson(JsonReader json) => AdminDevice(
    deviceId: json.nonEmpty('device_id'),
    name: json.string('name'),
    platform: json.enumValue(
      'platform',
      DevicePlatform.values,
      orElse: DevicePlatform.other,
    ),
    active: json.boolean('active'),
    createdAt: json.time('created_at'),
    lastSeenOn: json.optTime('last_seen_on'),
    revokedAt: json.optTime('revoked_at'),
  );
}

/// `GET /v1/admin/accounts/{account}`.
final class AdminAccountDetail {
  const AdminAccountDetail({
    required this.account,
    required this.devices,
    required this.hasPassword,
    required this.openReports,
  });

  final AdminAccount account;
  final List<AdminDevice> devices;
  final bool hasPassword;

  /// Open reports about this account.
  final int openReports;

  JsonMap toJson() => {
    'account': account.toJson(),
    'devices': [for (final d in devices) d.toJson()],
    'has_password': hasPassword,
    'open_reports': openReports,
  };

  factory AdminAccountDetail.fromJson(JsonReader json) => AdminAccountDetail(
    account: AdminAccount.fromJson(json.object('account')),
    devices: json.objects('devices', AdminDevice.fromJson),
    hasPassword: json.boolean('has_password'),
    openReports: json.integer('open_reports'),
  );
}

/// `PUT /v1/admin/accounts/{account}/suspension` and
/// `POST /v1/admin/accounts/{account}/ban`. The reason is for the audit log.
final class AdminActionRequest {
  const AdminActionRequest({this.reason});

  static const maxReasonLength = 500;

  final String? reason;

  JsonMap toJson() => compact({'reason': reason});

  factory AdminActionRequest.fromJson(JsonReader json) =>
      AdminActionRequest(reason: json.optString('reason'));
}

/// `POST /v1/admin/accounts/{account}/recovery-codes`: shown once.
final class AdminRecoveryCode {
  const AdminRecoveryCode({
    required this.recoveryCode,
    required this.expiresAt,
  });

  final String recoveryCode;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'recovery_code': recoveryCode,
    'expires_at': toWireTime(expiresAt),
  };

  factory AdminRecoveryCode.fromJson(JsonReader json) => AdminRecoveryCode(
    recoveryCode: json.nonEmpty('recovery_code'),
    expiresAt: json.time('expires_at'),
  );
}

enum InviteStatus implements WireEnum {
  open('open'),
  used('used'),
  cancelled('cancelled'),
  expired('expired'),
  unknown('unknown');

  const InviteStatus(this.wire);

  @override
  final String wire;
}

/// One row of `GET /v1/admin/invites` (codes are stored hashed and never
/// listed).
final class AdminInvite {
  const AdminInvite({
    required this.inviteId,
    required this.issuer,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.redeemedBy,
  });

  final String inviteId;

  /// `admin` or `self` (Helix Global self-issued).
  final String issuer;
  final InviteStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? redeemedBy;

  JsonMap toJson() => compact({
    'invite_id': inviteId,
    'issuer': issuer,
    'status': status.wire,
    'created_at': toWireTime(createdAt),
    'expires_at': toWireTime(expiresAt),
    'redeemed_by': redeemedBy,
  });

  factory AdminInvite.fromJson(JsonReader json) => AdminInvite(
    inviteId: json.nonEmpty('invite_id'),
    issuer: json.string('issuer'),
    status: json.enumValue(
      'status',
      InviteStatus.values,
      orElse: InviteStatus.unknown,
    ),
    createdAt: json.time('created_at'),
    expiresAt: json.time('expires_at'),
    redeemedBy: json.optString('redeemed_by'),
  );
}

/// `POST /v1/admin/invites`: the code is shown once.
final class CreatedInvite {
  const CreatedInvite({
    required this.inviteId,
    required this.inviteCode,
    required this.expiresAt,
  });

  final String inviteId;
  final String inviteCode;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'invite_id': inviteId,
    'invite_code': inviteCode,
    'expires_at': toWireTime(expiresAt),
  };

  factory CreatedInvite.fromJson(JsonReader json) => CreatedInvite(
    inviteId: json.nonEmpty('invite_id'),
    inviteCode: json.nonEmpty('invite_code'),
    expiresAt: json.time('expires_at'),
  );
}

enum ReportStatus implements WireEnum {
  open('open'),
  resolved('resolved'),
  dismissed('dismissed'),
  unknown('unknown');

  const ReportStatus(this.wire);

  @override
  final String wire;
}

/// One row of `GET /v1/admin/reports` (filter: `status`).
final class AdminReport {
  const AdminReport({
    required this.reportId,
    required this.reporter,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    this.note,
  });

  final String reportId;
  final String reporter;
  final String subject;
  final ReportCategory category;
  final ReportStatus status;
  final DateTime createdAt;
  final String? note;

  JsonMap toJson() => compact({
    'report_id': reportId,
    'reporter': reporter,
    'subject': subject,
    'category': category.wire,
    'status': status.wire,
    'created_at': toWireTime(createdAt),
    'note': note,
  });

  factory AdminReport.fromJson(JsonReader json) => AdminReport(
    reportId: json.nonEmpty('report_id'),
    reporter: json.nonEmpty('reporter'),
    subject: json.nonEmpty('subject'),
    category: json.enumValue(
      'category',
      ReportCategory.values,
      orElse: ReportCategory.other,
    ),
    status: json.enumValue(
      'status',
      ReportStatus.values,
      orElse: ReportStatus.unknown,
    ),
    createdAt: json.time('created_at'),
    note: json.optString('note'),
  );
}

/// `PUT /v1/admin/reports/{report_id}`: `resolved` or `dismissed`.
final class ResolveReportRequest {
  const ResolveReportRequest({required this.status});

  final ReportStatus status;

  JsonMap toJson() => {'status': status.wire};

  factory ResolveReportRequest.fromJson(JsonReader json) =>
      ResolveReportRequest(
        status: json.enumValue(
          'status',
          ReportStatus.values,
          orElse: ReportStatus.unknown,
        ),
      );
}

/// One row of `GET /v1/admin/audit` (newest first).
final class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.at,
    this.target,
    this.details = const {},
  });

  final String id;

  /// e.g. `account.suspend`, `invite.create`, `config.update`.
  final String action;
  final DateTime at;

  /// The account, device, invite, report or flag acted on.
  final String? target;
  final Map<String, String> details;

  JsonMap toJson() => compact({
    'id': id,
    'action': action,
    'at': toWireTime(at),
    'target': target,
    if (details.isNotEmpty) 'details': details,
  });

  factory AuditEntry.fromJson(JsonReader json) {
    final details = json.optObject('details');
    return AuditEntry(
      id: json.nonEmpty('id'),
      action: json.nonEmpty('action'),
      at: json.time('at'),
      target: json.optString('target'),
      details: {
        if (details != null)
          for (final k in details.json.keys) k: details.string(k),
      },
    );
  }
}

/// One outside service the server uses (push, SMS, the TURN relay): whether
/// it is set up and which one. Never a key, a URL or any other secret.
final class AdminIntegrationStatus {
  const AdminIntegrationStatus({
    required this.configured,
    this.provider,
    this.count,
  });

  /// The server has what it needs to use the service.
  final bool configured;

  /// Which one (`fcm`, `bulksmsbd`); null when none is set up or the service
  /// has no named provider.
  final String? provider;

  /// How many addresses it has (the TURN URLs); null when that means
  /// nothing for the service.
  final int? count;

  JsonMap toJson() =>
      compact({'configured': configured, 'provider': provider, 'count': count});

  factory AdminIntegrationStatus.fromJson(JsonReader json) =>
      AdminIntegrationStatus(
        configured: json.boolean('configured'),
        provider: json.optString('provider'),
        count: json.optInt('count'),
      );
}

/// The outside services an operator needs to know about. Set up through the
/// server's environment, so the console can show them but not change them.
final class AdminIntegrations {
  const AdminIntegrations({
    required this.push,
    required this.sms,
    required this.turn,
  });

  /// Wake-ups for phones whose app is closed (FCM).
  final AdminIntegrationStatus push;

  /// The gateway that sends sign-in codes.
  final AdminIntegrationStatus sms;

  /// The call relay for devices that cannot reach each other directly.
  final AdminIntegrationStatus turn;

  JsonMap toJson() => {
    'push': push.toJson(),
    'sms': sms.toJson(),
    'turn': turn.toJson(),
  };

  factory AdminIntegrations.fromJson(JsonReader json) => AdminIntegrations(
    push: AdminIntegrationStatus.fromJson(json.object('push')),
    sms: AdminIntegrationStatus.fromJson(json.object('sms')),
    turn: AdminIntegrationStatus.fromJson(json.object('turn')),
  );
}

/// `GET /v1/admin/config`: no secrets.
final class AdminConfig {
  const AdminConfig({
    required this.serverName,
    required this.version,
    required this.registration,
    required this.maintenance,
    required this.federationEnabled,
    required this.maxAttachmentBytes,
    required this.nodeId,
    this.federationDomain,
    this.integrations,
  });

  final String serverName;
  final String version;
  final RegistrationMode registration;
  final bool maintenance;
  final bool federationEnabled;
  final int maxAttachmentBytes;

  /// The node that answered.
  final String nodeId;
  final String? federationDomain;

  /// The outside services; null when the server does not say (an older
  /// server).
  final AdminIntegrations? integrations;

  JsonMap toJson() => compact({
    'server_name': serverName,
    'version': version,
    'registration': registration.wire,
    'maintenance': maintenance,
    'federation_enabled': federationEnabled,
    'max_attachment_bytes': maxAttachmentBytes,
    'node_id': nodeId,
    'federation_domain': federationDomain,
    'integrations': integrations?.toJson(),
  });

  factory AdminConfig.fromJson(JsonReader json) => AdminConfig(
    serverName: json.string('server_name'),
    version: json.string('version'),
    registration: json.enumValue(
      'registration',
      RegistrationMode.values,
      orElse: RegistrationMode.unknown,
    ),
    maintenance: json.boolean('maintenance'),
    federationEnabled: json.boolean('federation_enabled'),
    maxAttachmentBytes: json.integer('max_attachment_bytes'),
    nodeId: json.string('node_id'),
    federationDomain: json.optString('federation_domain'),
    integrations: switch (json.optObject('integrations')) {
      final integrations? => AdminIntegrations.fromJson(integrations),
      null => null,
    },
  );
}

/// `PATCH /v1/admin/config`: only the fields given change.
final class AdminConfigPatch {
  const AdminConfigPatch({
    this.serverName,
    this.maintenance,
    this.federationEnabled,
  });

  static const maxServerNameLength = 64;

  final String? serverName;
  final bool? maintenance;
  final bool? federationEnabled;

  bool get isEmpty =>
      serverName == null && maintenance == null && federationEnabled == null;

  JsonMap toJson() => compact({
    'server_name': serverName,
    'maintenance': maintenance,
    'federation_enabled': federationEnabled,
  });

  factory AdminConfigPatch.fromJson(JsonReader json) => AdminConfigPatch(
    serverName: json.optString('server_name'),
    maintenance: json.has('maintenance') ? json.boolean('maintenance') : null,
    federationEnabled: json.has('federation_enabled')
        ? json.boolean('federation_enabled')
        : null,
  );
}

/// `GET /v1/admin/feature-flags`: every known flag and its value. Flag
/// names are allow-listed by the server; unknown names are `not_found`.
final class FeatureFlags {
  const FeatureFlags({required this.flags});

  final Map<String, bool> flags;

  JsonMap toJson() => {'flags': flags};

  factory FeatureFlags.fromJson(JsonReader json) {
    final flags = json.object('flags');
    return FeatureFlags(
      flags: {for (final k in flags.json.keys) k: flags.boolean(k)},
    );
  }
}

/// `PUT /v1/admin/feature-flags/{name}`.
final class SetFeatureFlagRequest {
  const SetFeatureFlagRequest({required this.enabled});

  final bool enabled;

  JsonMap toJson() => {'enabled': enabled};

  factory SetFeatureFlagRequest.fromJson(JsonReader json) =>
      SetFeatureFlagRequest(enabled: json.boolean('enabled'));
}

/// `GET /v1/admin/logs`: recent redacted JSON log lines of the answering
/// node, oldest first. The stream route sends the same lines as WS text
/// frames.
final class AdminLogLines {
  const AdminLogLines({required this.lines});

  final List<String> lines;

  JsonMap toJson() => {'lines': lines};

  factory AdminLogLines.fromJson(JsonReader json) =>
      AdminLogLines(lines: json.strings('lines'));
}

/// `POST /v1/admin/purge`: rows removed, by kind.
final class PurgeResult {
  const PurgeResult({required this.removed});

  final Map<String, int> removed;

  JsonMap toJson() => {'removed': removed};

  factory PurgeResult.fromJson(JsonReader json) {
    final removed = json.object('removed');
    return PurgeResult(
      removed: {for (final k in removed.json.keys) k: removed.integer(k)},
    );
  }
}
