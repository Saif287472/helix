import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/notifications/notification_permission.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:helix_remote/core/platform/share_adapter.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/features/backup/application/backup_gateway.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/devices/application/devices_gateway.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/features/profile/application/profile_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show EngineConfig;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Fakes for the settings-side features (Phase A3b).
///
/// Every page in `features/settings`, `devices`, `backup` and `profile` talks
/// to a gateway interface, so a widget test replaces the gateway and runs the
/// real notifiers and the real page with no engine, no database and no
/// network. The same fakes drive the rule tests (tap targets, text scale).

/// A value that can be read, watched and changed.
class Live<T> {
  Live(this.value);

  T value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  Stream<T> get stream async* {
    yield value;
    yield* _changes.stream;
  }

  void set(T next) {
    value = next;
    _changes.add(next);
  }
}

/// An in-memory [LocalSettings].
class FakeLocalSettings implements LocalSettings {
  final Map<String, Object?> _values = {};
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  T read<T>(Setting<T> s) =>
      _values.containsKey(s.key) ? _values[s.key] as T : s.defaultValue;

  @override
  Future<T> get<T>(Setting<T> setting) async => read(setting);

  @override
  Stream<T> watch<T>(Setting<T> setting) async* {
    yield read(setting);
    await for (final key in _changes.stream) {
      if (key == setting.key) yield read(setting);
    }
  }

  @override
  Future<void> set<T>(Setting<T> setting, T value) async {
    _values[setting.key] = value;
    _changes.add(setting.key);
  }
}

class FakeDeviceAuthenticator implements DeviceAuthenticator {
  bool available = true;
  bool passes = true;
  final List<String> asked = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> confirm(String reason) async {
    asked.add(reason);
    return passes;
  }
}

class FakeShareAdapter implements ShareAdapter {
  bool result = true;
  final List<({String filename, Uint8List bytes, String mimeType})> shared = [];

  @override
  Future<bool> shareFile({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    shared.add((filename: filename, bytes: bytes, mimeType: mimeType));
    return result;
  }
}

class FakeNetworkProbe implements NetworkProbe {
  FakeNetworkProbe([this.kind = NetworkKind.unmetered]);

  NetworkKind kind;
  final StreamController<NetworkKind> _c = StreamController.broadcast();

  void change(NetworkKind next) {
    kind = next;
    _c.add(next);
  }

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _c.stream;
}

class FakeStorageProbe implements StorageUsageProbe {
  FakeStorageProbe([this.usage = const StorageUsage()]);

  StorageUsage usage;

  @override
  Future<StorageUsage> measure() async => usage;
}

class FakeNotificationPermission implements NotificationPermissionSource {
  FakeNotificationPermission({this.granted = true});

  bool granted;
  var requests = 0;

  @override
  Future<bool> allowed() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    granted = true;
    return granted;
  }
}

class FakeProfileImageSource implements ProfileImageSource {
  FakeProfileImageSource({this.picked, this.fails = false});

  Uint8List? picked;
  bool fails;

  @override
  bool get canPick => true;

  @override
  Future<Uint8List?> pickSquare({int size = 256}) async {
    if (fails) throw const ProfileImageException();
    return picked;
  }
}

class FakeAvatarStore implements ProfileAvatarStore {
  Uint8List? saved;

  @override
  Future<Uint8List?> load() async => saved;

  @override
  Future<void> save(Uint8List png) async => saved = png;

  @override
  Future<void> clear() async => saved = null;
}

// ---------------------------------------------------------------- backup

class FakeBackupGateway implements BackupGateway {
  final summary = Live(
    BackupSummary(
      lastBackupAt: DateTime(2026, 10, 3, 9),
      messages: 1204,
      bytes: 2400000,
    ),
  );
  final offers = Live<List<TransferView>>(const []);
  final backupEvents = StreamController<BackupRunProgress>.broadcast();
  final restoreEvents = StreamController<RestoreRunProgress>.broadcast();
  final transferEvents = StreamController<TransferView>.broadcast();

  /// What each call does. Set one to make the next call fail or wait.
  BackupProblem? backUpFails;
  BackupProblem? restoreFails;
  BackupProblem? recoveryCreateFails;
  BackupProblem? recoveryRestoreFails;
  BackupProblem? sendFails;
  BackupProblem? acceptFails;
  Completer<void>? holdBackUp;
  Completer<void>? holdRestore;
  var restoreOutcome = const RestoreOutcome(added: 120, existing: 4);
  var backupOutcome = const BackupOutcome(messages: 1300, truncated: false);

  final List<String> calls = [];
  String? lastSecret;

  @override
  Stream<BackupSummary> watchSummary() => summary.stream;

  @override
  Stream<BackupRunProgress> get backupProgress => backupEvents.stream;

  @override
  Stream<RestoreRunProgress> get restoreProgress => restoreEvents.stream;

  @override
  Stream<TransferView> get transferProgress => transferEvents.stream;

  @override
  Stream<List<TransferView>> watchOffers() => offers.stream;

  @override
  Future<BackupOutcome> backUpNow() async {
    calls.add('backUpNow');
    await holdBackUp?.future;
    if (backUpFails != null) throw BackupProblemException(backUpFails!);
    return backupOutcome;
  }

  @override
  Future<void> setAutoBackup(bool enabled) async {
    calls.add('setAutoBackup:$enabled');
    final s = summary.value;
    summary.set(
      BackupSummary(
        autoBackup: enabled,
        lastBackupAt: s.lastBackupAt,
        messages: s.messages,
        bytes: s.bytes,
      ),
    );
  }

  @override
  Future<void> deleteServerBackup() async => calls.add('deleteServerBackup');

  @override
  Future<RestoreOutcome> restoreHistory() async {
    calls.add('restoreHistory');
    await holdRestore?.future;
    if (restoreFails != null) throw BackupProblemException(restoreFails!);
    return restoreOutcome;
  }

  @override
  Future<BackupOutcome> createRecoveryBackup(String recoverySecret) async {
    calls.add('createRecoveryBackup');
    lastSecret = recoverySecret;
    if (recoveryCreateFails != null) {
      throw BackupProblemException(recoveryCreateFails!);
    }
    return backupOutcome;
  }

  @override
  Future<RestoreOutcome> restoreRecoveryBackup(String recoverySecret) async {
    calls.add('restoreRecoveryBackup');
    lastSecret = recoverySecret;
    if (recoveryRestoreFails != null) {
      throw BackupProblemException(recoveryRestoreFails!);
    }
    return restoreOutcome;
  }

  @override
  Future<void> deleteRecoveryBackup() async =>
      calls.add('deleteRecoveryBackup');

  @override
  Future<String> sendHistory() async {
    calls.add('sendHistory');
    if (sendFails != null) throw BackupProblemException(sendFails!);
    transferEvents.add(
      const TransferView(
        id: 't1',
        direction: TransferDirection.sending,
        stage: TransferStage.offered,
        done: 2,
        total: 2,
      ),
    );
    return 't1';
  }

  @override
  Future<void> cancelSend(String transferId) async =>
      calls.add('cancelSend:$transferId');

  @override
  Future<RestoreOutcome> acceptOffer(String transferId) async {
    calls.add('acceptOffer:$transferId');
    if (acceptFails != null) throw BackupProblemException(acceptFails!);
    return restoreOutcome;
  }

  @override
  Future<void> declineOffer(String transferId) async =>
      calls.add('declineOffer:$transferId');

  @override
  void pauseOffer(String transferId) => calls.add('pauseOffer:$transferId');
}

// --------------------------------------------------------------- devices

class FakeDevicesGateway implements DevicesGateway {
  final devices = Live<List<DeviceItem>>([
    DeviceItem(
      id: 'd1',
      name: 'Pixel 8',
      platform: 'android',
      isThisDevice: true,
      lastActiveAt: DateTime(2026, 10, 3, 9),
    ),
    DeviceItem(
      id: 'd2',
      name: 'Office laptop',
      platform: 'windows',
      isThisDevice: false,
      lastActiveAt: DateTime(2026, 10, 1, 9),
    ),
  ]);

  final List<String> calls = [];
  Object? refreshFails;
  Object? revokeFails;
  Object? renameFails;
  var revokeOthersCount = 1;
  List<SecurityEventItem> events = [
    SecurityEventItem(
      type: SecurityEventType.deviceAdded,
      at: DateTime(2026, 10, 2, 9),
      deviceName: 'Office laptop',
    ),
    SecurityEventItem(
      type: SecurityEventType.identityChanged,
      at: DateTime(2026, 9, 20, 9),
    ),
  ];

  LinkProblem? inspectFails;
  LinkProblem? approveFails;
  Completer<void>? holdApprove;
  String? approved;
  LinkRequest request = const LinkRequest(
    serverHost: 'helix.example.org',
    check: '482 913',
  );

  FakeLinkSession? session;
  LinkProblem? beginFails;

  @override
  Stream<List<DeviceItem>> watch() => devices.stream;

  @override
  Future<void> refresh() async {
    calls.add('refresh');
    if (refreshFails != null) throw refreshFails!;
  }

  @override
  Future<void> rename(String deviceId, String name) async {
    calls.add('rename:$deviceId:$name');
    if (renameFails != null) throw renameFails!;
  }

  @override
  Future<void> revoke(String deviceId, {bool lost = false}) async {
    calls.add('revoke:$deviceId:${lost ? 'lost' : 'plain'}');
    if (revokeFails != null) throw revokeFails!;
  }

  @override
  Future<int> revokeOthers() async {
    calls.add('revokeOthers');
    if (revokeFails != null) throw revokeFails!;
    return revokeOthersCount;
  }

  @override
  Future<List<SecurityEventItem>> securityEvents() async => events;

  @override
  Future<LinkRequest> inspectLink(String code) async {
    calls.add('inspect');
    if (inspectFails != null) throw LinkProblemException(inspectFails!);
    return request;
  }

  @override
  Future<void> approveLink(String code) async {
    calls.add('approve');
    await holdApprove?.future;
    if (approveFails != null) throw LinkProblemException(approveFails!);
    approved = code;
  }

  @override
  Future<LinkSession> beginLink({String? deviceName}) async {
    calls.add('beginLink');
    if (beginFails != null) throw LinkProblemException(beginFails!);
    return session = FakeLinkSession();
  }
}

class FakeLinkSession implements LinkSession {
  final Completer<void> done = Completer<void>();
  var cancelled = false;

  @override
  String get code =>
      'helix-link:1:https://helix.example.org:0192a4f0-0000-7000-8000-000000000001:AAAA';

  @override
  String get check => '482 913';

  @override
  DateTime get expiresAt => DateTime(2026, 10, 3, 10, 10);

  @override
  Future<void> complete() => done.future;

  @override
  void cancel() => cancelled = true;
}

// --------------------------------------------------------------- profile

class FakeProfileGateway implements ProfileGateway {
  final profile = Live(
    const ProfileData(
      accountId: 'acct-1',
      name: 'Anna Khan',
      about: 'Busy',
      helixName: 'anna.k',
      phoneMasked: '+88017*****01',
    ),
  );

  final List<String> calls = [];
  Object? saveFails;
  Object? helixNameFails;

  @override
  Stream<ProfileData> watch() => profile.stream;

  @override
  Future<void> saveProfile({
    required String name,
    required String about,
  }) async {
    calls.add('save:$name:$about');
    if (saveFails != null) throw saveFails!;
    final p = profile.value;
    profile.set(
      ProfileData(
        accountId: p.accountId,
        name: name,
        about: about,
        helixName: p.helixName,
        phoneMasked: p.phoneMasked,
      ),
    );
  }

  @override
  Future<void> setHelixName(String name) async {
    calls.add('helix:$name');
    if (helixNameFails != null) throw helixNameFails!;
    final p = profile.value;
    profile.set(
      ProfileData(
        accountId: p.accountId,
        name: p.name,
        about: p.about,
        helixName: name,
        phoneMasked: p.phoneMasked,
      ),
    );
  }

  @override
  Future<void> clearHelixName() async {
    calls.add('helix:clear');
    final p = profile.value;
    profile.set(
      ProfileData(
        accountId: p.accountId,
        name: p.name,
        about: p.about,
        phoneMasked: p.phoneMasked,
      ),
    );
  }
}

// -------------------------------------------------------------- settings

class FakeSettingsGateway implements SettingsGateway {
  final header = Live(
    const SettingsHeader(
      accountId: 'acct-1',
      name: 'Anna Khan',
      about: '',
      serverHost: 'helix.example.org',
    ),
  );
  final blocked = Live<List<BlockedPerson>>([
    const BlockedPerson(id: 'b1', name: 'Rahim'),
  ]);
  final muted = Live<List<MutedChat>>([
    const MutedChat(id: 'c1', title: 'Family'),
  ]);

  var overview = const AccountOverview(
    phoneMasked: '+88017*****01',
    helixName: 'anna.k',
    hasPassword: true,
  );
  var prefs = const PrivacyPrefs();
  var details = const ServerDetails(
    name: 'Helix Global',
    host: 'helix.example.org',
    version: '2.0.0',
    openRegistration: true,
    maxAttachmentBytes: 100 * 1024 * 1024,
    termsVersion: '2026-09-25',
    privacyVersion: '2026-09-25',
    features: {'crash_reporting_upload': true, 'group_calls': false},
  );
  var legalText = const LegalText(
    termsTitle: 'Helix Global Terms of Service',
    termsVersion: '2026-09-25',
    terms: 'These are the terms.',
    privacyTitle: 'Helix Global Privacy Policy',
    privacyVersion: '2026-09-25',
    privacy: 'This is the privacy policy.',
    fromServer: true,
  );

  final List<String> calls = [];
  Object? accountFails;
  Object? changePasswordFails;
  Object? exportFails;
  Object? deleteFails;
  Object? privacyLoadFails;
  Object? privacySaveFails;
  Object? serverFails;
  Object? syncFails;
  PrivacyPrefs? savedPrefs;
  String? changedTo;
  String? changedCurrent;

  @override
  Stream<SettingsHeader> watchHeader() => header.stream;

  @override
  Future<AccountOverview> account() async {
    if (accountFails != null) throw accountFails!;
    return overview;
  }

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? phoneNumber,
  }) async {
    calls.add('changePassword');
    if (changePasswordFails != null) throw changePasswordFails!;
    changedTo = newPassword;
    changedCurrent = currentPassword;
  }

  @override
  Future<Uint8List> exportAccount() async {
    calls.add('export');
    if (exportFails != null) throw exportFails!;
    return Uint8List.fromList('{"account_id":"acct-1"}'.codeUnits);
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    if (deleteFails != null) throw deleteFails!;
  }

  @override
  Future<PrivacyPrefs> privacy() async {
    if (privacyLoadFails != null) throw privacyLoadFails!;
    return prefs;
  }

  @override
  Future<void> setPrivacy(PrivacyPrefs next) async {
    calls.add('setPrivacy');
    if (privacySaveFails != null) throw privacySaveFails!;
    savedPrefs = next;
    prefs = next;
  }

  @override
  Stream<List<BlockedPerson>> watchBlocked() => blocked.stream;

  @override
  Future<void> unblock(String accountId) async {
    calls.add('unblock:$accountId');
    blocked.set([
      for (final p in blocked.value)
        if (p.id != accountId) p,
    ]);
  }

  @override
  Stream<List<MutedChat>> watchMuted() => muted.stream;

  @override
  Future<void> unmute(String chatId) async {
    calls.add('unmute:$chatId');
    muted.set([
      for (final c in muted.value)
        if (c.id != chatId) c,
    ]);
  }

  @override
  Future<ServerDetails> serverDetails() async {
    if (serverFails != null) throw serverFails!;
    return details;
  }

  @override
  Future<LegalText> legal() async => legalText;

  @override
  Future<void> syncNow() async {
    calls.add('syncNow');
    if (syncFails != null) throw syncFails!;
  }
}

// ----------------------------------------------------------------- harness

/// The overrides every settings-side test needs. Pass the fakes you want to
/// drive; the rest get quiet defaults.
List<Override> a3bOverrides({
  FakeLocalSettings? settings,
  FakeBackupGateway? backup,
  FakeDevicesGateway? devices,
  FakeProfileGateway? profile,
  FakeSettingsGateway? settingsGateway,
  FakeDeviceAuthenticator? auth,
  FakeShareAdapter? share,
  FakeNetworkProbe? network,
  FakeStorageProbe? storage,
  FakeNotificationPermission? permission,
  FakeProfileImageSource? imageSource,
  FakeAvatarStore? avatars,
  DateTime? now,
  List<Override> extra = const [],
}) {
  final clock = now ?? DateTime(2026, 10, 3, 10);
  final store = settings ?? FakeLocalSettings();
  return [
    // The lock reads its setting through a core provider that would open an
    // engine; here it reads the same fake store the switches write.
    appLockSettingProvider.overrideWith(
      (ref) => store
          .watch(AppSettings.appLockEnabled)
          .map(
            (enabled) => AppLockSetting(
              enabled: enabled,
              relockAfterSeconds: store.read(
                AppSettings.appLockRelockAfterSeconds,
              ),
            ),
          ),
    ),
    clockProvider.overrideWithValue(() => clock),
    localSettingsProvider.overrideWithValue(store),
    if (backup != null) backupGatewayProvider.overrideWithValue(backup),
    if (devices != null) devicesGatewayProvider.overrideWithValue(devices),
    if (profile != null) profileGatewayProvider.overrideWithValue(profile),
    if (settingsGateway != null)
      settingsGatewayProvider.overrideWithValue(settingsGateway),
    deviceAuthenticatorProvider.overrideWithValue(
      auth ?? FakeDeviceAuthenticator(),
    ),
    shareAdapterProvider.overrideWithValue(share ?? FakeShareAdapter()),
    networkProbeProvider.overrideWithValue(network ?? FakeNetworkProbe()),
    storageUsageProbeProvider.overrideWithValue(storage ?? FakeStorageProbe()),
    notificationPermissionSourceProvider.overrideWithValue(
      permission ?? FakeNotificationPermission(),
    ),
    profileImageSourceProvider.overrideWithValue(
      imageSource ?? FakeProfileImageSource(),
    ),
    profileAvatarStoreProvider.overrideWithValue(avatars ?? FakeAvatarStore()),
    // Nothing here may open an engine.
    runtimeFactoryProvider.overrideWithValue(_NoRuntime()),
    ...extra,
  ];
}

final class _NoRuntime implements RuntimeFactory {
  @override
  Future<Never> open({required Uri serverUrl}) =>
      throw StateError('these tests must not open an engine');
}

/// A container that does not retry failed providers. Riverpod 3 retries a
/// provider that throws, on a timer, which is right for an app and wrong for a
/// test that is checking the error state.
ProviderContainer newContainer(List<Override> overrides) =>
    ProviderContainer(overrides: overrides, retry: (_, _) => null);

/// Pumps [routes] in a real [GoRouter] under the Helix theme, at [textScale]
/// (the phone's own setting), and returns the router so a test can read where
/// it is.
Future<GoRouter> pumpRoutes(
  WidgetTester tester, {
  required String initial,
  required List<RouteBase> routes,
  List<Override> overrides = const [],
  double textScale = 1,
  ProviderContainer? container,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final router = GoRouter(initialLocation: initial, routes: routes);
  addTearDown(router.dispose);
  final scope = container ?? newContainer(overrides);
  if (container == null) addTearDown(scope.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp.router(
        theme: HelixThemes.light(),
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return router;
}

/// A route that only says where it is, standing in for a page under another
/// feature so a navigation can be asserted without building it.
GoRoute stubRoute(String path) => GoRoute(
  path: path,
  builder: (context, state) => Scaffold(body: Text('stub:$path')),
);

/// Pumps one page at the root of a router (so `context.push` works) with
/// stubs for the paths it may open.
Future<GoRouter> pumpPage(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
  double textScale = 1,
  List<String> stubs = const [],
  ProviderContainer? container,
}) => pumpRoutes(
  tester,
  initial: '/page',
  routes: [
    GoRoute(path: '/page', builder: (context, state) => page),
    for (final path in stubs) stubRoute(path),
  ],
  overrides: overrides,
  textScale: textScale,
  container: container,
);

/// Makes the test window tall, so a long `ListView` builds every row.
void useTallWindow(WidgetTester tester, {double height = 3200}) {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets streams, futures and dialog animations run. Not `pumpAndSettle`: a
/// page showing a progress bar never settles, and that is correct.
Future<void> settle(WidgetTester tester, {int times = 8}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls the page until [finder] is fully on screen. A `ListView` builds
/// only what is near the viewport, so the widget may not exist until then.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Gives linking this device a name without asking the platform.
final Override engineConfigNameOverride = engineConfigProvider.overrideWith(
  (ref) async => const EngineConfig(deviceName: 'Test phone'),
);
