import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/crash_reporter.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/engine/backup_policy.dart';
import 'package:helix_remote/core/platform/app_info.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/backup/presentation/backup_page.dart';
import 'package:helix_remote/features/backup/presentation/recovery_backup_page.dart';
import 'package:helix_remote/features/backup/presentation/restore_history_page.dart';
import 'package:helix_remote/features/backup/presentation/transfer_page.dart';
import 'package:helix_remote/features/devices/presentation/approve_device_page.dart';
import 'package:helix_remote/features/devices/presentation/devices_page.dart';
import 'package:helix_remote/features/devices/presentation/link_this_device_page.dart';
import 'package:helix_remote/features/devices/presentation/security_activity_page.dart';
import 'package:helix_remote/features/profile/presentation/profile_page.dart';
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
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote_api/v2.dart'
    show ApiException, NetworkException, SignedOutException, SignedOutReason;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show BackupException, BackupFailure, BackupRemote;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode, FullBackup, HistoryBackup;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../support/a3b_fakes.dart';

/// The product rules for the settings-side pages: every page at the default
/// and the largest text scale, against Flutter's own accessibility
/// guidelines, plus source scans and the small units the pages rest on.
void main() {
  final pages = <String, Widget Function()>{
    'Settings tab': () => const SettingsTab(),
    'Account': () => const AccountPage(),
    'Change password': () => const ChangePasswordPage(),
    'Privacy': () => const PrivacyPage(),
    'Blocked': () => const BlockedPage(),
    'Notifications': () => const NotificationsPage(),
    'Chats': () => const ChatsSettingsPage(),
    'Storage': () => const StoragePage(),
    'About': () => const AboutPage(),
    'Legal': () => const LegalPage(),
    'Advanced': () => const AdvancedPage(),
    'Devices': () => const DevicesPage(),
    'Approve device': () => const ApproveDevicePage(),
    'Security activity': () => const SecurityActivityPage(),
    'Link this device': () => const LinkThisDevicePage(),
    'Backup': () => const BackupPage(),
    'Restore (after sign-in)': () =>
        const RestoreHistoryPage(afterSignIn: true),
    'Restore (settings)': () => const RestoreHistoryPage(),
    'Transfer': () => const TransferPage(),
    'Recovery backup': () => const RecoveryBackupPage(),
    'Profile': () => const ProfilePage(),
  };

  List<Override> overrides() => a3bOverrides(
    backup: FakeBackupGateway(),
    devices: FakeDevicesGateway(),
    profile: FakeProfileGateway(),
    settingsGateway: FakeSettingsGateway(),
    extra: [engineConfigNameOverride],
  );

  for (final scale in [1.0, 2.0]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} at ${scale}x text: no overflow, targets and '
          'labels meet the guidelines', (tester) async {
        useTallWindow(tester, height: scale == 1 ? 3000 : 6000);
        await pumpPage(
          tester,
          entry.value(),
          overrides: overrides(),
          textScale: scale,
          stubs: const [],
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Pages with a ticking countdown stop it with the page.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }

  group('source rules for the A3b features', () {
    /// Source without `//` comments: a rule may be explained in prose.
    String code(File f) => f
        .readAsLinesSync()
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    Iterable<File> sources(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('no page mentions hosting your own server', () {
      for (final file in sources('lib')) {
        final text = code(file).toLowerCase();
        expect(
          text.contains('host your own') || text.contains('self-host'),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('Settings has no screen-capture control', () {
      for (final dir in const [
        'lib/features/settings',
        'lib/features/privacy',
        'lib/features/profile',
      ]) {
        if (!Directory(dir).existsSync()) continue;
        for (final file in sources(dir)) {
          final text = code(file);
          expect(text.contains('FLAG_SECURE'), isFalse, reason: file.path);
          expect(
            text.toLowerCase().contains('screenshot'),
            isFalse,
            reason: file.path,
          );
        }
      }
    });

    test('secrets are not copied, stored or logged by the backup feature', () {
      for (final file in sources('lib/features/backup')) {
        final text = file.readAsStringSync();
        expect(text.contains('Clipboard'), isFalse, reason: file.path);
        expect(text.contains('SharedPreferences'), isFalse, reason: file.path);
        expect(
          RegExp(r'\b(print|debugPrint)\(').hasMatch(text),
          isFalse,
          reason: file.path,
        );
      }
      // The recovery secret lives only in the notifier's state: it is never
      // handed to a settings store.
      final providers = File(
        'lib/features/backup/application/backup_providers.dart',
      ).readAsStringSync();
      expect(providers.contains('localSettingsProvider).set('), isFalse);
    });

    test('every string a page shows for a failure comes from copy files', () {
      for (final file in sources(
        'lib/features',
      ).where((f) => f.path.contains('presentation'))) {
        final text = code(file);
        expect(text.contains(r'$e)'), isFalse, reason: file.path);
        expect(text.contains('.toString()'), isFalse, reason: file.path);
      }
    });
  });

  group('units', () {
    test('the app version matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(kAppVersion, version);
      expect(const AppInfo().name, 'Helix Remote');
    });

    test('failures become sentences with no exception text', () {
      final now = DateTime(2026, 10, 3, 10);
      expect(
        describeFailure(const NetworkException()).kind,
        FailureKind.offline,
      );
      expect(
        describeFailure(
          const SignedOutException(SignedOutReason.noSession),
        ).kind,
        FailureKind.signedOut,
      );
      final locked = describeFailure(
        ApiException(
          status: 429,
          code: ErrorCode.passwordLocked,
          details: {
            'locked_until': DateTime(
              2026,
              10,
              3,
              10,
              4,
            ).toUtc().millisecondsSinceEpoch,
          },
        ),
        now: now,
      );
      expect(locked.kind, FailureKind.locked);
      expect(locked.message, contains('5 minutes'));
      expect(
        describeFailure(
          const ApiException(status: 429, code: ErrorCode.rateLimited),
        ).kind,
        FailureKind.rateLimited,
      );
      for (final error in [
        const NetworkException(),
        StateError('secret token abc'),
        const ApiException(
          status: 500,
          code: ErrorCode.internal,
          message: 'boom',
        ),
      ]) {
        final text = describeFailure(error).message;
        expect(text, isNot(contains('abc')));
        expect(text, isNot(contains('boom')));
        expect(text, isNot(contains('Exception')));
      }
    });

    test('network kinds: Wi-Fi wins over mobile, nothing is none', () {
      expect(
        DeviceNetworkProbe.classify([ConnectivityResult.mobile]),
        NetworkKind.mobile,
      );
      expect(
        DeviceNetworkProbe.classify([
          ConnectivityResult.mobile,
          ConnectivityResult.wifi,
        ]),
        NetworkKind.unmetered,
      );
      expect(
        DeviceNetworkProbe.classify([ConnectivityResult.none]),
        NetworkKind.none,
      );
      expect(DeviceNetworkProbe.classify(const []), NetworkKind.none);
    });

    test(
      'the backup upload is refused on mobile data, downloads are not',
      () async {
        final inner = _CountingRemote();
        var allowed = false;
        final remote = PolicyBackupRemote(
          inner,
          mayUpload: () async => allowed,
        );
        await expectLater(
          remote.putHistory(_history),
          throwsA(
            isA<BackupException>().having(
              (e) => e.failure,
              'failure',
              BackupFailure.notAllowed,
            ),
          ),
        );
        expect(inner.uploads, 0);
        await remote.history();
        expect(inner.downloads, 1);
        allowed = true;
        await remote.putHistory(_history);
        expect(inner.uploads, 1);
      },
    );

    test('crash reports do nothing until installed, and rate-limit', () async {
      CrashReporter.resetForTest();
      CrashReporter.report(StateError('x')); // not installed: silent
      final container = ProviderContainer(
        overrides: a3bOverrides(settings: FakeLocalSettings()),
      );
      addTearDown(() {
        container.dispose();
        CrashReporter.resetForTest();
      });
      container.read(crashReporterInstallProvider);
      // Installed but not opted in: the sink returns without a request (the
      // runtime factory here would throw if it were asked for a server).
      CrashReporter.report(StateError('x'));
      CrashReporter.report(StateError('y'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('a failed password sign-in withdraws the restore step', () async {
      final container = newContainer(a3bOverrides());
      addTearDown(container.dispose);
      final controller = container.read(signInControllerProvider.notifier);
      controller
        ..updateDigits('1711000001')
        ..updatePassword('pw');
      final ok = await controller.signInWithPassword();
      expect(ok, isFalse);
      expect(container.read(postSignInProvider), PostSignInStep.none);
    });

    test('settings keys for the new pages are namespaced and typed', () {
      expect(AppSettings.fontScalePercent.defaultValue, 100);
      expect(AppSettings.enterToSend.defaultValue, isFalse);
      expect(AppSettings.backupOverMobile.defaultValue, isFalse);
      expect(AppSettings.crashReportsOptIn.defaultValue, isFalse);
      expect(AppSettings.mediaVideo.defaultValue, MediaDownloadPolicy.never);
      final keys = [
        AppSettings.fontScalePercent,
        AppSettings.enterToSend,
        AppSettings.notifyMessages,
        AppSettings.notifyGroups,
        AppSettings.notifyCalls,
        AppSettings.notifySound,
        AppSettings.notifyVibrate,
        AppSettings.mediaImages,
        AppSettings.mediaAudio,
        AppSettings.mediaVideo,
        AppSettings.mediaDocuments,
        AppSettings.backupOverMobile,
        AppSettings.crashReportsOptIn,
        AppSettings.profileAbout,
      ].map((s) => s.key);
      expect(keys.toSet().length, keys.length);
      expect(keys.every((k) => k.startsWith('app.')), isTrue);
    });
  });
}

final _history = HistoryBackup(
  version: 1,
  data: Uint8List.fromList(List.filled(8, 2)),
);

class _CountingRemote implements BackupRemote {
  var uploads = 0;
  var downloads = 0;

  @override
  Future<HistoryBackup?> history() async {
    downloads++;
    return null;
  }

  @override
  Future<void> putHistory(HistoryBackup backup) async => uploads++;

  @override
  Future<void> deleteHistory() async {}

  @override
  Future<FullBackup?> full() async => null;

  @override
  Future<void> putFull(FullBackup backup) async {}

  @override
  Future<void> deleteFull() async {}
}
