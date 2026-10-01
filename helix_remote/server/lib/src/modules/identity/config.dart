import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';

/// The identity module's own settings (`HELIX_PHONE_PEPPER`, SMS, terms).
final class IdentityConfig {
  IdentityConfig._({
    required this.phonePepper,
    required this.sms,
    required this.termsVersion,
    required this.globalMode,
    required this.jwtKeys,
    required this.activeJwtKid,
    required this.otpResendAfter,
  });

  /// Key for the stored phone hash. Kept outside the database, so a stolen
  /// database does not let anyone test numbers against stored hashes.
  final Uint8List phonePepper;
  final SmsProvider sms;
  final String termsVersion;
  final bool globalMode;
  final Map<String, Uint8List> jwtKeys;
  final String activeJwtKid;

  /// Minimum gap between two codes to one number (`HELIX_OTP_RESEND_SECONDS`,
  /// default 30).
  final Duration otpResendAfter;

  static const accessLifetime = Duration(minutes: 15);
  static const refreshLifetime = Duration(days: 60);
  static const verificationLifetime = Duration(minutes: 15);
  static const signInTokenLifetime = Duration(minutes: 5);
  static const challengeLifetime = Duration(minutes: 5);
  static const linkLifetime = Duration(minutes: 10);
  static const otpLifetime = Duration(minutes: 10);
  static const otpMaxAttempts = 5;
  static const inviteLifetime = Duration(days: 7);
  static const recoveryLifetime = Duration(hours: 48);

  /// Builds from [config]. [sms] overrides the provider (tests).
  factory IdentityConfig.from(ServerConfig config, {SmsProvider? sms}) {
    final problems = <String>[];
    final env = config.env;
    final pepperRaw = env['HELIX_PHONE_PEPPER']?.trim() ?? '';
    Uint8List pepper = Uint8List(0);
    if (pepperRaw.isEmpty) {
      problems.add(
        'HELIX_PHONE_PEPPER is required (base64url, at least 32 random bytes)',
      );
    } else {
      try {
        pepper = decodeBytes(pepperRaw);
        if (pepper.length < 32) {
          problems.add('HELIX_PHONE_PEPPER must be at least 32 bytes');
        }
      } on Object {
        problems.add('HELIX_PHONE_PEPPER must be base64url');
      }
    }

    SmsProvider provider = sms ?? const NoSmsProvider();
    if (sms == null) {
      switch (env['HELIX_SMS_PROVIDER']?.trim() ?? 'none') {
        case 'none':
          break;
        case 'bulksmsbd':
          final key = env['HELIX_SMS_API_KEY']?.trim() ?? '';
          final sender = env['HELIX_SMS_SENDER_ID']?.trim() ?? '';
          if (key.isEmpty || sender.isEmpty) {
            problems.add(
              'HELIX_SMS_PROVIDER=bulksmsbd needs HELIX_SMS_API_KEY and HELIX_SMS_SENDER_ID',
            );
          }
          provider = BulkSmsBdProvider(apiKey: key, senderId: sender);
        default:
          problems.add('HELIX_SMS_PROVIDER must be none or bulksmsbd');
      }
    } else if (sms is RecordingSmsProvider && !config.devMode) {
      problems.add('the recording SMS provider is only allowed in dev mode');
    }
    if (config.globalMode && !provider.isConfigured) {
      problems.add(
        'HELIX_GLOBAL_MODE=true needs an SMS provider (HELIX_SMS_PROVIDER)',
      );
    }
    final resendRaw = env['HELIX_OTP_RESEND_SECONDS']?.trim();
    final resend = resendRaw == null || resendRaw.isEmpty
        ? 30
        : int.tryParse(resendRaw);
    if (resend == null || resend < 0 || resend > 600) {
      problems.add('HELIX_OTP_RESEND_SECONDS must be 0..600');
    }
    if (problems.isNotEmpty) throw ConfigError(problems);

    return IdentityConfig._(
      phonePepper: pepper,
      sms: provider,
      termsVersion: env['HELIX_TERMS_VERSION']?.trim().isNotEmpty == true
          ? env['HELIX_TERMS_VERSION']!.trim()
          : '2026-09',
      globalMode: config.globalMode,
      jwtKeys: config.jwtKeys,
      activeJwtKid: config.activeJwtKid,
      otpResendAfter: Duration(seconds: resend!),
    );
  }
}
