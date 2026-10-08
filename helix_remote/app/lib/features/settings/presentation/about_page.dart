import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Help and about: the version, the server, the legal documents,
/// the open-source licences and the crash-report choice.
///
/// Crash reports are off unless the person turns them on **and** the server
/// accepts them. A report is the kind of error, the app version and the
/// platform, and nothing else.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(aboutAppProvider);
    final server = ref.watch(serverDetailsProvider);
    final crash = ref.watch(crashReportsOptInProvider).value ?? false;

    return HelixSettingsScaffold(
      title: 'Help and about',
      body: ListView(
        children: [
          HelixSettingsSection(
            title: app.name,
            children: [
              HelixSettingsTile(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: app.version,
              ),
              HelixSettingsTile(
                icon: Icons.dns_outlined,
                title: 'Server',
                subtitle: switch (server) {
                  AsyncData(:final value) => '${value.name} (${value.host})',
                  AsyncError() => 'Could not be reached',
                  _ => 'Checking...',
                },
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Legal',
            children: [
              HelixSettingsTile(
                icon: Icons.gavel_outlined,
                title: 'Terms of Service and Privacy Policy',
                subtitle: switch (server) {
                  AsyncData(:final value) =>
                    'Terms ${value.termsVersion}, privacy ${value.privacyVersion}',
                  _ => null,
                },
                showChevron: true,
                onTap: () => context.push(RoutePaths.legal),
              ),
              HelixSettingsTile(
                icon: Icons.description_outlined,
                title: 'Open-source licences',
                showChevron: true,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: app.name,
                  applicationVersion: app.version,
                ),
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Diagnostics',
            footer:
                'A crash report says what kind of error happened, the app '
                'version and the platform. It has no message text, no '
                'account details and no stack trace. It is never sent unless '
                'you turn this on.',
            children: [
              switch (server) {
                AsyncData(:final value) when value.allowsCrashReports =>
                  HelixSettingsSwitchTile(
                    icon: Icons.bug_report_outlined,
                    title: 'Send crash reports',
                    value: crash,
                    onChanged: ref
                        .read(settingsActionsProvider)
                        .setCrashReportsOptIn,
                  ),
                AsyncData() => const HelixSettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Send crash reports',
                  subtitle: 'This server does not accept crash reports',
                ),
                _ => const HelixSettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Send crash reports',
                  subtitle: 'Checking what the server accepts...',
                ),
              },
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
