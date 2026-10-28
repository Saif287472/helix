import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What one account may do under its plan (ADR-035).
///
/// A module that enforces a limit asks an [EntitlementSource] at the moment it
/// decides, so a plan change needs no job and a downgrade never deletes
/// anything: it only refuses more.
final class Entitlements {
  const Entitlements({
    required this.plan,
    required this.maxDevices,
    required this.attachmentQuotaBytes,
    required this.maxAttachmentBytes,
    required this.attachmentRetention,
    required this.backupMaxBytes,
    required this.backupQuotaBytes,
    this.unlimitedCalls = true,
  });

  final PlanId plan;

  /// Active devices an account may hold.
  final int maxDevices;

  /// Attachment bytes an account may hold on the server.
  final int attachmentQuotaBytes;

  /// The largest single attachment.
  final int maxAttachmentBytes;

  /// How long an attachment stays on the server.
  final Duration attachmentRetention;

  /// The largest single backup media object, and all of them together.
  final int backupMaxBytes;
  final int backupQuotaBytes;

  /// Calls spend no call time (Orbit Premium, and every server without plans).
  /// False on the Free plan while plans are on (ADR-036).
  final bool unlimitedCalls;

  // The limits the server has always had. Free keeps them, except the device
  // count, which is the one limit that tightens when plans are on.
  static const standardMaxDevices = 10;
  static const standardAttachmentQuota = 4 * 1024 * 1024 * 1024;
  static const standardAttachmentRetention = Duration(days: 30);
  static const standardBackupMaxBytes = 100 * 1024 * 1024;
  static const standardBackupQuota = 1024 * 1024 * 1024;

  static const freeMaxDevices = 2;

  /// Premium is these many times the standard size and quota.
  static const premiumAttachmentQuota = 16 * 1024 * 1024 * 1024;
  static const premiumFileSizeFactor = 4;
  static const premiumAttachmentRetention = Duration(days: 90);
  static const premiumBackupMaxBytes = 400 * 1024 * 1024;
  static const premiumBackupQuota = 4 * 1024 * 1024 * 1024;

  /// What every account gets while the operator has not switched plans on
  /// (and on every personal server): the limits as they were before plans.
  /// [maxAttachmentBytes] is `HELIX_MAX_ATTACHMENT_BYTES`.
  factory Entitlements.standard({required int maxAttachmentBytes}) =>
      Entitlements(
        plan: PlanId.free,
        maxDevices: standardMaxDevices,
        attachmentQuotaBytes: standardAttachmentQuota,
        maxAttachmentBytes: maxAttachmentBytes,
        attachmentRetention: standardAttachmentRetention,
        backupMaxBytes: standardBackupMaxBytes,
        backupQuotaBytes: standardBackupQuota,
      );

  /// The Free plan while plans are on.
  factory Entitlements.free({required int maxAttachmentBytes}) => Entitlements(
    plan: PlanId.free,
    maxDevices: freeMaxDevices,
    attachmentQuotaBytes: standardAttachmentQuota,
    maxAttachmentBytes: maxAttachmentBytes,
    attachmentRetention: standardAttachmentRetention,
    backupMaxBytes: standardBackupMaxBytes,
    backupQuotaBytes: standardBackupQuota,
    unlimitedCalls: false,
  );

  /// Orbit Premium. [maxAttachmentBytes] is the Free file size
  /// (`HELIX_MAX_ATTACHMENT_BYTES`), which Premium multiplies.
  factory Entitlements.premium({required int maxAttachmentBytes}) =>
      Entitlements(
        plan: PlanId.premium,
        maxDevices: standardMaxDevices,
        attachmentQuotaBytes: premiumAttachmentQuota,
        maxAttachmentBytes: maxAttachmentBytes * premiumFileSizeFactor,
        attachmentRetention: premiumAttachmentRetention,
        backupMaxBytes: premiumBackupMaxBytes,
        backupQuotaBytes: premiumBackupQuota,
      );

  /// These limits with the operator's overrides on top, by [PlanLimitKey]
  /// wire name (support cases, ADR-035). Unknown names are ignored.
  Entitlements withOverrides(Map<String, int> overrides) {
    if (overrides.isEmpty) return this;
    int pick(PlanLimitKey key, int current) => overrides[key.wire] ?? current;
    return Entitlements(
      plan: plan,
      maxDevices: pick(PlanLimitKey.maxDevices, maxDevices),
      attachmentQuotaBytes: pick(
        PlanLimitKey.attachmentQuotaBytes,
        attachmentQuotaBytes,
      ),
      maxAttachmentBytes: pick(
        PlanLimitKey.maxAttachmentBytes,
        maxAttachmentBytes,
      ),
      attachmentRetention: Duration(
        days: pick(
          PlanLimitKey.attachmentRetentionDays,
          attachmentRetention.inDays,
        ),
      ),
      backupMaxBytes: pick(PlanLimitKey.backupMaxBytes, backupMaxBytes),
      backupQuotaBytes: pick(PlanLimitKey.backupQuotaBytes, backupQuotaBytes),
      unlimitedCalls: unlimitedCalls,
    );
  }

  PlanLimits toLimits() => PlanLimits(
    maxDevices: maxDevices,
    attachmentQuotaBytes: attachmentQuotaBytes,
    maxAttachmentBytes: maxAttachmentBytes,
    attachmentRetentionDays: attachmentRetention.inDays,
    backupMaxBytes: backupMaxBytes,
    backupQuotaBytes: backupQuotaBytes,
  );
}

/// Where a module learns an account's [Entitlements]: the `billing` module.
abstract interface class EntitlementSource {
  Future<Entitlements> forAccount(String accountId);
}
