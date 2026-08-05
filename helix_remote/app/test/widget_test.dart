import 'dart:io';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/main.dart';

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
    await tester.pumpWidget(HelixRemoteApp(root: root));

    expect(find.text('Helix Remote'), findsOneWidget);
    expect(find.text('Starting Helix Remote...'), findsOneWidget);

    root.dispose();
  });

  testWidgets('a very large system text-size setting is clamped, not applied '
      'unbounded - several fixed-size layout elements (nav bar, chips, quick '
      'action bubbles) clip or overflow well past that', (
    WidgetTester tester,
  ) async {
    final root = RemoteCompositionRoot.production(
      databaseDirectory: Directory.systemTemp.path,
      devConfig: _devConfig(),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: HelixRemoteApp(root: root),
      ),
    );

    final resolvedScaler = MediaQuery.textScalerOf(
      tester.element(find.text('Helix Remote')),
    );
    expect(resolvedScaler.scale(1.0), closeTo(1.3, 0.001));

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
    await tester.pumpWidget(
      const HelixRemoteConfigurationErrorApp(
        message: 'HELIX_REMOTE_HOST is required.',
      ),
    );

    expect(find.text('Remote configuration required'), findsOneWidget);
    expect(find.textContaining('HELIX_REMOTE_HOST'), findsOneWidget);
  });
}
