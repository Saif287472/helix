import 'dart:async';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/identity/identity_manager_impl.dart';
import 'package:helix_local_storage/infrastructure/storage/flutter_profile_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/flutter_secure_identity_store.dart';

class ProfileService {
  final IdentityManager _identityManager;

  ProfileService({IdentityManager? identityManager})
    : _identityManager =
          identityManager ??
          IdentityManagerImpl(
            profileRepository: const FlutterProfileRepository(),
            secureIdentityStore: const FlutterSecureIdentityStore(),
          );

  Profile? get profile => _identityManager.profile;
  DeviceIdentity? get identity => _identityManager.identity;
  bool get isFirstRun => _identityManager.isFirstRun;
  Stream<Profile> get profileChanges => _identityManager.profileChanges;

  Future<void> init() async {
    await _identityManager.init();
  }

  Future<void> createProfile(
    String displayName,
    String secretCode,
    DiscoverabilityState disc,
  ) async {
    await _identityManager.createProfile(displayName, secretCode, disc);
  }

  Future<void> updateDisplayName(String name) async {
    await _identityManager.updateDisplayName(name);
  }

  Future<void> updateSecretCode(String code) async {
    await _identityManager.updateSecretCode(code);
  }

  Future<String?> getSecretCode() => _identityManager.getSecretCode();

  Future<String?> getSecretCodeVerifier() =>
      _identityManager.getSecretCodeVerifier();

  Future<void> updateDiscoverability(DiscoverabilityState state) async {
    await _identityManager.updateDiscoverability(state);
  }

  Future<void> updatePreferences({
    bool? notifyShowSender,
    bool? notifySound,
    bool? copyEnabled,
    bool? screenshotProtect,
    String? themeMode,
    String? accentColor,
    bool? amoledDark,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? homeWelcomeDismissed,
    bool? biometricLock,
    int? lockAfterMinutes,
    String? ringtoneAsset,
  }) async {
    await _identityManager.updatePreferences(
      notifyShowSender: notifyShowSender,
      notifySound: notifySound,
      copyEnabled: copyEnabled,
      screenshotProtect: screenshotProtect,
      themeMode: themeMode,
      accentColor: accentColor,
      amoledDark: amoledDark,
      readReceiptsEnabled: readReceiptsEnabled,
      typingIndicatorsEnabled: typingIndicatorsEnabled,
      homeWelcomeDismissed: homeWelcomeDismissed,
      biometricLock: biometricLock,
      lockAfterMinutes: lockAfterMinutes,
      ringtoneAsset: ringtoneAsset,
    );
  }

  Future<void> resetPreferencesToDefaults() async {
    await _identityManager.resetPreferencesToDefaults();
  }

  Future<void> reset() async {
    await _identityManager.reset();
  }

  String generateDicewarePassphrase() {
    return _identityManager.generateDicewarePassphrase();
  }

  String? validateDisplayName(String s) {
    return _identityManager.validateDisplayName(s);
  }

  String? validateSecretCode(String s) {
    return _identityManager.validateSecretCode(s);
  }

  void dispose() {
    _identityManager.dispose();
  }
}
