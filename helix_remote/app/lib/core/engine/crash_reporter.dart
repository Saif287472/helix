import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/app_info.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show CrashReport;

/// Opt-in crash reports.
///
/// A report is **the exception's type, the app version and the platform** and
/// nothing else: no message text, no stack trace, no account, no server
/// address. It is sent only when the person turned it on in Settings > About
/// and the server's `crash_reporting_upload` flag is on; otherwise [report]
/// does nothing at all. At most one report goes out per minute.
abstract final class CrashReporter {
  static Future<void> Function(String errorType)? _sink;
  static DateTime? _lastAt;

  static const _gap = Duration(minutes: 1);

  /// Called by the zone handler and `FlutterError.onError`. Never throws and
  /// never waits.
  static void report(Object error) {
    final sink = _sink;
    if (sink == null) return;
    final now = DateTime.now();
    final last = _lastAt;
    if (last != null && now.difference(last) < _gap) return;
    _lastAt = now;
    unawaited(sink(error.runtimeType.toString()).catchError((Object _) {}));
  }

  @visibleForTesting
  static void resetForTest() {
    _sink = null;
    _lastAt = null;
  }
}

/// Connects [CrashReporter] to the account's settings and server. Read once
/// when the app starts.
final crashReporterInstallProvider = Provider<void>((ref) {
  CrashReporter._sink = (type) async {
    final opted = await ref
        .read(localSettingsProvider)
        .get(AppSettings.crashReportsOptIn);
    if (!opted) return;
    final runtime = await ref.read(runtimeProvider.future);
    final info = await runtime.api.ops.serverInfo();
    if (!(info.features['crash_reporting_upload'] ?? false)) return;
    await runtime.api.ops.crashReport(
      CrashReport(
        name: type,
        fields: {
          'app_version': kAppVersion,
          'platform': defaultTargetPlatform.name,
        },
      ),
    );
  };
  ref.onDispose(() => CrashReporter._sink = null);
});
