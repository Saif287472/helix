import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/widgets/dialogs.dart'
    show secretClipboardLifetime;
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

  /// Runs while the prompt is up (the real one pauses the app on Android).
  void Function()? whilePrompting;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    whilePrompting?.call();
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

  /// Starts it signed in on a phone: the dock and the header gear, not the
  /// header pills.
  Future<void> startPhone(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    saveSession();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HelixAdminApp(services: services()));
    await tester.pumpAndSettle();
  }

  /// Opens a place from the header (the test window is wide): `Overview`,
  /// `Users & Devices`, `Invites`, `Reports` or `Configuration`. The pill bar
  /// scrolls when the places do not fit, and the test font is much wider
  /// than the shipped one, so a later place can be off the edge.
  Future<void> goTo(WidgetTester tester, String place) async {
    final pill = find.descendant(
      of: find.byType(AppBar),
      matching: find.text(place),
    );
    await tester.ensureVisible(pill);
    await tester.tap(pill);
    await tester.pumpAndSettle();
  }

  /// Opens the live log, which comes up as a sheet over Configuration.
  Future<void> openLogSheet(WidgetTester tester) async {
    await goTo(tester, 'Configuration');
    await tapRowAction(tester, 'Show log');
  }

  /// Opens the audit trail, the one system view that is a page of its own.
  Future<void> openAudit(WidgetTester tester) async {
    await goTo(tester, 'Configuration');
    await tapRowAction(tester, 'Open audit');
  }

  /// Taps a button inside a Configuration card, bringing it on screen first.
  /// The page is a lazy list: a card below the fold is not built yet, and one
  /// partly built can still sit under the bottom edge.
  Future<void> tapRowAction(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.dragUntilVisible(
      button,
      find.byType(ListView).first,
      const Offset(0, -150),
    );
    await tester.ensureVisible(button);
    // The scroll only lands on the next frame, and a tap measures the old one.
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Opens Configuration from the gear in the phone header. The window has to
  /// be narrow enough for the dock layout, as `pumpApp` is not.
  Future<void> openConfigWithGear(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Closes an open sheet by tapping the dark area above it.
  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  }

  /// Opens one report from the queue, by the category on its tile. The report
  /// in full, and the ways to work it, come up in a sheet over the queue. When
  /// several reports share a category it opens the first of them.
  Future<void> openReportSheet(WidgetTester tester, String category) async {
    await tester.tap(find.text(category).first);
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
/// What the mocked clipboard holds now (null: nothing was ever put there).
String? clipboardNow;

List<String> recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  // A secret is taken off the clipboard again; the test does not wait a minute.
  secretClipboardLifetime = Duration.zero;
  addTearDown(() => secretClipboardLifetime = const Duration(minutes: 1));
  clipboardNow = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        final text = args['text']! as String;
        clipboardNow = text;
        if (text.isNotEmpty) copied.add(text);
      }
      if (call.method == 'Clipboard.getData') {
        return clipboardNow == null ? null : {'text': clipboardNow};
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
