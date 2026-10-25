import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/profile/application/profile_gateway.dart';
import 'package:helix_remote/features/settings/application/media_policy_sync.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/application/sound_packs.dart'
    show canChooseRingtoneProvider;
import 'package:helix_remote/features/settings/presentation/about_page.dart';
import 'package:helix_remote/features/settings/presentation/appearance_page.dart';
import 'package:helix_remote/features/settings/presentation/account_page.dart';
import 'package:helix_remote/features/settings/presentation/advanced_page.dart';
import 'package:helix_remote/features/settings/presentation/blocked_page.dart';
import 'package:helix_remote/features/settings/presentation/change_password_page.dart';
import 'package:helix_remote/features/settings/presentation/chats_page.dart';
import 'package:helix_remote/features/settings/presentation/legal_page.dart';
import 'package:helix_remote/features/settings/presentation/notifications_page.dart';
import 'package:helix_remote/features/settings/presentation/privacy_page.dart';
import 'package:helix_remote/features/settings/presentation/storage_page.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart'
    show downloadSummary;
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/orbit_you_connector.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EngineSettings, MediaSettings;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

import '../support/a3b_fakes.dart';

/// A widget test that ends by taking the page down and letting the last Orbit
/// toast (4 s at most) go, so no timer is left pending.
void youTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

/// The text in the Orbit field labelled [label].
Finder orbitField(String label) => find.descendant(
  of: find.widgetWithText(orbit.OrbitTextField, label),
  matching: find.byType(EditableText),
);

void main() {
  group('You', () {
    youTest('shows who you are and opens every page', (tester) async {
      useTallWindow(tester);
      final paths = [
        RoutePaths.appearance,
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
        const OrbitYouConnector(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: paths,
      );
      await settle(tester);

      expect(find.text('Anna Khan'), findsWidgets);
      expect(find.textContaining('helix.example.org'), findsWidgets);
      for (final (label, path) in [
        ('Appearance', RoutePaths.appearance),
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
        await reveal(tester, find.text(label).last);
        await tester.tap(find.text(label).last);
        await settle(tester);
        expect(find.text('stub:$path'), findsOneWidget, reason: label);
        router.pop();
        await settle(tester);
      }
      // There is no host-your-own-server guide anywhere in Settings.
      expect(find.textContaining('Host your own'), findsNothing);
      expect(find.textContaining('host your own'), findsNothing);
    });

    youTest('Appearance opens the page of themes to get', (tester) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const AppearancePage(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: [RoutePaths.themePacks],
      );
      await settle(tester);
      // The one row under the two cards, and no "on the way" caption: the
      // themes a server publishes are reachable.
      expect(find.textContaining('More themes are on the way'), findsNothing);
      await tester.tap(find.text('More themes'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.themePacks}'), findsOneWidget);
    });

    youTest('Notifications opens the page of ringtones to get', (tester) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const NotificationsPage(),
        overrides: [
          ...a3bOverrides(settingsGateway: FakeSettingsGateway()),
          // A phone that rings through its notification channels: the row
          // only exists where a chosen sound can ring.
          canChooseRingtoneProvider.overrideWithValue(true),
        ],
        stubs: [RoutePaths.ringtones],
      );
      await settle(tester);
      await tester.tap(find.text('Ringtone'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.ringtones}'), findsOneWidget);
    });

    youTest('Edit profile opens the profile', (tester) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: [RoutePaths.profile],
      );
      await settle(tester);
      await tester.tap(find.text('Edit profile').first);
      await settle(tester);
      expect(find.text('stub:${RoutePaths.profile}'), findsOneWidget);
    });

    youTest('the share sheet carries the ~name link, QR and buttons', (
      tester,
    ) async {
      useTallWindow(tester);
      const link = 'https://helix.agiletechbd.com/u/anna.k';
      final share = FakeShareAdapter();
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: a3bOverrides(
          settingsGateway: FakeSettingsGateway(),
          profile: FakeProfileGateway(),
          share: share,
        ),
        stubs: [RoutePaths.scanChat],
      );
      await settle(tester);
      Future<void> openSheet() async {
        await tester.tap(find.byTooltip('Share your Orbit code'));
        await settle(tester);
      }

      await openSheet();
      expect(find.text(link), findsOneWidget);
      expect(
        tester.widget<orbit.OrbitQr>(find.byType(orbit.OrbitQr)).matrix,
        isNotNull,
        reason: 'the sheet draws the link as a real code, not a pattern',
      );

      await tester.tap(find.text('Copy link'));
      await settle(tester);
      expect(find.text('Link copied'), findsOneWidget);
      // Let the toast go away: it sits over the sheet and eats the next tap.
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      await openSheet();
      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(share.links, [link]);

      await openSheet();
      await tester.tap(find.text('Scan someone’s code'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.scanChat}'), findsOneWidget);
    });

    youTest('an account with no ~name has no link to share', (tester) async {
      useTallWindow(tester);
      final profile = FakeProfileGateway()
        ..profile.set(
          const ProfileData(
            accountId: 'acct-1',
            name: 'Anna Khan',
            about: 'Busy',
            phoneMasked: '+88017*****01',
          ),
        );
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: a3bOverrides(
          settingsGateway: FakeSettingsGateway(),
          profile: profile,
        ),
      );
      await settle(tester);
      expect(find.byTooltip('Share your Orbit code'), findsNothing);
      expect(find.textContaining('/u/'), findsNothing);
    });
  });

  group('Settings search', () {
    youTest('narrows the rows and says when nothing matches', (tester) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
      );
      await settle(tester);

      await tester.tap(find.byTooltip('Search settings'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'receipts');
      await settle(tester);
      expect(find.text('Privacy'), findsWidgets);
      expect(find.text('Backup'), findsNothing);

      await tester.enterText(find.byType(EditableText), 'zzzz');
      await settle(tester);
      expect(find.textContaining('No settings match'), findsOneWidget);

      await tester.tap(find.byTooltip('Close search'));
      await settle(tester);
      expect(find.text('Backup'), findsWidgets);
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
          RoutePaths.deleteAccount,
          RoutePaths.accounts,
        ],
      );
      await settle(tester);
      return g;
    }

    youTest('switching instead of signing out opens Accounts', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.text('Switch account'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.accounts}'), findsOneWidget);
    });

    youTest('shows the phone number masked and the ~name', (tester) async {
      await open(tester);
      expect(find.textContaining('+88017*****01'), findsOneWidget);
      expect(find.textContaining('~anna.k'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Password set'), findsOneWidget);
    });

    youTest('without a password it offers to set one', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01');
      await open(tester, gateway: g);
      expect(find.text('Set a password'), findsOneWidget);
      expect(find.text('No password'), findsOneWidget);
    });

    youTest('says since when the account exists', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = AccountOverview(
          phoneMasked: '+88017*****01',
          hasPassword: true,
          createdAt: DateTime(2026, 9, 12),
        );
      await open(tester, gateway: g);
      expect(find.text('Since Sep 2026'), findsOneWidget);
    });

    youTest('offline: the page says so and can retry', (tester) async {
      final g = FakeSettingsGateway()..accountFails = const NetworkException();
      await open(tester, gateway: g);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    youTest('sign out is confirmed and warns about the wipe', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.textContaining('deletes its messages'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Sign out?'), findsNothing);
    });

    youTest('export shares a file named for the day', (tester) async {
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

    youTest('an export that cannot be shared says so', (tester) async {
      final share = FakeShareAdapter()..result = false;
      await open(tester, share: share);
      await tester.tap(find.text('Export my data'));
      await settle(tester);
      expect(find.textContaining('could not be shared'), findsOneWidget);
    });

    youTest('an export that fails offline says so', (tester) async {
      final g = FakeSettingsGateway()..exportFails = const NetworkException();
      await open(tester, gateway: g);
      await tester.tap(find.text('Export my data'));
      await settle(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    youTest('delete offers the export first, then goes to its own page', (
      tester,
    ) async {
      final share = FakeShareAdapter();
      final g = await open(tester, share: share);
      await reveal(tester, find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      expect(find.text('Delete your account?'), findsOneWidget);
      await tester.tap(find.text('Export first'));
      await settle(tester);
      expect(g.calls, contains('export'));
      // "Export first" only exports: the page has not moved on.
      expect(find.text('stub:${RoutePaths.deleteAccount}'), findsNothing);

      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.deleteAccount}'), findsOneWidget);
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
      await tester.enterText(orbitField('Current password'), current);
      await tester.enterText(orbitField('New password'), next);
      await tester.enterText(
        orbitField('Confirm new password'),
        confirm ?? next,
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(orbit.OrbitButton, 'Change password'),
      );
      await settle(tester);
    }

    youTest('changes the password with the current one', (tester) async {
      final g = await open(tester);
      await fill(tester);
      expect(g.changedTo, 'new password 1');
      expect(g.changedCurrent, 'old password');
      expect(find.text('Password saved'), findsOneWidget);
    });

    youTest('the passwords are hidden until asked', (tester) async {
      await open(tester);
      bool hidden() =>
          tester.widget<EditableText>(orbitField('New password')).obscureText;
      expect(hidden(), isTrue);
      await tester.tap(find.text('Show passwords'));
      await settle(tester);
      expect(hidden(), isFalse);
    });

    youTest('a wrong current password is said plainly', (tester) async {
      final g = FakeSettingsGateway()
        ..changePasswordFails = const ApiException(
          status: 401,
          code: ErrorCode.invalidCredentials,
        );
      await open(tester, gateway: g);
      await fill(tester);
      expect(find.text('That is not your current password.'), findsOneWidget);
      expect(find.text('Password saved'), findsNothing);
    });

    youTest('a lockout says how long to wait', (tester) async {
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

    youTest('offline says so', (tester) async {
      final g = FakeSettingsGateway()
        ..changePasswordFails = const NetworkException();
      await open(tester, gateway: g);
      await fill(tester);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    youTest('a mismatch and a short password never reach the engine', (
      tester,
    ) async {
      final g = await open(tester);
      await fill(tester, next: 'short', confirm: 'different');
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(g.calls, isNot(contains('changePassword')));
    });

    youTest('a first password needs no current one', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01');
      await open(tester, gateway: g);
      expect(find.text('Current password'), findsNothing);
      await tester.enterText(orbitField('New password'), 'first password');
      await tester.enterText(
        orbitField('Confirm new password'),
        'first password',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(orbit.OrbitButton, 'Set a password'),
      );
      await settle(tester);
      expect(g.changedTo, 'first password');
      expect(g.changedCurrent, isNull);
    });

    youTest('a linked device is asked for the number once', (tester) async {
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

    /// The segment [option] in the segmented row titled [row].
    Finder segment(String row, String option) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is orbit.OrbitSegRow && w.title == row,
      ),
      matching: find.text(option),
    );

    youTest('loads the server\'s values and saves a change', (tester) async {
      final (g, _, _) = await open(tester);
      expect(find.text('Last seen'), findsOneWidget);
      await tester.tap(segment('Last seen', 'Nobody'));
      await settle(tester);
      expect(g.savedPrefs?.lastSeen, AudienceChoice.nobody);
      // "My contacts" is not offered: the contact list is not uploaded.
      expect(find.text('My contacts'), findsNothing);
    });

    youTest('a change that fails goes back and says why', (tester) async {
      final g = FakeSettingsGateway()
        ..privacySaveFails = const NetworkException();
      await open(tester, gateway: g);
      await tester.tap(segment('Last seen', 'Nobody'));
      await settle(tester);
      expect(find.textContaining('That was not saved'), findsOneWidget);
      expect(g.savedPrefs, isNull);
    });

    youTest('a load failure offers a retry', (tester) async {
      final g = FakeSettingsGateway()
        ..privacyLoadFails = const NetworkException();
      await open(tester, gateway: g);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The local settings are still there.
      expect(find.text('Read receipts'), findsOneWidget);
    });

    youTest('read receipts and typing are local switches', (tester) async {
      final (_, settings, _) = await open(tester);
      expect(settings.read(EngineSettings.sendReadReceipts), isTrue);
      await tester.tap(find.text('Read receipts'));
      await settle(tester);
      expect(settings.read(EngineSettings.sendReadReceipts), isFalse);
      await tester.tap(find.text('Typing indicator'));
      await settle(tester);
      expect(settings.read(EngineSettings.sendTyping), isFalse);
    });

    youTest('the disappearing default can be set and turned off', (
      tester,
    ) async {
      const row = 'Disappearing messages for new chats';
      final (_, settings, _) = await open(tester);
      await reveal(tester, find.text(row));
      await tester.tap(segment(row, '7 d'));
      await settle(tester);
      expect(settings.read(EngineSettings.defaultDisappearingSeconds), 604800);

      await tester.tap(segment(row, 'Off'));
      await settle(tester);
      expect(settings.read(EngineSettings.defaultDisappearingSeconds), isNull);
    });

    youTest('app lock needs the phone unlock to turn on', (tester) async {
      final (_, _, auth) = await open(tester);
      DeviceLock? lock() => ProviderScope.containerOf(
        tester.element(find.byType(PrivacyPage)),
      ).read(accountsProvider).lock;
      await reveal(tester, find.text('Lock Orbit'));
      auth.passes = false;
      await tester.tap(find.text('Lock Orbit'));
      await settle(tester);
      expect(lock(), isNull);
      expect(find.textContaining('unlock was not completed'), findsOneWidget);

      auth.passes = true;
      await tester.tap(find.text('Lock Orbit'));
      await settle(tester);
      // The device's lock, for every account on it.
      expect(lock(), const DeviceLock(enabled: true, relockAfterSeconds: 60));

      await reveal(tester, find.text('Lock again'));
      await tester.tap(segment('Lock again', '5 min'));
      await settle(tester);
      expect(lock(), const DeviceLock(enabled: true, relockAfterSeconds: 300));
    });

    youTest('no screen lock: the app lock explains why it cannot start', (
      tester,
    ) async {
      final (_, _, auth) = await open(tester);
      auth.available = false;
      await reveal(tester, find.text('Lock Orbit'));
      await tester.tap(find.text('Lock Orbit'));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PrivacyPage)),
      );
      expect(container.read(accountsProvider).lock, isNull);
      expect(find.textContaining('no screen lock'), findsOneWidget);
    });

    youTest('there is no screenshot or screen-security setting', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('creenshot'), findsNothing);
      expect(find.textContaining('screen security'), findsNothing);
    });

    youTest('the blocked row counts and opens the list', (tester) async {
      await open(tester);
      await reveal(tester, find.text('1 blocked person'));
      await tester.tap(find.text('1 blocked person'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.blocked}'), findsOneWidget);
    });

    youTest('blocked list unblocks after confirmation', (tester) async {
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
      await tester.tap(find.text('Unblock').last);
      await settle(tester);
      expect(g.calls, contains('unblock:b1'));
      expect(find.textContaining('Nobody is blocked'), findsWidgets);
    });
  });

  group('Notifications', () {
    youTest('switches write, a muted chat can be unmuted', (tester) async {
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
      await tester.tap(find.text('Vibrate').last);
      await settle(tester);
      expect(settings.read(AppSettings.notifyVibrate), isFalse);
      expect(settings.read(AppSettings.notificationsPreview), isTrue);
      await tester.tap(find.text('Show message previews'));
      await settle(tester);
      expect(settings.read(AppSettings.notificationsPreview), isFalse);
      // A test device is an Android one, and a call there rings with a chosen
      // sound through its notification channels: the row is here, and says what
      // the next call rings with.
      expect(find.text('Ringtone'), findsOneWidget);
      expect(find.text('Phone’s ringtone'), findsOneWidget);

      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
      await reveal(tester, find.text('Unmute'));
      await tester.tap(find.text('Unmute'));
      await settle(tester);
      expect(g.calls, contains('unmute:c1'));
      expect(find.textContaining('No muted chats'), findsOneWidget);
    });

    youTest('a phone with notifications off says so and can ask', (
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
      expect(find.textContaining('turned off for Orbit'), findsOneWidget);
      await tester.tap(find.text('Allow notifications'));
      await settle(tester);
      expect(permission.requests, 1);
      expect(find.textContaining('turned off for Orbit'), findsNothing);
    });
  });

  group('Chats', () {
    youTest('text size, Enter key and media policy write', (tester) async {
      useTallWindow(tester);
      final settings = FakeLocalSettings();
      await pumpPage(
        tester,
        const ChatsSettingsPage(),
        overrides: a3bOverrides(settings: settings),
      );
      await settle(tester);

      await tester.tap(find.text('Large'));
      await settle(tester);
      expect(settings.read(AppSettings.fontScalePercent), 115);

      await tester.tap(find.text('Enter key sends'));
      await settle(tester);
      expect(settings.read(AppSettings.enterToSend), isTrue);

      await reveal(tester, find.text('Videos'));
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is orbit.OrbitSegRow && w.title == 'Videos',
          ),
          matching: find.text('Wi-Fi'),
        ),
      );
      await settle(tester);
      expect(settings.read(AppSettings.mediaVideo), MediaDownloadPolicy.wifi);
      // The theme is on its own page, Appearance.
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
        // Images default to Wi-Fi only now, so they follow the network too;
        // an "always" kind does not move.
        expect(settings.read(MediaSettings.autoDownloadImages), 0);
        expect(
          settings.read(MediaSettings.autoDownloadAudio),
          MediaDownloadLimits.audio,
        );
      },
    );
  });

  group('Storage', () {
    youTest('shows what Orbit keeps and frees a chat without its messages', (
      tester,
    ) async {
      useTallWindow(tester);
      final settings = FakeLocalSettings();
      await settings.set(AppSettings.backupOverMobile, true);
      final gateway = FakeSettingsGateway()
        ..storedMedia = const MediaStorageSummary(
          photosVideosBytes: 12 * 1024 * 1024,
          filesBytes: 2 * 1024 * 1024,
          voiceNoteBytes: 1024 * 1024,
        )
        ..chatSizes = const [
          ChatStorageSizes(
            chatId: 'c1',
            photosVideosBytes: 8 * 1024 * 1024,
            filesBytes: 1024 * 1024,
          ),
        ]
        ..freeBytes = 8 * 1024 * 1024;
      await pumpPage(
        tester,
        const StoragePage(),
        overrides: a3bOverrides(
          settings: settings,
          settingsGateway: gateway,
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
      expect(find.text('23 MB on this phone'), findsOneWidget);
      expect(find.textContaining('3.0 MB messages and keys'), findsOneWidget);
      expect(
        find.text('Photos on Wi-Fi, voice always, videos and documents never'),
        findsOneWidget,
      );
      expect(find.text('Allowed'), findsOneWidget);

      // The biggest chats come from the engine, named by the chat list; with
      // no runtime in this test the fallback name is used.
      expect(
        find.textContaining('BIGGEST CHATS', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('9.0 MB'), findsOneWidget);
      await tester.tap(find.text('Chat'));
      await settle(tester);
      expect(find.text('Remove photos and videos · 8.0 MB'), findsOneWidget);
      expect(find.text('Remove documents · 1.0 MB'), findsOneWidget);
      await tester.tap(find.text('Remove photos and videos · 8.0 MB'));
      await settle(tester);
      expect(find.text('8.0 MB freed'), findsOneWidget);
      expect(gateway.freedChats, ['c1:photosVideos']);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.text('Download automatically'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.chats}'), findsOneWidget);
    });

    youTest('names the themes a person downloaded, beside the rest', (
      tester,
    ) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const StoragePage(),
        overrides: a3bOverrides(
          settingsGateway: FakeSettingsGateway(),
          storage: FakeStorageProbe(
            const StorageUsage(
              databaseBytes: 3 * 1024 * 1024,
              mediaBytes: 20 * 1024 * 1024,
              packBytes: 2 * 1024 * 1024,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('25 MB on this phone'), findsOneWidget);
      expect(
        find.text('3.0 MB messages and keys · 20 MB media · 2.0 MB themes'),
        findsOneWidget,
      );
    });

    youTest('says when the figures cannot be read', (tester) async {
      useTallWindow(tester);
      final gateway = FakeSettingsGateway()
        ..storageFails = StateError('the database is closed');
      await pumpPage(
        tester,
        const StoragePage(),
        overrides: a3bOverrides(settingsGateway: gateway),
      );
      await settle(tester);
      expect(
        find.text('The storage figures could not be read.'),
        findsOneWidget,
      );
    });

    test('the download line names kinds with the same policy together', () {
      expect(
        downloadSummary(
          photos: MediaDownloadPolicy.always,
          voice: MediaDownloadPolicy.always,
          videos: MediaDownloadPolicy.always,
          documents: MediaDownloadPolicy.always,
        ),
        'Photos, voice, videos and documents always',
      );
      expect(
        downloadSummary(
          photos: MediaDownloadPolicy.never,
          voice: MediaDownloadPolicy.wifi,
          videos: MediaDownloadPolicy.never,
          documents: MediaDownloadPolicy.always,
        ),
        'Photos and videos never, voice on Wi-Fi, documents always',
      );
    });
  });

  group('About, legal and advanced', () {
    youTest('About shows the version, the server and problem reports', (
      tester,
    ) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const AboutPage(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
        stubs: [RoutePaths.legal, RoutePaths.advanced],
      );
      await settle(tester);
      expect(find.text('Version 2.0.0'), findsOneWidget);
      expect(find.text('Helix Global (helix.example.org)'), findsOneWidget);
      expect(find.text('Open-source licences'), findsOneWidget);
      // Problem reports are always sent, so there is no switch to offer.
      expect(find.text('Problem reports'), findsOneWidget);
      expect(find.text('Send crash reports'), findsNothing);

      await tester.tap(find.text('Terms of Service'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.legal}'), findsOneWidget);
    });

    youTest('legal documents come from the server with their version', (
      tester,
    ) async {
      useTallWindow(tester);
      await pumpPage(
        tester,
        const LegalPage(),
        overrides: a3bOverrides(settingsGateway: FakeSettingsGateway()),
      );
      await settle(tester);
      expect(find.text('Helix Global Terms of Service'), findsOneWidget);
      expect(
        find.textContaining(RegExp('version 2026-09-25', caseSensitive: false)),
        findsOneWidget,
      );
      expect(find.textContaining('These are the terms.'), findsOneWidget);
      await tester.tap(find.text('Privacy'));
      await settle(tester);
      expect(
        find.textContaining('This is the privacy policy.'),
        findsOneWidget,
      );
    });

    youTest('Advanced lists server facts and flags, and can sync', (
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
      expect(find.text('Largest attachment'), findsOneWidget);
      expect(find.text('100 MB'), findsOneWidget);
      expect(find.text('Crash reports accepted'), findsOneWidget);
      await tester.tap(find.text('Check for messages now'));
      await settle(tester);
      expect(g.calls, contains('syncNow'));
      expect(
        find.textContaining(RegExp('up to date', caseSensitive: false)),
        findsOneWidget,
      );
      expect(find.textContaining('Host your own'), findsNothing);
    });

    youTest('Advanced explains an unreachable server', (tester) async {
      useTallWindow(tester);
      final g = FakeSettingsGateway()..serverFails = const NetworkException();
      await pumpPage(
        tester,
        const AdvancedPage(),
        overrides: a3bOverrides(settingsGateway: g),
      );
      await settle(tester);
      expect(find.textContaining('could not be reached'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
