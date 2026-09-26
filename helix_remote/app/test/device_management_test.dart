// Phase 14 device management UI tests.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/device_management_screen.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'support/group_call_rest_stubs.dart';

// ---------------------------------------------------------------------------
// Stub REST client
// ---------------------------------------------------------------------------

class _StubRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  final List<RemoteDevice> devices;
  final List<String> revokedIds = [];
  final List<String> renamedIds = [];
  final List<String> lostIds = [];
  final List<String> approvedLinks = [];
  final List<String> rejectedLinks = [];

  _StubRestClient({this.devices = const []});

  @override
  set accessToken(String? token) {}

  @override
  Future<void> close() async {}

  @override
  Future<List<RemoteDevice>> listDevices() async => List.from(devices);

  @override
  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async {
    approvedLinks.add('$linkId:$verificationCode');
    return {'status': 'APPROVED'};
  }

  @override
  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async {
    rejectedLinks.add('$linkId:$verificationCode');
    return {'status': 'REJECTED'};
  }

  @override
  Future<void> revokeDevice(String deviceId) async {
    revokedIds.add(deviceId);
    devices.removeWhere((d) => d.deviceId == deviceId);
  }

  @override
  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    renamedIds.add(deviceId);
  }

  @override
  Future<void> reportLostDevice(String deviceId) async {
    lostIds.add(deviceId);
  }

  @override
  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(
    String deviceId,
  ) async => [
    {'type': 'login', 'timestamp': 1700000000000},
  ];

  @override
  dynamic noSuchMethod(Invocation i) async => {};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RemoteDevice _device(String id, String name) => RemoteDevice(
  deviceId: id,
  deviceName: name,
  deviceSigningPublicKey: 'pk',
  deviceAgreementPublicKey: 'ak',
  createdAt: DateTime.now(),
);

Widget _makeApp(_StubRestClient client, {Stream<RemoteSyncChange>? changes}) {
  return MaterialApp(
    localizationsDelegates: HelixLocalizations.localizationsDelegates,
    supportedLocales: HelixLocalizations.supportedLocales,
    home: DeviceManagementScreen(restClient: client, deviceChanges: changes),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('P14-W01 DeviceManagementScreen reachability', () {
    testWidgets('shows device list', (tester) async {
      final client = _StubRestClient(
        devices: [_device('dev-1', 'Alice Phone'), _device('dev-2', 'Tablet')],
      );

      await tester.pumpWidget(_makeApp(client));
      await tester.pump();

      expect(find.text('Alice Phone'), findsOneWidget);
      expect(find.text('Tablet'), findsOneWidget);
    });

    testWidgets('Link New Device approval submits link code', (tester) async {
      final client = _StubRestClient();
      await tester.pumpWidget(_makeApp(client));
      await tester.pump();

      expect(find.text('Link New Device'), findsOneWidget);
      await tester.tap(find.text('Link New Device'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'link_123');
      await tester.enterText(find.byType(TextField).at(1), '654321');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(client.approvedLinks, contains('link_123:654321'));
      expect(find.text('Device link approved.'), findsOneWidget);
    });

    testWidgets(
      'popup menu shows Rename, Security History, Report Lost, Revoke',
      (tester) async {
        final client = _StubRestClient(devices: [_device('dev-1', 'My Phone')]);

        await tester.pumpWidget(_makeApp(client));
        await tester.pump();

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();

        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Security History'), findsOneWidget);
        expect(find.text('Report Lost'), findsOneWidget);
        expect(find.text('Revoke'), findsOneWidget);
      },
    );

    testWidgets('security history dialog shows events', (tester) async {
      final client = _StubRestClient(devices: [_device('dev-1', 'Sec Phone')]);

      await tester.pumpWidget(_makeApp(client));
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Security History'));
      await tester.pumpAndSettle();

      expect(find.text('Sec Phone Security'), findsOneWidget);
      expect(find.text('Key fingerprint'), findsOneWidget);
      expect(find.text('login'), findsOneWidget);
    });
  });

  group('P14-A01 live device list via sync stream', () {
    testWidgets('reloads device list when devices area changes', (
      tester,
    ) async {
      final changeController = StreamController<RemoteSyncChange>.broadcast();
      final client = _StubRestClient(
        devices: [_device('dev-1', 'Initial Device')],
      );

      await tester.pumpWidget(
        _makeApp(client, changes: changeController.stream),
      );
      await tester.pump();
      expect(find.text('Initial Device'), findsOneWidget);

      // Add new device and emit change
      client.devices.add(_device('dev-2', 'New Device'));
      changeController.add(
        const RemoteSyncChange(areas: {RemoteSyncChangeArea.devices}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('New Device'), findsOneWidget);

      changeController.close();
    });

    testWidgets('ignores non-device sync changes', (tester) async {
      final changeController = StreamController<RemoteSyncChange>.broadcast();
      final client = _StubRestClient(devices: []);

      await tester.pumpWidget(
        _makeApp(client, changes: changeController.stream),
      );
      await tester.pump();
      expect(find.text('No devices found'), findsOneWidget);

      // Emit message change — should not reload
      changeController.add(
        const RemoteSyncChange(areas: {RemoteSyncChangeArea.messages}),
      );
      await tester.pump();

      expect(find.text('No devices found'), findsOneWidget);
      changeController.close();
    });
  });
}
