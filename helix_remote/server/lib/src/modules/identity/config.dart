import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';

/// The identity module's own settings (`HELIX_PHONE_PEPPER`, SMS, terms).
final class IdentityConfig {
  IdentityConfig._({
    required this.phonePepper,
    required this.phoneKey,
    required this.sms,
    required this.termsVersion,
    required this.globalMode,
    required this.jwtKeys,
    required this.activeJwtKid,
    required this.otpResendAfter,
    required this.inactiveDeviceDays,
    required this.smsDailyLimit,
    required this.smsCountries,
  });

  /// Key for the stored phone hash. Kept outside the database, so a stolen
  /// database does not let anyone test numbers against stored hashes.
  final Uint8List phonePepper;

  /// `HELIX_PHONE_KEY` (base64url, 32 random bytes): encrypts the full phone
  /// numbers apps report, for the operator console (ADR-030). Unset, the
  /// default: no number is kept beyond its hash and last four digits.
  final Uint8List? phoneKey;
  final SmsProvider sms;
  final String termsVersion;
  final bool globalMode;
  final Map<String, Uint8List> jwtKeys;
  final String activeJwtKid;

  /// Minimum gap between two codes to one number (`HELIX_OTP_RESEND_SECONDS`,
  /// default 30).
  final Duration otpResendAfter;

  /// `HELIX_DEVICE_INACTIVE_DAYS`: devices unused for longer are revoked
  /// (never an account's most recently used one). 0, the default: never.
  final int inactiveDeviceDays;

  static const minInactiveDeviceDays = 14;
  static const maxInactiveDeviceDays = 3650;

  /// `HELIX_SMS_DAILY_LIMIT`: codes this cluster sends in a day, whichever
  /// numbers they are for, 1 to 1000000. A pumping script rotating through
  /// proxies can otherwise spend the provider's balance on thousands of
  /// numbers nobody owns; when the balance runs out, real sign-ups fail with
  /// `sms_unavailable`. Default 500.
  final int smsDailyLimit;

  /// `HELIX_SMS_COUNTRIES`: the calling country codes that may ask for a code,
  /// as bare digits (`880`, `880,971`; a leading `+` is accepted). `*` means
  /// every country, and is stored as the empty set. Default `880`:
  /// international and premium-rate numbers are the ones worth pumping.
  final Set<String> smsCountries;

  static const defaultSmsDailyLimit = 500;
  static const defaultSmsCountries = '880';

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

    final phoneKeyRaw = env['HELIX_PHONE_KEY']?.trim() ?? '';
    Uint8List? phoneKey;
    if (phoneKeyRaw.isNotEmpty) {
      try {
        phoneKey = decodeBytes(phoneKeyRaw);
        if (phoneKey.length != 32) {
          problems.add('HELIX_PHONE_KEY must be 32 bytes (base64url)');
        }
      } on Object {
        problems.add('HELIX_PHONE_KEY must be base64url');
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
    final inactiveRaw = env['HELIX_DEVICE_INACTIVE_DAYS']?.trim();
    final inactive = inactiveRaw == null || inactiveRaw.isEmpty
        ? 0
        : int.tryParse(inactiveRaw);
    if (inactive == null ||
        (inactive != 0 &&
            (inactive < minInactiveDeviceDays ||
                inactive > maxInactiveDeviceDays))) {
      problems.add(
        'HELIX_DEVICE_INACTIVE_DAYS must be 0 (off) or '
        '$minInactiveDeviceDays..$maxInactiveDeviceDays',
      );
    }

    final smsDailyRaw = env['HELIX_SMS_DAILY_LIMIT']?.trim();
    final smsDaily = smsDailyRaw == null || smsDailyRaw.isEmpty
        ? defaultSmsDailyLimit
        : int.tryParse(smsDailyRaw);
    // A zero limit would be a bucket that never refills (and a division by
    // zero in its retry time); an operator who wants no texts leaves
    // HELIX_SMS_PROVIDER at none.
    if (smsDaily == null || smsDaily < 1 || smsDaily > 1000000) {
      problems.add('HELIX_SMS_DAILY_LIMIT must be 1..1000000');
    }
    // Unset or blank is the default; `*` turns the list off; otherwise bare
    // country codes, comma separated.
    final countriesRaw =
        (env['HELIX_SMS_COUNTRIES']?.trim().isNotEmpty ?? false)
        ? env['HELIX_SMS_COUNTRIES']!.trim()
        : defaultSmsCountries;
    final countries = countriesRaw == '*'
        ? <String>{}
        : {
            for (final part in countriesRaw.split(','))
              if (part.trim().isNotEmpty) part.trim().replaceFirst('+', ''),
          };
    if (countriesRaw != '*' &&
        (countries.isEmpty ||
            countries.any((c) => !RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(c)))) {
      problems.add(
        'HELIX_SMS_COUNTRIES must be * or bare country codes, '
        'e.g. 880 or 880,971',
      );
    }
    if (problems.isNotEmpty) throw ConfigError(problems);

    return IdentityConfig._(
      phonePepper: pepper,
      phoneKey: phoneKey,
      sms: provider,
      termsVersion: env['HELIX_TERMS_VERSION']?.trim().isNotEmpty == true
          ? env['HELIX_TERMS_VERSION']!.trim()
          : HelixLegalDocuments.termsVersion,
      globalMode: config.globalMode,
      jwtKeys: config.jwtKeys,
      activeJwtKid: config.activeJwtKid,
      otpResendAfter: Duration(seconds: resend!),
      inactiveDeviceDays: inactive!,
      smsDailyLimit: smsDaily!,
      smsCountries: countries,
    );
  }

  /// Whether [e164] may ask for a code ([smsCountries]; empty allows all).
  bool allowsCountry(String e164) {
    if (smsCountries.isEmpty) return true;
    // E.164 country codes are prefix-free (1 to 3 digits), so a number
    // belongs to a listed country exactly when one listed code is a prefix
    // of its digits.
    final digits = e164.startsWith('+') ? e164.substring(1) : e164;
    for (var length = math.min(3, digits.length); length >= 1; length--) {
      if (smsCountries.contains(digits.substring(0, length))) return true;
    }
    return false;
  }
}
