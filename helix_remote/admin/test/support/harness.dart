import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/services/admin_services.dart';
import 'package:helix_admin/src/services/admin_settings.dart';
import 'package:helix_admin/src/services/device_lock.dart';
import 'package:helix_admin/src/services/token_vault.dart';
import 'package:helix_remote_api/v2.dart';

import 'fake_admin_server.dart';

const adminPassword = 'correct horse battery staple';

/// A clock the test moves. It starts at the real time: the API's token
/// check uses the real clock, and a session issued in the past would look
/// expired to it.
final class TestClock {
  TestClock() : _now = DateTime.now();

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

final class FakeDeviceLock implements DeviceLock {
  bool supported = true;
  bool allow = true;
  int prompts = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return allow;
  }
}

/// A log WebSocket the test pushes lines into.
final class FakeLogSocket implements RealtimeSocket {
  FakeLogSocket(this.headers);

  final Map<String, String> headers;
  final StreamController<String> _lines = StreamController();
  bool closedByClient = false;

  @override
  String? get protocol => null;

  @override
  Stream<String> get messages => _lines.stream;

  void push(String line) => _lines.add(line);

  /// The server closes the stream.
  Future<void> serverCloses() => _lines.close();

  @override
  void send(String text) {}

  @override
  Future<void> close([int? code, String? reason]) async {
    closedByClient = true;
    if (!_lines.isClosed) unawaited(_lines.close());
  }

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// Everything a console test needs: the fake server, the in-memory services
/// and helpers to start the app signed out or signed in.
final class AdminHarness {
  AdminHarness() {
    server = FakeAdminServer(now: clock.call);
  }

  final clock = TestClock();
  late final FakeAdminServer server;
  final vault = MemoryTokenVault();
  final settings = MemoryAdminSettings();
  final lock = FakeDeviceLock();

  /// Log sockets opened so far.
  final List<FakeLogSocket> sockets = [];

  /// When set, opening the log socket throws this instead.
  Object? socketError;

  AdminServices services() => AdminServices(
    loadSettings: () async => settings,
    vault: vault,
    deviceLock: lock,
    now: clock.call,
    apiFactory: (baseUrl, {session}) => HelixAdminApi(
      baseUrl: baseUrl,
      httpClient: server.client,
      session: session,
      clientName: 'admin/test',
      retry: RetryPolicy.none,
      sockets: (uri, {required headers, required protocols}) async {
        final error = socketError;
        if (error != null) throw error;
        final socket = FakeLogSocket(headers);
        sockets.add(socket);
        return socket;
      },
    ),
  );

  /// A server with an admin password already set.
  void configured() => server.adminPassword = adminPassword;

  /// Puts a valid saved session in the vault, as a previous run would have.
  void saveSession() {
    configured();
    vault.stored = StoredSession(
      serverUrl: FakeAdminServer.host.toString(),
      session: server.issue(),
    );
    settings.serverUrl = FakeAdminServer.host.toString();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HelixAdminApp(services: services()));
    await tester.pumpAndSettle();
  }

  /// Starts the console already signed in and on the Overview.
  Future<void> startSignedIn(WidgetTester tester) async {
    saveSession();
    await pumpApp(tester);
  }

  /// Opens a place from the header (the test window is wide): `Overview`,
  /// `Users & Devices`, `Invites` or `Ops & Logs`.
  Future<void> goTo(WidgetTester tester, String place) async {
    await tester.tap(
      find.descendant(of: find.byType(AppBar), matching: find.text(place)),
    );
    await tester.pumpAndSettle();
  }

  /// Opens Ops & Logs and one of its sub-tabs: `Reports`, `Audit`, `Logs`
  /// or `Config`.
  Future<void> openOps(WidgetTester tester, String tab) async {
    await goTo(tester, 'Ops & Logs');
    await tester.tap(find.text(tab).first);
    await tester.pumpAndSettle();
  }
}

/// Types [text] into the field whose label is [label].
Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

/// Taps the button (or text) [label].
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Records what the app puts on the clipboard.
List<String> recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}
