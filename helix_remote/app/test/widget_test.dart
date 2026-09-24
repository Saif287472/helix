import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/main.dart';
import 'package:helix_remote/app/helix_remote_app_shell.dart';

RemoteDevelopmentConfig _devConfig() => RemoteDevelopmentConfig(
  profile: RemoteRuntimeProfile.localWindows,
  restBaseUri: Uri.parse('http://127.0.0.1:8080'),
  webSocketUri: Uri.parse('ws://127.0.0.1:8080/api/v1/ws'),
  allowInsecureTransport: true,
  backendHostMode: 'same-pc',
  requestTimeoutMs: 15000,
  reconnectPolicy: const ReconnectPolicy(),
  databaseDirectory: Directory.systemTemp.path,
  attachmentCacheDir: '${Directory.systemTemp.path}/attachments_cache',
  diagnosticLevel: DiagnosticLevel.info,
);

void main() {
  testWidgets('HelixRemoteApp launches and shows loading state', (
    WidgetTester tester,
  ) async {
    final root = RemoteCompositionRoot.production(
      databaseDirectory: Directory.systemTemp.path,
      devConfig: _devConfig(),
    );
    await tester.pumpWidget(
      HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
    );

    expect(find.text('HELIX'), findsOneWidget);
    expect(find.text('Deploying Helix…'), findsOneWidget);

    root.dispose();
  });

  // Removed (2026-06-24): "startup state machine - idle until initialize()" —
  // exact duplicate of composition_root_test.dart "Startup state is idle before initialize()"
  //
  // Removed (2026-06-24): "accessors throw before initialize()" —
  // subset duplicate of composition_root_test.dart "Service accessors throw StateError before
  // initialize()", which checks 9 accessors vs this test's 5.
  //
  // Removed (2026-06-24): "withConfig validation rejects empty displayName" —
  // exact duplicate of composition_root_test.dart "P5-014: throws StateError when displayName is empty"
  //
  // Removed (2026-06-24): "withConfig validation rejects prefix without trailing underscore" —
  // exact duplicate of composition_root_test.dart "P5-014: throws StateError when
  // secureStoragePrefix lacks trailing _"

  testWidgets('configuration errors render a stable startup screen', (
    WidgetTester tester,
  ) async {
    // Wrapped, because this is a page rather than an application — it used to
    // supply its own shell and read its copy from the context above it.
    await tester.pumpWidget(
      const HelixRemoteAppShell(
        home: HelixRemoteConfigurationErrorApp(
          message: 'HELIX_REMOTE_HOST is required.',
        ),
      ),
    );

    expect(find.text('Remote configuration required'), findsOneWidget);
    expect(find.textContaining('HELIX_REMOTE_HOST'), findsOneWidget);
  });
}
