import 'package:flutter/material.dart' show showLicensePage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Help and about, drawn by `orbit_ui`'s [orbit.AboutScreen]: the
/// app and its server, the legal documents, and a line saying that problem
/// reports go to the server (the anomaly log: every build, no switch).
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(aboutAppProvider);
    final server = ref.watch(serverDetailsProvider).value;

    return orbit.AboutScreen(
      model: orbit.AboutModel(
        versionLabel: 'Version ${app.version}',
        serverName: server?.name ?? '',
        serverHost: server?.host ?? '',
        termsVersion: server?.termsVersion ?? '',
        privacyVersion: server?.privacyVersion ?? '',
        problemReports:
            'When something goes wrong, Orbit tells your server what and '
            'where, so it can be fixed',
      ),
      actions: orbit.AboutActions(
        onOpenDoc: (_) => context.push(RoutePaths.legal),
        onOpenAdvanced: () => context.push(RoutePaths.advanced),
        onOpenLicences: () => showLicensePage(
          context: context,
          applicationName: app.name,
          applicationVersion: app.version,
        ),
      ),
    );
  }
}
