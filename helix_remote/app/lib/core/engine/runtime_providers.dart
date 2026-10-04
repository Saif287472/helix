import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform;

/// Opens the app's one live [HelixRuntime] for a server.
///
/// This is the seam between the app and the engine. Everything above it works
/// with a runtime it was handed; tests and the widget suite replace this with
/// one backed by an in-memory database, so no test ever opens a real file,
/// a keystore or a socket.
abstract interface class RuntimeFactory {
  Future<HelixRuntime> open({required Uri serverUrl});
}

/// The real factory: keystore, encrypted file on disk, live network.
final class DeviceRuntimeFactory implements RuntimeFactory {
  DeviceRuntimeFactory({
    SecureKeyStore? keys,
    PhoneBook? phoneBook,
    Future<EngineConfig> Function()? config,
  }) : _keys = keys ?? SecureKeyStore(),
       _phoneBook = phoneBook ?? const DevicePhoneBook(),
       _config = config ?? _defaultEngineConfig;

  final SecureKeyStore _keys;
  final PhoneBook _phoneBook;
  final Future<EngineConfig> Function() _config;

  /// Used when no configuration is injected. The real device name comes from
  /// `engineConfigProvider`, which needs the platform plugin; this is the
  /// fallback for a host without one.
  static Future<EngineConfig> _defaultEngineConfig() async => engineConfigFor(
    deviceName: 'Helix device',
    platform: currentDevicePlatform,
  );

  @override
  Future<HelixRuntime> open({required Uri serverUrl}) async {
    final file = await AppPaths.databaseFile();
    return HelixRuntime.open(
      dbFile: file,
      key: await _keys.keyFor(file),
      serverUrl: serverUrl,
      phoneBook: _phoneBook,
      config: await _config(),
    );
  }
}

final runtimeFactoryProvider = Provider<RuntimeFactory>(
  (ref) => DeviceRuntimeFactory(
    phoneBook: DevicePhoneBook(
      access: ref.watch(contactsAccessProvider),
      country: ref.watch(phoneCountryProvider),
    ),
  ),
);

/// The country code bare national numbers are read in (the prefix of this
/// account's own number), shared by the address-book adapter the engine holds
/// and the people search. See [PhoneCountry].
final phoneCountryProvider = Provider<PhoneCountry>((ref) => PhoneCountry());

/// The remembered server URL, in the keystore. Overridden in tests so nothing
/// writes to the platform.
final serverUrlStoreProvider = Provider<ServerUrlStore>(
  (ref) => ServerUrlStore(),
);

/// The server this device talks to.
///
/// Null until something chooses one. Sign-in opens on Helix Global, so the
/// app has a server before it has an account; the choice is remembered in the
/// keystore by [ServerUrlStore] once an account exists on it.
final serverUrlProvider = NotifierProvider<ServerUrlNotifier, Uri?>(
  ServerUrlNotifier.new,
);

final class ServerUrlNotifier extends Notifier<Uri?> {
  @override
  Uri? build() => null;

  /// Points the app at [url], which tears the runtime down and opens a new one
  /// (see [runtimeProvider]). Used by sign-in and by the sign-out path.
  void use(Uri url) => state = url;

  /// Forgets the server, so the next screen is sign-in on Helix Global.
  void forget() => state = null;
}

/// The live runtime, or the reason there is not one yet.
///
/// Watching this is how the app learns that the server changed: the old
/// runtime is closed by [runtimeProvider]'s `onDispose` before the new one
/// opens.
final runtimeProvider = FutureProvider<HelixRuntime>((ref) async {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null) {
    throw const NoServerChosen();
  }
  final runtime = await ref
      .watch(runtimeFactoryProvider)
      .open(serverUrl: serverUrl);
  ref.onDispose(runtime.close);
  return runtime;
});

/// Thrown by [runtimeProvider] before a server is chosen. Sign-in is what
/// chooses one, so this is the normal "nobody is signed in" state rather than
/// a failure.
final class NoServerChosen implements Exception {
  const NoServerChosen();

  @override
  String toString() => 'no server has been chosen yet';
}

/// This device's name and platform, sent with registration so the account's
/// other devices can label it.
final engineConfigProvider = FutureProvider<EngineConfig>((ref) async {
  final platform = currentDevicePlatform;
  return engineConfigFor(
    deviceName: await _deviceName(platform),
    platform: platform,
  );
});

Future<String> _deviceName(DevicePlatform platform) async {
  final model = switch (platform) {
    DevicePlatform.android => await _androidModel(),
    DevicePlatform.windows => Platform.operatingSystemVersion,
    _ => null,
  };
  final label = model?.trim();
  if (label == null || label.isEmpty) return 'Helix device';
  return label.length <= 60 ? label : label.substring(0, 60);
}

Future<String?> _androidModel() async {
  try {
    return (await DeviceInfoPlugin().androidInfo).model;
  } on Object {
    // No plugin (tests, a platform without it): the generic name is fine.
    return null;
  }
}

/// `EngineConfig` for tests: short timers, and no wiping so a revocation can
/// be inspected.
EngineConfig testEngineConfig({EngineConfig? base}) =>
    (base ?? const EngineConfig()).copyWith(
      maintenanceInterval: const Duration(seconds: 30),
    );
