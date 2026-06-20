import 'dart:io';

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

  test(
    'RemoteCompositionRoot startup state machine - idle until initialize()',
    () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(),
      );
      expect(root.startupState, RemoteStartupState.idle);
      root.dispose();
    },
  );

  test('RemoteCompositionRoot accessors throw before initialize()', () {
    final root = RemoteCompositionRoot.production(
      databaseDirectory: Directory.systemTemp.path,
      devConfig: _devConfig(),
    );
    expect(() => root.database, throwsA(isA<StateError>()));
    expect(() => root.syncEngine, throwsA(isA<StateError>()));
    expect(() => root.keyStorage, throwsA(isA<StateError>()));
    expect(() => root.restClient, throwsA(isA<StateError>()));
    expect(() => root.messagingService, throwsA(isA<StateError>()));
    root.dispose();
  });

  test('withConfig validation rejects empty displayName', () {
    expect(
      () => RemoteCompositionRoot.withConfig(
        const RemoteProductConfig(
          displayName: '',
          packageId: 'com.test',
          secureStoragePrefix: 'helix_remote_v1_',
          methodChannelNamespace: 'ns',
          logNamespace: 'log',
          databaseDirectory: '/tmp',
        ),
        devConfig: _devConfig(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('withConfig validation rejects prefix without trailing underscore', () {
    expect(
      () => RemoteCompositionRoot.withConfig(
        const RemoteProductConfig(
          displayName: 'Test',
          packageId: 'com.test',
          secureStoragePrefix: 'helix_remote_v1',
          methodChannelNamespace: 'ns',
          logNamespace: 'log',
          databaseDirectory: '/tmp',
        ),
        devConfig: _devConfig(),
      ),
      throwsA(isA<StateError>()),
    );
  });

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
