// Phase 03 — HXA-006, HXA-023.
//
// Verifies:
//   P03-W01  resetRequired state renders the Reset button (no dead-end screen).
//   P03-W02  authenticatedAndSyncing renders the Syncing screen, not the ready screen.
//   P05-W01  fresh-device recovery is visibly disabled and accepts no code.

import 'dart:io';

import 'package:flutter/widgets.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/main.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

RemoteDevelopmentConfig _devConfig(String dir) => RemoteDevelopmentConfig(
  profile: RemoteRuntimeProfile.localWindows,
  restBaseUri: Uri.parse('http://127.0.0.1:8080'),
  webSocketUri: Uri.parse('ws://127.0.0.1:8080/api/v1/ws'),
  allowInsecureTransport: true,
  backendHostMode: 'same-pc',
  requestTimeoutMs: 5000,
  reconnectPolicy: const ReconnectPolicy(),
  databaseDirectory: dir,
  attachmentCacheDir: '$dir/attachments_cache',
  diagnosticLevel: DiagnosticLevel.info,
);

RemoteProductConfig _productConfig(String dir) => RemoteProductConfig(
  displayName: 'Helix Remote',
  packageId: 'com.helix.remote',
  secureStoragePrefix: 'helix_remote_v1_',
  methodChannelNamespace: 'com.helix.remote',
  logNamespace: 'helix_remote',
  databaseDirectory: dir,
);

void main() {
  testWidgets('P03-W01: resetRequired state shows Reset button and title', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('p03_w01_');
    addTearDown(() => dir.deleteSync(recursive: true));

    // A pre-existing DB file with no db_key triggers resetRequired.
    File('${dir.path}${Platform.pathSeparator}helix_remote.db').createSync();

    final root = RemoteCompositionRoot.withConfig(
      _productConfig(dir.path),
      devConfig: _devConfig(dir.path),
      keyValueStore: _InMemoryKeyValueStore(),
    );

    await tester.pumpWidget(HelixRemoteApp(root: root));
    // Allow the async boot to complete (it throws and transitions to resetRequired).
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Reset Required'), findsOneWidget);
    expect(find.text('Reset Helix Remote'), findsOneWidget);
    expect(find.text('Database key is missing'), findsOneWidget);

    await root.dispose();
  });

  testWidgets(
    'P03-W02: authenticatedAndSyncing renders HomeScreen (offline-first; no separate syncing screen)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p03_w02_');
      addTearDown(() {
        if (dir.existsSync()) {
          try {
            dir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      final store = _InMemoryKeyValueStore();

      final root = RemoteCompositionRoot.withConfig(
        _productConfig(dir.path),
        devConfig: _devConfig(dir.path),
        keyValueStore: store,
      );

      await tester.pumpWidget(HelixRemoteApp(root: root));

      // Reach setup, then drive authenticatedAndSyncing directly so this
      // widget assertion does not depend on live runtime I/O.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Create new account').evaluate().isNotEmpty) break;
      }
      root.setAuthenticated('tok-w02');
      await tester.pump();

      // Pump a few frames for state to settle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // authenticatedAndSyncing now shows HomeScreen immediately (offline-first
      // design, _buildSyncingScreen removed). The setup screen must be gone.
      expect(find.text('Create new account'), findsNothing);
      // HomeScreen bottom nav is visible with its tab labels.
      expect(find.text('Chats'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P05-W01: setup recovery is disabled instead of accepting restore codes',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p05_w01_');
      addTearDown(() {
        if (dir.existsSync()) {
          try {
            dir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      final root = RemoteCompositionRoot.withConfig(
        _productConfig(dir.path),
        devConfig: _devConfig(dir.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );

      await tester.pumpWidget(HelixRemoteApp(root: root));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Create new account').evaluate().isNotEmpty) break;
      }

      expect(find.text('Create new account'), findsOneWidget);
      expect(find.text('Restore existing account unavailable'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Restore account'), findsNothing);
      expect(find.text('Restore code'), findsNothing);
      expect(find.text('Enter your restore code'), findsNothing);

      await tester.tap(find.text('Restore existing account unavailable'));
      await tester.pump();

      expect(find.text('Restore account'), findsNothing);
      expect(find.text('Restore code'), findsNothing);
      expect(root.startupState, RemoteStartupState.unauthenticated);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
