import 'package:helix_remote_backend/src/env_sanitize.dart';

/// A feature whose environment variables must be either all set or all
/// unset. A partial set (one present, one missing) is never intentional -
/// it means a deploy typo'd or half-copied a variable name, and the feature
/// would otherwise silently fall back to disabled instead of failing loudly.
class ConditionalEnvGroup {
  const ConditionalEnvGroup(this.label, this.vars, {this.anyOf = const []});

  /// Human-readable name shown in warnings/errors, e.g. "SMS delivery".
  final String label;

  /// Env var names that make up this feature. All-or-nothing.
  final List<String> vars;

  /// Alternative ways to supply one thing, of which exactly one is needed
  /// once the feature is switched on at all. FCM credentials are either a
  /// service-account key or a pre-obtained access token; demanding both
  /// would be wrong, and demanding neither would let a deployment configure
  /// a project ID and no way to authenticate against it.
  final List<String> anyOf;

  /// Every variable this feature reads, in the order an operator should see
  /// them listed.
  List<String> get allVars => [...vars, ...anyOf];
}

/// Backend features gated behind a group of env vars. Each one already has
/// an inert fallback (Noop provider, disabled warning) when fully unset -
/// see bin/server.dart - so only a *partial* set is treated as an error.
const List<ConditionalEnvGroup> remoteConditionalEnvGroups = [
  ConditionalEnvGroup('SMS delivery (BulkSMSBD)', [
    'HELIX_REMOTE_SMS_API_KEY',
    'HELIX_REMOTE_SMS_SENDER_ID',
  ]),
  ConditionalEnvGroup(
    'FCM push notifications',
    ['HELIX_REMOTE_FCM_PROJECT_ID'],
    anyOf: [
      'HELIX_REMOTE_FCM_SERVICE_ACCOUNT',
      'HELIX_REMOTE_FCM_ACCESS_TOKEN',
    ],
  ),
  ConditionalEnvGroup('TURN relay (WebRTC calls)', [
    'HELIX_REMOTE_TURN_URL',
    'HELIX_REMOTE_TURN_SECRET',
  ]),
];

/// Env vars required on every boot, dev or not.
const List<String> remoteRequiredEnvVars = ['HELIX_REMOTE_JWT_SECRET'];

/// Result of validating the process environment at startup. Aggregates every
/// problem found in one pass so an operator sees the full list of what's
/// wrong instead of fixing one variable, restarting, and hitting the next.
class StartupEnvResult {
  const StartupEnvResult({required this.fatalErrors, required this.warnings});

  /// Problems that must stop the process from starting: a required variable
  /// is missing, or a conditional group is partially configured.
  final List<String> fatalErrors;

  /// Non-fatal notices: an optional feature's env vars are all unset, so it
  /// will run with its inert fallback (no SMS/FCM/TURN provider).
  final List<String> warnings;

  bool get isFatal => fatalErrors.isNotEmpty;
}

/// Validates [env] (normally `Platform.environment`) against the required
/// and conditional variable groups above. Pure and side-effect free so it
/// can be unit tested without touching the real process environment.
///
/// [devMode] suppresses "feature disabled" warnings (dev boxes routinely run
/// without SMS/FCM/TURN configured) but never suppresses fatal errors - a
/// half-configured pair or a missing required secret is a mistake in dev
/// too, and dev is exactly where it's cheap to catch.
StartupEnvResult validateStartupEnv(
  Map<String, String> env, {
  required bool devMode,
}) {
  final fatal = <String>[];
  final warnings = <String>[];

  for (final name in remoteRequiredEnvVars) {
    if (sanitizeEnvValue(env[name]).isEmpty) {
      fatal.add('$name is required but not set.');
    }
  }

  final jwtSecret = sanitizeEnvValue(env['HELIX_REMOTE_JWT_SECRET']);
  if (jwtSecret.isNotEmpty && !devMode && jwtSecret.length < 32) {
    fatal.add(
      'HELIX_REMOTE_JWT_SECRET must be at least 32 bytes outside '
      'HELIX_REMOTE_DEV_MODE=1 (got ${jwtSecret.length}).',
    );
  }

  for (final group in remoteConditionalEnvGroups) {
    final values = [for (final v in group.vars) sanitizeEnvValue(env[v])];
    final alternatives = [
      for (final v in group.anyOf) sanitizeEnvValue(env[v]),
    ];
    final setCount = values.where((v) => v.isNotEmpty).length;
    final alternativesSet = alternatives.where((v) => v.isNotEmpty).length;

    if (setCount == 0 && alternativesSet == 0) {
      if (!devMode) {
        warnings.add(
          '${group.label} is not configured '
          '(${group.allVars.join(', ')} not set). This feature is disabled.',
        );
      }
      continue;
    }

    // Something is set, so the operator meant to turn this on. Report every
    // way in which they did not finish, rather than the first.
    final missingVars = [
      for (var i = 0; i < group.vars.length; i++)
        if (values[i].isEmpty) group.vars[i],
    ];
    if (missingVars.isNotEmpty) {
      fatal.add(
        '${group.label} is partially configured: '
        '${missingVars.join(', ')} missing while the rest of '
        '${group.allVars.join(', ')} is set. Set all of them or none.',
      );
    }
    if (group.anyOf.isNotEmpty && alternativesSet == 0) {
      fatal.add(
        '${group.label} is partially configured: one of '
        '${group.anyOf.join(' or ')} is required once '
        '${group.vars.join(', ')} is set.',
      );
    }
  }

  return StartupEnvResult(fatalErrors: fatal, warnings: warnings);
}
