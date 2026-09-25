// Phase 03 — HXA-006, HXA-023.
//
// Verifies:
//   P03-W01  resetRequired state renders the Reset button (no dead-end screen).
//   P03-W02  authenticatedAndSyncing renders the Syncing screen, not the ready screen.
//   P05-W01  fresh-device recovery is visibly disabled and accepts no code.
//   P05-W02  tapping the invalid-invite icon shows the reason (not a silent
//            no-op - ScaffoldMessenger.of needs a context from inside the
//            MaterialApp this State builds, not the State's own context).
//   P05-W03  a pasted full join link in the invite field is reduced to the
//            bare code, since admins hand out links but this field expects
//            only the code.
//   P05-W04  the phone field's error text isn't limited to one line -
//            server-provided errors (e.g. an SMS gateway's rejection
//            reason) are longer than a plain validation label and must not
//            be truncated with an ellipsis.

import 'dart:io';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/main.dart';
import 'package:helix_remote/app/helix_remote_app_shell.dart';

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

    await tester.pumpWidget(
      HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
    );
    // Allow the async boot to complete (it throws and transitions to resetRequired).
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Reset Required'), findsOneWidget);
    expect(find.text('Reset Helix Remote'), findsOneWidget);
    expect(find.text('Database key is missing'), findsOneWidget);

    await root.dispose();
  });

  testWidgets(
    'P03-W03: tapping Reset Helix Remote actually shows the confirmation '
    'dialog',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p03_w03_');
      addTearDown(() => dir.deleteSync(recursive: true));

      File('${dir.path}${Platform.pathSeparator}helix_remote.db').createSync();

      final root = RemoteCompositionRoot.withConfig(
        _productConfig(dir.path),
        devConfig: _devConfig(dir.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('Reset Helix Remote'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm destructive reset'), findsOneWidget);

      await root.dispose();
    },
  );

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

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );

      // Reach setup, then drive authenticatedAndSyncing directly so this
      // widget assertion does not depend on live runtime I/O.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Helix Global Server').evaluate().isNotEmpty) break;
      }
      root.setAuthenticated('tok-w02');
      await tester.pump();

      // Pump a few frames for state to settle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // authenticatedAndSyncing now shows HomeScreen immediately (offline-first
      // design, _buildSyncingScreen removed). The setup screen must be gone.
      expect(find.text('Helix Global Server'), findsNothing);
      // HomeScreen bottom nav is visible with its tab labels.
      expect(find.text('Chats'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P05-W01: unauthenticated state renders new Welcome SetupScreen and no legacy screens',
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

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Helix Global Server').evaluate().isNotEmpty) break;
      }

      // The new welcome flow is rendered
      expect(find.text('Helix Global Server'), findsOneWidget);
      expect(find.text('Others'), findsOneWidget);
      expect(find.text('Request OTP'), findsOneWidget);
      // The offline escape hatch was removed; Global signup is phone + OTP.
      expect(find.text('Continue offline for now'), findsNothing);

      // Legacy screens are gone entirely
      expect(find.text('Server invitation code'), findsNothing);
      expect(find.text('Restore existing account'), findsNothing);
      expect(find.text('Restore account'), findsNothing);
      expect(find.text('Restore code'), findsNothing);
      expect(find.text('Enter your restore code'), findsNothing);
      expect(find.text('Unavailable'), findsNothing);

      expect(root.startupState, RemoteStartupState.unauthenticated);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P05-W02: invalid code in CodeEntryStep displays validation error',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p05_w02_');
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

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Others').evaluate().isNotEmpty) break;
      }

      await tester.tap(find.text('Others'));
      await tester.pumpAndSettle();

      // Submit empty code to trigger validation error
      await tester.ensureVisible(find.text('Verify & Connect'));
      await tester.tap(find.text('Verify & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a code or link.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P05-W03: pasting a full join link into the code entry field extracts the bare code',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p05_w03_');
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

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Others').evaluate().isNotEmpty) break;
      }

      await tester.tap(find.text('Others'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(
        find.byType(TextFormField).first,
        'https://hr.agiletechbd.com/join?invite=UiFzSP3Vgp6XA7fEby6-IPb5i',
      );
      await tester.pump();

      expect(find.text('UiFzSP3Vgp6XA7fEby6-IPb5i'), findsOneWidget);
      expect(find.textContaining('hr.agiletechbd.com'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P05-W04: the phone field allows multi-line error text instead of truncating it',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p05_w04_');
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

      await tester.pumpWidget(
        HelixRemoteAppShell(home: HelixRemoteApp(root: root)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Request OTP').evaluate().isNotEmpty) break;
      }

      final phoneField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      // InputDecoration.errorMaxLines defaults to null, which truncates
      // errorText to a single line with an ellipsis - a long server error
      // (e.g. "Failed to send verification SMS: ...") would be cut off.
      expect(phoneField.decoration?.errorMaxLines, isNotNull);
      expect(phoneField.decoration!.errorMaxLines! > 1, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
