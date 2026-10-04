import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show SettingsService;

/// The typed, on-device settings store, as the settings pages see it.
///
/// A seam rather than the engine, so every settings notifier can be tested
/// with an in-memory store and no database.
abstract interface class LocalSettings {
  Future<T> get<T>(Setting<T> setting);

  Stream<T> watch<T>(Setting<T> setting);

  Future<void> set<T>(Setting<T> setting, T value);
}

final class EngineLocalSettings implements LocalSettings {
  const EngineLocalSettings(this._ref);

  final Ref _ref;

  Future<SettingsService> get _settings async =>
      (await _ref.read(runtimeProvider.future)).engine.settings;

  @override
  Future<T> get<T>(Setting<T> setting) async =>
      (await _settings).get<T>(setting);

  @override
  Stream<T> watch<T>(Setting<T> setting) async* {
    final settings = await _settings;
    yield* settings.watch<T>(setting);
  }

  @override
  Future<void> set<T>(Setting<T> setting, T value) async {
    await (await _settings).set<T>(setting, value);
  }
}

final localSettingsProvider = Provider<LocalSettings>(EngineLocalSettings.new);

/// A live value of one setting, as a provider.
///
/// ```dart
/// final readReceiptsProvider = settingProvider(EngineSettings.sendReadReceipts);
/// ```
StreamProvider<T> settingProvider<T>(Setting<T> setting) =>
    StreamProvider<T>((ref) => ref.watch(localSettingsProvider).watch(setting));
