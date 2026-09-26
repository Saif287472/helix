// Phase 3 Step 3.3 — the Config controls that were SnackBar-only.
//
// Maintenance Mode, the admin-password change, the data purge and the support
// bundle each had a button in the console and nothing behind it: the handler
// was a `SnackBar` claiming success without touching the network. These tests
// pin that they now call the server, and that they report what actually
// happened rather than asserting success unconditionally.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/config_tab.dart';

/// Records what the console asked for, and answers from a script.
class _RecordingClient extends AdminClient {
  _RecordingClient({
    required this.onRequest,
    this.statusCode = 200,
    this.body = const <String, dynamic>{},
  }) : super(baseUrl: 'https://helix.test', token: 'tok');

  final void Function(String method, String path) onRequest;
  final int statusCode;
  final Map<String, dynamic> body;

  final List<String> paths = <String>[];

  /// Whether a specific request was made. The Config screen also fetches
  /// feature flags in `initState`, so [paths] is never empty and assertions
  /// have to name the action they care about.
  bool called(String pathAndMethod) => paths.contains(pathAndMethod);

  @override
  Future<void> setMaintenanceMode(bool enabled) async {
    paths.add('POST /ops/maintenance');
    onRequest('POST', '/ops/maintenance');
    if (statusCode != 200) {
      throw const AdminRequestException('Maintenance mode change failed');
    }
  }

  @override
  Future<void> changeAdminPin({
    required String currentPassword,
    required String newPassword,
  }) async {
    paths.add('POST /ops/admin-pin');
    onRequest('POST', '/ops/admin-pin');
    if (statusCode != 200) {
      throw const AdminRequestException('The current password is incorrect');
    }
  }

  @override
  Future<Map<String, int>> purgeData() async {
    paths.add('POST /ops/purge');
    onRequest('POST', '/ops/purge');
    if (statusCode != 200) {
      throw const AdminRequestException('Purge failed');
    }
    final removed = body['removed'];
    if (removed is! Map) return const <String, int>{};
    return removed.map(
      (k, v) => MapEntry(k as String, v is int ? v : 0),
    );
  }

  @override
  Future<Map<String, dynamic>> getSupportDiagnostic() async {
    paths.add('GET /ops/support-diagnostic');
    onRequest('GET', '/ops/support-diagnostic');
    if (statusCode != 200) {
      throw const AdminRequestException('Support bundle failed');
    }
    return body;
  }

  @override
  Future<Map<String, bool>> getFeatureFlags() async {
    paths.add('GET /ops/feature-flags');
    onRequest('GET', '/ops/feature-flags');
    return const <String, bool>{'crash_reporting_upload': false};
  }
}

const _defaultConfig = <String, dynamic>{
  'server_name': 'Test Node',
  'max_server_name_length': 60,
  'default_server_name': 'Private Server #1234',
  'server_id': 'srv_real',
  'server_public_key': 'pub_real',
  'public_base_url': 'https://helix.test',
  'maintenance_mode': false,
};

Widget _configTab({
  required AdminClient client,
  Map<String, dynamic>? config,
  ValueChanged<bool>? onAppLockChanged,
}) {
  return ConfigTab(
    config: config ?? _defaultConfig,
    client: client,
    federationDomainController: TextEditingController(),
    federationAddressController: TextEditingController(),
    federationDirectoryController: TextEditingController(),
    onSetWorldwideMode: (_) {},
    onSaveServerName: (name) async => name,
    onAppLockChanged: onAppLockChanged,
  );
}

/// The Config screen is a long scrollable column, so a control near the bottom
/// is off-screen in the default test viewport. Tapping it would then fail for
/// layout reasons rather than logic ones, so every test here gets a viewport
/// tall enough to hold the whole card stack.
Future<void> pumpConfig(
  WidgetTester tester,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

_RecordingClient _silentClient({
  int statusCode = 200,
  Map<String, dynamic>? body,
}) {
  return _RecordingClient(
    onRequest: (method, path) {},
    statusCode: statusCode,
    body: body ?? const <String, dynamic>{},
  );
}

/// The Switch that belongs to the row labelled [label]. Each Config row is
/// `Row(children: [Expanded(Column(Text(title))), Switch()])`.
Finder switchFor(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );

/// The property value rendered under [label] in the identity grid.
String propValueFor(WidgetTester tester, String label) {
  final card = find
      .ancestor(of: find.text(label), matching: find.byType(Container))
      .first;
  return tester
      .widgetList<SelectableText>(
        find.descendant(of: card, matching: find.byType(SelectableText)),
      )
      .first
      .data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('maintenance mode', () {
    testWidgets('renders the server-reported state, not a local guess', (
      tester,
    ) async {
      final client = _silentClient();
      await pumpConfig(
        tester,
        _configTab(
          client: client,
          config: const {'server_name': 'N', 'maintenance_mode': true},
        ),
      );

      expect(
        tester.widget<Switch>(switchFor('Server Maintenance Mode')).value,
        isTrue,
        reason: 'the server says maintenance is on; the switch must agree',
      );
    });

    testWidgets('toggling calls the server rather than only setState', (
      tester,
    ) async {
      final client = _silentClient();
      await pumpConfig(tester, _configTab(client: client));

      await tester.tap(switchFor('Server Maintenance Mode'));
      await tester.pumpAndSettle();

      expect(client.paths, contains('POST /ops/maintenance'));
    });

    testWidgets('a refused change rolls the switch back and says why', (
      tester,
    ) async {
      final client = _silentClient(statusCode: 500);
      await pumpConfig(tester, _configTab(client: client));

      await tester.tap(switchFor('Server Maintenance Mode'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not change maintenance mode'),
        findsOneWidget,
      );
      expect(
        tester.widget<Switch>(switchFor('Server Maintenance Mode')).value,
        isFalse,
        reason: 'a switch must not stay on for a change the server refused',
      );
    });
  });

  group('admin password change', () {
    Future<void> openDialog(WidgetTester tester, _RecordingClient client) async {
      await pumpConfig(tester, _configTab(client: client));
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(
      WidgetTester tester, {
      required String current,
      required String next,
      required String confirm,
    }) async {
      await tester.enterText(
        find.byKey(const Key('admin_pin_current')),
        current,
      );
      await tester.enterText(find.byKey(const Key('admin_pin_new')), next);
      await tester.enterText(
        find.byKey(const Key('admin_pin_confirm')),
        confirm,
      );
      await tester.tap(find.byKey(const Key('admin_pin_submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('opens a dialog that validates before submitting', (
      tester,
    ) async {
      final client = _silentClient();
      await openDialog(tester, client);

      expect(find.byKey(const Key('admin_pin_submit')), findsOneWidget);
      expect(client.called('POST /ops/admin-pin'), isFalse);

      // Only the current password filled in: rejected locally, no request.
      await fill(
        tester,
        current: 'current-password',
        next: '',
        confirm: '',
      );

      expect(find.textContaining('at least 6 characters'), findsOneWidget);
      expect(client.called('POST /ops/admin-pin'), isFalse);
    });

    testWidgets('a mismatched confirmation blocks the request', (
      tester,
    ) async {
      final client = _silentClient();
      await openDialog(tester, client);

      await fill(
        tester,
        current: 'current-password',
        next: 'a-new-password',
        confirm: 'a-different-password',
      );

      expect(find.textContaining('do not match'), findsOneWidget);
      expect(client.called('POST /ops/admin-pin'), isFalse);
    });

    testWidgets('a valid submission calls the server and confirms', (
      tester,
    ) async {
      final client = _silentClient();
      await openDialog(tester, client);

      await fill(
        tester,
        current: 'current-password',
        next: 'a-new-password',
        confirm: 'a-new-password',
      );

      expect(client.paths, contains('POST /ops/admin-pin'));
      expect(find.textContaining('Admin password changed'), findsOneWidget);
    });

    testWidgets("the server's rejection is shown, not swallowed", (
      tester,
    ) async {
      final client = _silentClient(statusCode: 401);
      await openDialog(tester, client);

      await fill(
        tester,
        current: 'wrong-password',
        next: 'a-new-password',
        confirm: 'a-new-password',
      );

      expect(
        find.textContaining('current password is incorrect'),
        findsOneWidget,
      );
    });
  });

  group('data purge', () {
    Future<void> openDialog(WidgetTester tester, _RecordingClient client) async {
      await pumpConfig(tester, _configTab(client: client));
      await tester.tap(find.text('Purge Data'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for confirmation before deleting anything', (
      tester,
    ) async {
      final client = _silentClient();
      await openDialog(tester, client);

      expect(find.text('Purge expired data?'), findsOneWidget);
      expect(client.called('POST /ops/purge'), isFalse, reason: 'nothing sent yet');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.called('POST /ops/purge'), isFalse);
    });

    testWidgets('reports the real per-table counts', (tester) async {
      final client = _silentClient(
        body: const {
          'removed': {'outbox_dead_letter': 3, 'outbox_failed': 1},
          'total': 4,
        },
      );
      await openDialog(tester, client);

      await tester.tap(find.widgetWithText(FilledButton, 'Purge'));
      await tester.pumpAndSettle();

      expect(client.paths, contains('POST /ops/purge'));
      expect(find.textContaining('Purged 4 rows'), findsOneWidget);
      expect(find.textContaining('3 outbox_dead_letter'), findsOneWidget);
    });

    testWidgets('says so plainly when there was nothing to purge', (
      tester,
    ) async {
      final client = _silentClient(
        body: const {'removed': <String, int>{}, 'total': 0},
      );
      await openDialog(tester, client);

      await tester.tap(find.widgetWithText(FilledButton, 'Purge'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing to purge'), findsOneWidget);
    });

    testWidgets('a failure is reported instead of claiming success', (
      tester,
    ) async {
      final client = _silentClient(statusCode: 500);
      await openDialog(tester, client);

      await tester.tap(find.widgetWithText(FilledButton, 'Purge'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not purge data'), findsOneWidget);
    });
  });

  group('support bundle', () {
    testWidgets('copies the bundle the server built', (tester) async {
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final client = _silentClient(
        body: const {
          'readiness': {'api_ready': true},
        },
      );
      await pumpConfig(tester, _configTab(client: client));

      await tester.tap(find.byKey(const Key('config_copy_support_bundle')));
      await tester.pumpAndSettle();

      expect(client.paths, contains('GET /ops/support-diagnostic'));
      expect(copied, hasLength(1));
      expect(copied.single, contains('api_ready'));
    });
  });

  group('app lock', () {
    testWidgets('defaults to off rather than claiming to be on', (
      tester,
    ) async {
      await pumpConfig(tester, _configTab(client: _silentClient()));

      expect(
        tester
            .widget<Switch>(switchFor('Device Biometric / PIN Lock'))
            .value,
        isFalse,
        reason: 'the default used to be true, so the switch displayed "on" '
            'for an operator who had never enabled it',
      );
    });

    testWidgets('toggling reports upwards', (tester) async {
      bool? reported;
      await pumpConfig(
        tester,
        _configTab(
          client: _silentClient(),
          onAppLockChanged: (v) => reported = v,
        ),
      );

      await tester.tap(switchFor('Device Biometric / PIN Lock'));
      await tester.pumpAndSettle();

      expect(reported, isTrue);
    });
  });

  group('identity fields', () {
    testWidgets('never invents a server id or public key', (tester) async {
      await pumpConfig(
        tester,
        _configTab(
          client: _silentClient(),
          config: const {
            'server_name': 'N',
            'server_id': 'unknown',
            'server_public_key': 'unknown',
          },
        ),
      );

      expect(propValueFor(tester, 'SERVER ID'), equals('Not available'));
      expect(
        propValueFor(tester, 'SERVER PUBLIC KEY'),
        equals('Not available'),
      );
      expect(find.textContaining('srv_alpha'), findsNothing);
      expect(find.textContaining('pub_9b14c'), findsNothing);
    });

    testWidgets('a real server id and key are shown as-is', (tester) async {
      await pumpConfig(
        tester,
        _configTab(
          client: _silentClient(),
          config: const {
            'server_name': 'N',
            'server_id': 'srv_actual',
            'server_public_key': 'pub_actual',
          },
        ),
      );

      expect(propValueFor(tester, 'SERVER ID'), equals('srv_actual'));
      expect(propValueFor(tester, 'SERVER PUBLIC KEY'), equals('pub_actual'));
    });
  });
}
