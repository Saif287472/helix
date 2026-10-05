import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/platform/qr_encoder.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:helix_remote/features/devices/application/devices_gateway.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/features/devices/presentation/approve_device_page.dart';
import 'package:helix_remote/features/devices/presentation/devices_page.dart';
import 'package:helix_remote/features/devices/presentation/link_this_device_page.dart';
import 'package:helix_remote/features/devices/presentation/security_activity_page.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_api/v2.dart' show NetworkException;
import 'package:helix_remote_crypto/v2.dart' show LinkCode;
import 'package:helix_remote_ui/helix_remote_ui.dart' show HelixQrDisplay;

import '../support/a3b_fakes.dart';

void main() {
  group('Devices page', () {
    testWidgets('lists this device first, with platform and last seen', (
      tester,
    ) async {
      final devices = FakeDevicesGateway();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);

      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.textContaining('This device'), findsOneWidget);
      expect(find.text('Office laptop'), findsOneWidget);
      expect(
        find.textContaining('Windows - Last active 2 days ago'),
        findsOneWidget,
      );
      // It refreshed from the server when it opened.
      expect(devices.calls, contains('refresh'));
    });

    testWidgets('renames a device', (tester) async {
      final devices = FakeDevicesGateway();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);

      await tester.tap(find.text('Office laptop'));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Desk PC');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(devices.calls, contains('rename:d2:Desk PC'));
    });

    testWidgets('removing a device asks first, and says what it costs', (
      tester,
    ) async {
      final devices = FakeDevicesGateway();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);

      await tester.tap(find.text('Office laptop'));
      await settle(tester);
      await tester.tap(find.text('Remove this device'));
      await settle(tester);
      expect(find.textContaining('lose its messages'), findsOneWidget);
      expect(devices.calls.where((c) => c.startsWith('revoke')), isEmpty);

      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(devices.calls, contains('revoke:d2:plain'));
      expect(find.text('Device removed.'), findsOneWidget);
    });

    testWidgets('lost or stolen tells the server why', (tester) async {
      final devices = FakeDevicesGateway();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);
      await tester.tap(find.text('Office laptop'));
      await settle(tester);
      await tester.tap(find.text('Lost or stolen'));
      await settle(tester);
      await tester.tap(find.text('Remove it'));
      await settle(tester);
      expect(devices.calls, contains('revoke:d2:lost'));
    });

    testWidgets('this device cannot be removed from here', (tester) async {
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: FakeDevicesGateway()),
      );
      await settle(tester);
      await tester.tap(find.text('Pixel 8'));
      await settle(tester);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Remove this device'), findsNothing);
    });

    testWidgets('sign out all others needs confirmation', (tester) async {
      final devices = FakeDevicesGateway();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);
      await reveal(tester, find.text('Sign out all other devices'));
      await tester.tap(find.text('Sign out all other devices'));
      await settle(tester);
      expect(find.text('Sign out all other devices?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(devices.calls, isNot(contains('revokeOthers')));

      await tester.tap(find.text('Sign out all other devices'));
      await settle(tester);
      await tester.tap(find.text('Sign them out'));
      await settle(tester);
      expect(devices.calls, contains('revokeOthers'));
      expect(find.text('Signed out 1 other device.'), findsOneWidget);
    });

    testWidgets('offline: says so and offers a retry', (tester) async {
      final devices = FakeDevicesGateway()
        ..refreshFails = const NetworkException();
      await pumpPage(
        tester,
        const DevicesPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Security activity', () {
    testWidgets('lists events and marks key resets', (tester) async {
      await pumpPage(
        tester,
        const SecurityActivityPage(),
        overrides: a3bOverrides(devices: FakeDevicesGateway()),
      );
      await settle(tester);
      expect(find.text('A device was added'), findsOneWidget);
      expect(find.text('Your account key was reset'), findsOneWidget);
      expect(find.byIcon(Icons.priority_high), findsOneWidget);
    });

    testWidgets('empty log has an empty state', (tester) async {
      final devices = FakeDevicesGateway()..events = const [];
      await pumpPage(
        tester,
        const SecurityActivityPage(),
        overrides: a3bOverrides(devices: devices),
      );
      await settle(tester);
      expect(find.text('Nothing to show'), findsOneWidget);
    });
  });

  group('Approve a new device', () {
    Future<(FakeDevicesGateway, FakeDeviceAuthenticator)> open(
      WidgetTester tester, {
      bool scanner = false,
    }) async {
      final devices = FakeDevicesGateway();
      final auth = FakeDeviceAuthenticator();
      await pumpPage(
        tester,
        const ApproveDevicePage(),
        overrides: a3bOverrides(
          devices: devices,
          auth: auth,
          extra: [
            qrScannerBuilderProvider.overrideWithValue(
              scanner ? (context, onCode) => _AutoScan(onCode) : null,
            ),
          ],
        ),
      );
      await settle(tester);
      return (devices, auth);
    }

    Future<void> paste(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('Continue'));
      await settle(tester);
    }

    testWidgets('a code that is not a Helix link is refused', (tester) async {
      final (devices, _) = await open(tester);
      devices.inspectFails = LinkProblem.notACode;
      await paste(tester, 'hello');
      expect(find.textContaining('not a Helix link code'), findsOneWidget);
      expect(devices.approved, isNull);
    });

    testWidgets('a code for another server is refused', (tester) async {
      final (devices, _) = await open(tester);
      devices.inspectFails = LinkProblem.otherServer;
      await paste(tester, 'helix-link:1:x');
      expect(find.textContaining('different server'), findsOneWidget);
    });

    testWidgets('shows what is being approved and the check number', (
      tester,
    ) async {
      await open(tester);
      await paste(tester, 'helix-link:1:ok');
      expect(find.text('Approve this device?'), findsOneWidget);
      expect(find.textContaining('helix.example.org'), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      expect(find.textContaining('do not approve it'), findsOneWidget);
    });

    testWidgets('approval needs the phone unlock; a refusal sends nothing', (
      tester,
    ) async {
      final (devices, auth) = await open(tester);
      auth.passes = false;
      await paste(tester, 'helix-link:1:ok');
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(auth.asked, hasLength(1));
      expect(devices.calls, isNot(contains('approve')));
      expect(find.textContaining('phone\'s own unlock'), findsOneWidget);
    });

    testWidgets('approving sends once the unlock passes', (tester) async {
      final (devices, auth) = await open(tester);
      devices.holdApprove = Completer<void>();
      await paste(tester, 'helix-link:1:ok');
      await tester.tap(find.text('Approve'));
      await settle(tester);
      // Busy: a second tap changes nothing.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      devices.holdApprove!.complete();
      await settle(tester);
      expect(auth.asked, hasLength(1));
      expect(devices.approved, 'helix-link:1:ok');
      expect(find.textContaining('is joining your account'), findsOneWidget);
    });

    testWidgets('no screen lock on the phone: approval still needs a tap', (
      tester,
    ) async {
      final (devices, auth) = await open(tester);
      auth.available = false;
      await paste(tester, 'helix-link:1:ok');
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(auth.asked, isEmpty);
      expect(devices.approved, isNotNull);
    });

    testWidgets('an expired code is explained', (tester) async {
      final (devices, _) = await open(tester);
      devices.approveFails = LinkProblem.expired;
      await paste(tester, 'helix-link:1:ok');
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('scanning with a camera reaches the same review', (
      tester,
    ) async {
      final (devices, _) = await open(tester, scanner: true);
      await settle(tester);
      expect(devices.calls, contains('inspect'));
      expect(find.text('Approve this device?'), findsOneWidget);
    });

    testWidgets('without a camera only the paste field is offered', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(_AutoScan), findsNothing);
      expect(find.text('Or paste the code'), findsOneWidget);
    });
  });

  group('Link this device', () {
    testWidgets('shows a QR code and the check number, then signs in', (
      tester,
    ) async {
      final devices = FakeDevicesGateway();
      final container = ProviderContainer(
        overrides: a3bOverrides(
          devices: devices,
          extra: [engineConfigNameOverride],
        ),
      );
      addTearDown(container.dispose);
      await pumpPage(
        tester,
        const LinkThisDevicePage(),
        container: container,
        stubs: [RoutePaths.home],
      );
      await settle(tester);

      expect(devices.calls, contains('beginLink'));
      expect(find.byType(HelixQrDisplay), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      // The restore step is asked for before the engine signs in, so the
      // router needs no second hop.
      expect(container.read(postSignInProvider), PostSignInStep.offerRestore);

      devices.session!.done.complete();
      await settle(tester);
      expect(container.read(postSignInProvider), PostSignInStep.offerRestore);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('an expired code can be replaced', (tester) async {
      final devices = FakeDevicesGateway();
      final container = ProviderContainer(
        overrides: a3bOverrides(
          devices: devices,
          extra: [engineConfigNameOverride],
        ),
      );
      addTearDown(container.dispose);
      await pumpPage(tester, const LinkThisDevicePage(), container: container);
      await settle(tester);

      devices.session!.done.completeError(
        const LinkProblemException(LinkProblem.expired),
      );
      await settle(tester);
      expect(find.textContaining('expired'), findsWidgets);
      expect(container.read(postSignInProvider), PostSignInStep.none);

      await tester.tap(find.text('Show a new code'));
      await settle(tester);
      expect(devices.calls.where((c) => c == 'beginLink'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('offline says so', (tester) async {
      final devices = FakeDevicesGateway()..beginFails = LinkProblem.offline;
      await pumpPage(
        tester,
        const LinkThisDevicePage(),
        overrides: a3bOverrides(
          devices: devices,
          extra: [engineConfigNameOverride],
        ),
      );
      await settle(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });
  });

  group('helpers', () {
    test('the check number is stable and six digits', () {
      final code = LinkCode(
        serverOrigin: 'https://helix.example.org',
        linkId: '0192a4f0-0000-7000-8000-000000000001',
        ephemeralKey: List.filled(32, 7),
      );
      final a = linkCheckNumber(code);
      expect(a, matches(RegExp(r'^\d{3} \d{3}$')));
      expect(linkCheckNumber(code), a);
      final other = LinkCode(
        serverOrigin: 'https://helix.example.org',
        linkId: '0192a4f0-0000-7000-8000-000000000002',
        ephemeralKey: List.filled(32, 7),
      );
      expect(linkCheckNumber(other), isNot(a));
    });

    test('a link code encodes to a square QR matrix', () {
      final matrix = encodeQr('helix-link:1:https://helix.example.org:abc:def');
      expect(matrix.size, greaterThanOrEqualTo(21));
      expect(matrix.modules.length, matrix.size * matrix.size);
      // Finder pattern: the top-left corner module is dark.
      expect(matrix.at(0, 0), isTrue);
    });
  });
}

/// A stand-in camera that "reads" a code as soon as it appears.
class _AutoScan extends StatefulWidget {
  const _AutoScan(this.onCode);

  final ValueChanged<String> onCode;

  @override
  State<_AutoScan> createState() => _AutoScanState();
}

class _AutoScanState extends State<_AutoScan> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onCode('helix-link:scanned'),
    );
  }

  @override
  Widget build(BuildContext context) => const Text('fake camera');
}
