import 'package:flutter/material.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote/services/telemetry_consent.dart';
import 'package:helix_remote/services/telemetry_reporter.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Crash-report and analytics consent, and the local error log.
///
/// Consent defaults to off and these switches are the only way telemetry
/// reaches the server; each change is persisted and applied to the live
/// reporter immediately.
class DiagnosticsSettingsPage extends StatefulWidget {
  const DiagnosticsSettingsPage({super.key, required this.onExportLog});

  /// Shares or shows the local error log (owned by the settings screen,
  /// which handles the per-platform share quirks).
  final Future<void> Function() onExportLog;

  @override
  State<DiagnosticsSettingsPage> createState() =>
      _DiagnosticsSettingsPageState();
}

class _DiagnosticsSettingsPageState extends State<DiagnosticsSettingsPage> {
  TelemetryConsent _consent = const TelemetryConsent();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    const TelemetryConsentStore().read().then((consent) {
      if (mounted) setState(() => _consent = consent);
    });
  }

  Future<void> _setConsent(TelemetryConsent consent) async {
    final messenger = ScaffoldMessenger.of(context);
    final previous = _consent;
    setState(() {
      _busy = true;
      _consent = consent;
    });
    try {
      await const TelemetryConsentStore().write(consent);
      TelemetryReporter.instance.configure(consent: consent);
      messenger.showSnackBar(
        const SnackBar(content: Text('Telemetry preferences saved.')),
      );
    } catch (_) {
      if (mounted) setState(() => _consent = previous);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reporter = TelemetryReporter.instance;
    return SettingsPage(
      title: 'Diagnostics',
      children: [
        SettingsSection(
          title: 'Help improve Helix',
          footer: reporter.canReportCrashes != _consent.crashReporting
              ? 'Reporting is not available right now: the reporter has no sink configured. The preference is saved and will apply once a connection is established.'
              : null,
          children: [
            SettingsSwitchTile(
              icon: Icons.bug_report_outlined,
              color: HelixColorTokens.cFFF97316,
              title: 'Send crash reports',
              subtitle:
                  "Redacted crash details go only to the server you are connected to, and land in that server's own log. Off means nothing is ever sent.",
              value: _consent.crashReporting,
              onChanged: _busy
                  ? null
                  : (v) => _setConsent(
                      TelemetryConsent(
                        crashReporting: v,
                        minimalAnalytics: _consent.minimalAnalytics,
                      ),
                    ),
            ),
            SettingsSwitchTile(
              icon: Icons.analytics_outlined,
              color: HelixColorTokens.cFF0EA5E9,
              title: 'Send minimal analytics',
              subtitle: _consent.crashReporting || _consent.minimalAnalytics
                  ? 'Only the categories listed in the privacy policy, never message content.'
                  : 'No usage data is sent.',
              value: _consent.minimalAnalytics,
              onChanged: _busy
                  ? null
                  : (v) => _setConsent(
                      TelemetryConsent(
                        crashReporting: _consent.crashReporting,
                        minimalAnalytics: v,
                      ),
                    ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Error log',
          footer:
              'The log stays on this phone. Exporting it lets you send it to '
              'support; it is cleared once exported.',
          children: [
            SettingsTile(
              icon: Icons.ios_share_outlined,
              color: HelixColorTokens.cFF6D6AAE,
              title: 'Export error log',
              onTap: widget.onExportLog,
            ),
          ],
        ),
      ],
    );
  }
}
