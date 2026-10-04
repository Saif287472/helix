import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/settings/application/media_policy_sync.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/presentation/about_page.dart';
import 'package:helix_remote/features/settings/presentation/account_page.dart';
import 'package:helix_remote/features/settings/presentation/advanced_page.dart';
import 'package:helix_remote/features/settings/presentation/blocked_page.dart';
import 'package:helix_remote/features/settings/presentation/change_password_page.dart';
import 'package:helix_remote/features/settings/presentation/chats_page.dart';
import 'package:helix_remote/features/settings/presentation/legal_page.dart';
import 'package:helix_remote/features/settings/presentation/notifications_page.dart';
import 'package:helix_remote/features/settings/presentation/privacy_page.dart';
import 'package:helix_remote/features/settings/presentation/settings_tab.dart';
import 'package:helix_remote/features/settings/presentation/storage_page.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EngineSettings, MediaSettings;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import '../support/a3b_fakes.dart';

void main() {
  group('Settings tab', () {
    testWidgets('shows who you are and opens every page', (tester) async {
      useTallWindow(tester);
      final paths = [
        RoutePaths.account,
        RoutePaths.privacy,
        RoutePaths.notifications,
        RoutePaths.chats,
        RoutePaths.devices,
        RoutePaths.backup,
        RoutePaths.storage,
        RoutePaths.about,
        RoutePaths.advanced,
        RoutePaths.profile,
      ];
      final router = await pumpPage(
        tester,
        const SettingsTab(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: paths,
      );
      await settle(tester);

      expect(find.text('Anna Khan'), findsOneWidget);
      expect(find.text('helix.example.org'), findsOneWidget);
      for (final (label, path) in [
        ('Account', RoutePaths.account),
        ('Privacy', RoutePaths.privacy),
        ('Notifications', RoutePaths.notifications),
        ('Chats', RoutePaths.chats),
        ('Devices', RoutePaths.devices),
        ('Backup', RoutePaths.backup),
        ('Storage and data', RoutePaths.storage),
        ('Help and about', RoutePaths.about),
        ('Advanced', RoutePaths.advanced),
      ]) {
        await tester.tap(find.text(label));
        await settle(tester);
        expect(find.text('stub:$path'), findsOneWidget, reason: label);
        router.pop();
        await settle(tester);
      }
      // There is no host-your-own-server guide anywhere in Settings.
      expect(find.textContaining('Host your own'), findsNothing);
      expect(find.textContaining('host your own'), findsNothing);
    });

    testWidgets('the header opens the profile', (tester) async {
      await pumpPage(
        tester,
        const SettingsTab(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: [RoutePaths.profile],
      );
      await settle(tester);
      await tester.tap(find.text('Anna Khan'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.profile}'), findsOneWidget);
    });
  });

  group('Account', () {
    Future<FakeSettingsGateway> open(
      WidgetTester tester, {
      FakeSettingsGateway? gateway,
      FakeShareAdapter? share,
    }) async {
      useTallWindow(tester);
      final g = gateway ?? FakeSettingsGateway();
      await pumpPage(
        tester,
        const AccountPage(),
        overrides: a3bOverrides(settingsGateway: g, share: share),
        stubs: [
          RoutePaths.changePassword,
          RoutePaths.profile,
          RoutePaths.devicesActivity,
        ],
      );
      await settle(tester);
      return g;
    }

    testWidgets('shows the phone number masked and the ~name', (tester) async {
      await open(tester);
      expect(find.text('+88017*****01'), findsOneWidget);
      expect(find.text('~anna.k'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
    });

    testWidgets('without a password it offers to set one', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01');
      await open(tester, gateway: g);
      expect(find.text('Set a password'), findsOneWidget);
      expect(find.textContaining('Not set'), findsOneWidget);
    });

    testWidgets('offline: the page says so and can retry', (tester) async {
      final g = FakeSettingsGateway()..accountFails = const NetworkException();
      await open(tester, gateway: g);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('sign out is confirmed and warns about the wipe', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.textContaining('deletes its messages'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Sign out?'), findsNothing);
    });

    testWidgets('export shares a file named for the day', (tester) async {
      final share = FakeShareAdapter();
      final g = await open(tester, share: share);
      await tester.tap(find.text('Export my data'));
      await settle(tester);
      expect(g.calls, contains('export'));
      expect(
        share.shared.single.filename,
        'helix-account-export-2026-10-03.json',
      );
      expect(share.shared.single.mimeType, 'application/json');
    });

    testWidgets('an export that cannot be shared says so', (tester) async {
      final share = FakeShareAdapter()..result = false;
      await open(tester, share: share);
      await tester.tap(find.text('Export my data'));
      await settle(tester);
      expect(find.textContaining('could not be shared'), findsOneWidget);
    });

    testWidgets('an export that fails offline says so', (tester) async {
      final g = FakeSettingsGateway()..exportFails = const NetworkException();
      await open(tester, gateway: g);
      await tester.tap(find.text('Export my data'));
      await settle(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    testWidgets(
      'deleting needs the word DELETE, and nothing is sent without it',
      (tester) async {
        final g = await open(tester);
        await reveal(tester, find.text('Delete my account'));
        await tester.tap(find.text('Delete my account'));
        await settle(tester);
        expect(find.text('Delete your account?'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.enterText(find.byType(TextField), 'delete');
        await tester.tap(find.text('Delete account'));
        await settle(tester);
        expect(g.calls, isNot(contains('deleteAccount')));
        expect(
          find.textContaining('Type DELETE in capital letters'),
          findsOneWidget,
        );
      },
    );

    testWidgets('delete can start with an export', (tester) async {
      final share = FakeShareAdapter();
      final g = await open(tester, share: share);
      await reveal(tester, find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      await tester.tap(find.text('Export first'));
      await settle(tester);
      expect(g.calls, contains('export'));
      expect(share.shared, hasLength(1));
      expect(find.text('Type DELETE to confirm'), findsOneWidget);
    });

    testWidgets('a refused delete is explained', (tester) async {
      final g = FakeSettingsGateway()
        ..deleteFails = const ApiException(
          status: 503,
          code: ErrorCode.maintenance,
        );
      await open(tester, gateway: g);
      await reveal(tester, find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.tap(find.text('Delete account'));
      await settle(tester);
      expect(g.calls, contains('deleteAccount'));
      expect(find.textContaining('not available right now'), findsOneWidget);
    });
  });

  group('Change password', () {
    Future<FakeSettingsGateway> open(
      WidgetTester tester, {
      FakeSettingsGateway? gateway,
    }) async {
      useTallWindow(tester);
      final g = gateway ?? FakeSettingsGateway();
      await pumpPage(
        tester,
        const ChangePasswordPage(),
        overrides: a3bOverrides(settingsGateway: g),
      );
      await settle(tester);
      return g;
    }

    Future<void> fill(
      WidgetTester tester, {
      String current = 'old password',
      String next = 'new password 1',
      String? confirm,
    }) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Current password'),
        current,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        next,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm new password'),
        confirm ?? next,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await settle(tester);
    }

    testWidgets('changes the password with the current one', (tester) async {
      final g = await open(tester);
      await fill(tester);
      expect(g.changedTo, 'new password 1');
      expect(g.changedCurrent, 'old password');
      expect(find.textContaining('Your password is saved'), findsOneWidget);
    });

    testWidgets('the passwords are hidden until asked', (tester) async {
      await open(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'New password'))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.text('Show passwords'));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'New password'))
            .obscureText,
        isFalse,
      );
    });

    testWidgets('a wrong current password is said plainly', (tester) async {
      final g = FakeSettingsGateway()
        ..changePasswordFails = const ApiException(
          status: 401,
          code: ErrorCode.invalidCredentials,
        );
      await open(tester, gateway: g);
      await fill(tester);
      expect(find.text('That is not your current password.'), findsOneWidget);
      expect(find.textContaining('saved'), findsNothing);
    });

    testWidgets('a lockout says how long to wait', (tester) async {
      final g = FakeSettingsGateway()
        ..changePasswordFails = ApiException(
          status: 429,
          code: ErrorCode.passwordLocked,
          details: {
            'locked_until': DateTime(
              2026,
              10,
              3,
              10,
              14,
            ).toUtc().millisecondsSinceEpoch,
          },
        );
      await open(tester, gateway: g);
      await fill(tester);
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
      expect(find.textContaining('minutes'), findsOneWidget);
    });

    testWidgets('offline says so', (tester) async {
      final g = FakeSettingsGateway()
        ..changePasswordFails = const NetworkException();
      await open(tester, gateway: g);
      await fill(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    testWidgets('a mismatch and a short password never reach the engine', (
      tester,
    ) async {
      final g = await open(tester);
      await fill(tester, next: 'short', confirm: 'different');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(g.calls, isNot(contains('changePassword')));
    });

    testWidgets('a first password needs no current one', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01');
      await open(tester, gateway: g);
      expect(find.text('Current password'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'first password',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm new password'),
        'first password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Set password'));
      await settle(tester);
      expect(g.changedTo, 'first password');
      expect(g.changedCurrent, isNull);
    });

    testWidgets('a linked device is asked for the number once', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(
          phoneMasked: '*******0001',
          hasPassword: true,
          phoneKnownOnDevice: false,
        );
      await open(tester, gateway: g);
      expect(find.text('Your phone number'), findsOneWidget);
    });
  });

  group('Privacy', () {
    Future<(FakeSettingsGateway, FakeLocalSettings, FakeDeviceAuthenticator)>
    open(WidgetTester tester, {FakeSettingsGateway? gateway}) async {
      useTallWindow(tester);
      final g = gateway ?? FakeSettingsGateway();
      final settings = FakeLocalSettings();
      final auth = FakeDeviceAuthenticator();
      await pumpPage(
        tester,
        const PrivacyPage(),
        overrides: a3bOverrides(
          settingsGateway: g,
          settings: settings,
          auth: auth,
        ),
        stubs: [RoutePaths.blocked],
      );
      await settle(tester);
      return (g, settings, auth);
    }

    testWidgets('loads the server\'s values and saves a change', (
      tester,
    ) async {
      final (g, _, _) = await open(tester);
      expect(find.text('Last seen'), findsOneWidget);
      await tester.tap(find.text('Last seen'));
      await settle(tester);
      await tester.tap(find.text('Nobody'));
      await settle(tester);
      expect(g.savedPrefs?.lastSeen, AudienceChoice.nobody);
      // "My contacts" is not offered: the contact list is not uploaded.
      await tester.tap(find.text('Online status'));
      await settle(tester);
      expect(find.text('My contacts'), findsNothing);
    });

    testWidgets('a change that fails goes back and says why', (tester) async {
      final g = FakeSettingsGateway()
        ..privacySaveFails = const NetworkException();
      await open(tester, gateway: g);
      await tester.tap(find.text('Last seen'));
      await settle(tester);
      await tester.tap(find.text('Nobody'));
      await settle(tester);
      expect(find.textContaining('That was not saved'), findsOneWidget);
      expect(find.text('Everyone'), findsWidgets);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final g = FakeSettingsGateway()
        ..privacyLoadFails = const NetworkException();
      await open(tester, gateway: g);
      expect(find.textContaining('You are offline'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The local settings are still there.
      expect(find.text('Read receipts'), findsOneWidget);
    });

    testWidgets('read receipts and typing are local switches', (tester) async {
      final (_, settings, _) = await open(tester);
      expect(settings.read(EngineSettings.sendReadReceipts), isTrue);
      await tester.tap(find.text('Read receipts'));
      await settle(tester);
      expect(settings.read(EngineSettings.sendReadReceipts), isFalse);
      await tester.tap(find.text('Typing indicators'));
      await settle(tester);
      expect(settings.read(EngineSettings.sendTyping), isFalse);
    });

    testWidgets('the disappearing default can be set and turned off', (
      tester,
    ) async {
      final (_, settings, _) = await open(tester);
      await reveal(tester, find.text('Disappearing messages'));
      await tester.tap(find.text('Disappearing messages'));
      await settle(tester);
      await tester.tap(find.text('7 days'));
      await settle(tester);
      expect(settings.read(EngineSettings.defaultDisappearingSeconds), 604800);

      await tester.tap(find.text('Disappearing messages'));
      await settle(tester);
      await tester.tap(find.text('Off'));
      await settle(tester);
      expect(settings.read(EngineSettings.defaultDisappearingSeconds), isNull);
    });

    testWidgets('app lock needs the phone unlock to turn on', (tester) async {
      final (_, settings, auth) = await open(tester);
      await reveal(tester, find.text('Lock Helix'));
      auth.passes = false;
      await tester.tap(find.text('Lock Helix'));
      await settle(tester);
      expect(settings.read(AppSettings.appLockEnabled), isFalse);
      expect(find.textContaining('unlock was not completed'), findsOneWidget);

      auth.passes = true;
      await tester.tap(find.text('Lock Helix'));
      await settle(tester);
      expect(settings.read(AppSettings.appLockEnabled), isTrue);
    });

    testWidgets('no screen lock: the app lock explains why it cannot start', (
      tester,
    ) async {
      final (_, settings, auth) = await open(tester);
      auth.available = false;
      await reveal(tester, find.text('Lock Helix'));
      await tester.tap(find.text('Lock Helix'));
      await settle(tester);
      expect(settings.read(AppSettings.appLockEnabled), isFalse);
      expect(find.textContaining('no screen lock'), findsOneWidget);
    });

    testWidgets('there is no screenshot or screen-security setting', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('creenshot'), findsNothing);
      expect(find.textContaining('screen security'), findsNothing);
    });

    testWidgets('blocked list unblocks after confirmation', (tester) async {
      useTallWindow(tester);
      final g = FakeSettingsGateway();
      await pumpPage(
        tester,
        const BlockedPage(),
        overrides: a3bOverrides(settingsGateway: g),
      );
      await settle(tester);
      expect(find.text('Rahim'), findsOneWidget);
      await tester.tap(find.text('Unblock'));
      await settle(tester);
      expect(find.text('Unblock Rahim?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await settle(tester);
      expect(g.calls, contains('unblock:b1'));
      expect(find.text('Nobody is blocked'), findsOneWidget);
    });
  });

  group('Notifications', () {
    testWidgets('switches write, a muted chat can be unmuted', (tester) async {
      useTallWindow(tester);
      final settings = FakeLocalSettings();
      final g = FakeSettingsGateway();
      await pumpPage(
        tester,
        const NotificationsPage(),
        overrides: a3bOverrides(settingsGateway: g, settings: settings),
      );
      await settle(tester);

      expect(settings.read(AppSettings.notifyMessages), isTrue);
      await tester.tap(find.text('Messages'));
      await settle(tester);
      expect(settings.read(AppSettings.notifyMessages), isFalse);
      await tester.tap(find.text('Vibrate'));
      await settle(tester);
      expect(settings.read(AppSettings.notifyVibrate), isFalse);
      expect(settings.read(AppSettings.notificationsPreview), isFalse);
      await tester.tap(find.text('Show message previews'));
      await settle(tester);
      expect(settings.read(AppSettings.notificationsPreview), isTrue);

      expect(find.text('Family'), findsOneWidget);
      await tester.tap(find.text('Unmute'));
      await settle(tester);
      expect(g.calls, contains('unmute:c1'));
      expect(find.text('No muted chats'), findsOneWidget);
    });

    testWidgets('a phone with notifications off says so and can ask', (
      tester,
    ) async {
      useTallWindow(tester);
      final permission = FakeNotificationPermission(granted: false);
      await pumpPage(
        tester,
        const NotificationsPage(),
        overrides: a3bOverrides(
          settingsGateway: FakeSettingsGateway(),
          permission: permission,
        ),
      );
      await settle(tester);
      expect(find.textContaining('turned off for Helix'), findsOneWidget);
      await tester.tap(find.text('Allow notifications'));
      await settle(tester);
      expect(permission.requests, 1);
      expect(find.textContaining('turned off for Helix'), findsNothing);
    });
  });

  group('Chats', () {
    testWidgets('text size, Enter key and media policy write', (tester) async {
      useTallWindow(tester);
      final settings = FakeLocalSettings();
      await pumpPage(
        tester,
        const ChatsSettingsPage(),
        overrides: a3bOverrides(settings: settings),
      );
      await settle(tester);

      await tester.tap(find.text('Text size'));
      await settle(tester);
      await tester.tap(find.text('Large'));
      await settle(tester);
      expect(settings.read(AppSettings.fontScalePercent), 115);

      await tester.tap(find.text('Enter key sends'));
      await settle(tester);
      expect(settings.read(AppSettings.enterToSend), isTrue);

      await tester.tap(find.text('Videos'));
      await settle(tester);
      await tester.tap(find.text('On Wi-Fi only').last);
      await settle(tester);
      expect(settings.read(AppSettings.mediaVideo), MediaDownloadPolicy.wifi);
      // There is no theme choice: Helix has one light theme.
      expect(find.textContaining('Dark'), findsNothing);
    });
  });

  group('Media auto-download policy', () {
    test('a policy becomes an engine limit that follows the network', () {
      int limit(MediaDownloadPolicy p, NetworkKind n) =>
          autoDownloadLimit(policy: p, network: n, ceiling: 100);
      expect(limit(MediaDownloadPolicy.never, NetworkKind.unmetered), 0);
      expect(limit(MediaDownloadPolicy.always, NetworkKind.mobile), 100);
      expect(limit(MediaDownloadPolicy.wifi, NetworkKind.unmetered), 100);
      expect(limit(MediaDownloadPolicy.wifi, NetworkKind.mobile), 0);
      expect(limit(MediaDownloadPolicy.wifi, NetworkKind.none), 0);
    });

    test(
      'the sync writes the engine settings and follows the network',
      () async {
        final settings = FakeLocalSettings();
        final network = FakeNetworkProbe(NetworkKind.unmetered);
        final container = newContainer(
          a3bOverrides(settings: settings, network: network),
        );
        addTearDown(container.dispose);
        await settings.set(AppSettings.mediaVideo, MediaDownloadPolicy.wifi);
        container.listen(mediaPolicySyncProvider, (_, _) {});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          settings.read(MediaSettings.autoDownloadVideo),
          MediaDownloadLimits.video,
        );

        network.change(NetworkKind.mobile);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(settings.read(MediaSettings.autoDownloadVideo), 0);
        // "Always" kinds do not move.
        expect(
          settings.read(MediaSettings.autoDownloadImages),
          MediaDownloadLimits.images,
        );
      },
    );
  });

  group('Storage', () {
    testWidgets('shows what Helix keeps and how to free it', (tester) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const StoragePage(),
        overrides: a3bOverrides(
          storage: FakeStorageProbe(
            const StorageUsage(
              databaseBytes: 3 * 1024 * 1024,
              mediaBytes: 20 * 1024 * 1024,
            ),
          ),
        ),
        stubs: [RoutePaths.chats, RoutePaths.backup],
      );
      await settle(tester);
      expect(find.text('23 MB'), findsOneWidget);
      expect(find.text('3.0 MB'), findsOneWidget);
      expect(
        find.textContaining('delete messages or a whole chat'),
        findsOneWidget,
      );
    });
  });

  group('About, legal and advanced', () {
    testWidgets('About shows the version, the server and the crash opt-in', (
      tester,
    ) async {
      useTallWindow(tester);
      final settings = FakeLocalSettings();
      await pumpPage(
        tester,
        const AboutPage(),
        overrides: a3bOverrides(
          settingsGateway: FakeSettingsGateway(),
          settings: settings,
        ),
        stubs: [RoutePaths.legal],
      );
      await settle(tester);
      expect(find.text('2.0.0'), findsOneWidget);
      expect(find.text('Helix Global (helix.example.org)'), findsOneWidget);
      expect(find.text('Terms 2026-09-25, privacy 2026-09-25'), findsOneWidget);
      expect(find.text('Open-source licences'), findsOneWidget);

      expect(settings.read(AppSettings.crashReportsOptIn), isFalse);
      await tester.tap(find.text('Send crash reports'));
      await settle(tester);
      expect(settings.read(AppSettings.crashReportsOptIn), isTrue);
    });

    testWidgets(
      'a server that does not accept crash reports hides the switch',
      (tester) async {
        useTallWindow(tester);
        final g = FakeSettingsGateway();
        g.details = const ServerDetails(
          name: 'Office server',
          host: 'chat.office.example',
          version: '2.0.0',
          openRegistration: false,
          maxAttachmentBytes: 1024,
          termsVersion: '1',
          privacyVersion: '1',
        );
        await pumpPage(
          tester,
          const AboutPage(),
          overrides: a3bOverrides(settingsGateway: g),
          stubs: [RoutePaths.legal],
        );
        await settle(tester);
        expect(
          find.text('Office server (chat.office.example)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('does not accept crash reports'),
          findsOneWidget,
        );
        expect(find.byType(Switch), findsNothing);
      },
    );

    testWidgets('legal documents come from the server with their version', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const LegalPage(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
      );
      await settle(tester);
      expect(find.text('Helix Global Terms of Service'), findsOneWidget);
      expect(find.text('Version 2026-09-25'), findsOneWidget);
      expect(find.text('These are the terms.'), findsOneWidget);
      await tester.tap(find.text('Privacy'));
      await settle(tester);
      expect(find.text('This is the privacy policy.'), findsOneWidget);
    });

    testWidgets('Advanced lists server facts and flags, and can sync', (
      tester,
    ) async {
      useTallWindow(tester);
      final g = FakeSettingsGateway();
      await pumpPage(
        tester,
        const AdvancedPage(),
        overrides: a3bOverrides(settingsGateway: g),
      );
      await settle(tester);
      expect(find.text('Server version'), findsOneWidget);
      expect(find.text('100 MB'), findsOneWidget);
      expect(find.text('Crash reports accepted'), findsOneWidget);
      await tester.tap(find.text('Check for messages now'));
      await settle(tester);
      expect(g.calls, contains('syncNow'));
      expect(find.text('Up to date.'), findsOneWidget);
      expect(find.textContaining('Host your own'), findsNothing);
    });

    testWidgets('Advanced explains an unreachable server', (tester) async {
      final g = FakeSettingsGateway()..serverFails = const NetworkException();
      await pumpPage(
        tester,
        const AdvancedPage(),
        overrides: a3bOverrides(settingsGateway: g),
      );
      await settle(tester);
      expect(find.textContaining('could not be reached'), findsOneWidget);
    });
  });
}
