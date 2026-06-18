import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_domain/application/contracts/repositories.dart';

class FlutterProfileRepository implements ProfileRepository {
  final FlutterSecureStorage _storage;

  const FlutterProfileRepository({
    this._storage = const FlutterSecureStorage(),
  });

  @override
  Future<Profile?> loadProfile() async {
    final displayName = await _storage.read(key: kKeyDisplayName);
    if (displayName == null) return null;

    final discRaw = await _storage.read(key: kKeyDiscoverable);
    final notifyRaw = await _storage.read(key: kKeyNotifyShowSender);
    final notifySoundRaw = await _storage.read(key: kKeyNotifySound);
    final copyRaw = await _storage.read(key: kKeyCopyEnabled);
    final screenshotRaw = await _storage.read(key: kKeyScreenshotProtect);
    final themeRaw = await _storage.read(key: kKeyThemeMode);
    final accentRaw = await _storage.read(key: kKeyAccentColor);
    final amoledRaw = await _storage.read(key: kKeyAmoledDark);
    final readRaw = await _storage.read(key: kKeyReadReceiptsEnabled);
    final typingRaw = await _storage.read(key: kKeyTypingIndicatorsEnabled);
    final welcomeRaw = await _storage.read(key: kKeyHomeWelcomeDismissed);
    final biometricRaw = await _storage.read(key: kKeyBiometricLock);
    final lockMinutesRaw = await _storage.read(key: kKeyLockAfterMinutes);
    final ringtoneRaw = await _storage.read(key: kKeyRingtoneAsset);

    return Profile(
      displayName: displayName,
      discoverability: discRaw == '1'
          ? DiscoverabilityState.discoverable
          : DiscoverabilityState.hidden,
      notifyShowSender: notifyRaw == '1',
      notifySound: notifySoundRaw != '0',
      copyEnabled: copyRaw == '1',
      screenshotProtect: screenshotRaw != '0', // default true when null
      themeMode: themeRaw ?? 'system',
      accentColor: accentRaw ?? 'teal',
      amoledDark: amoledRaw == '1',
      readReceiptsEnabled: readRaw != '0',
      typingIndicatorsEnabled: typingRaw != '0',
      homeWelcomeDismissed: welcomeRaw == '1',
      biometricLock: biometricRaw == '1',
      lockAfterMinutes: int.tryParse(lockMinutesRaw ?? '0') ?? 0,
      ringtoneAsset: kAvailableRingtoneAssets.contains(ringtoneRaw)
          ? ringtoneRaw!
          : kDefaultRingtoneAsset,
    );
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    await _storage.write(key: kKeyDisplayName, value: profile.displayName);
    await _storage.write(
      key: kKeyDiscoverable,
      value: profile.discoverability == DiscoverabilityState.discoverable
          ? '1'
          : '0',
    );
    await _storage.write(
      key: kKeyNotifyShowSender,
      value: profile.notifyShowSender ? '1' : '0',
    );
    await _storage.write(
      key: kKeyNotifySound,
      value: profile.notifySound ? '1' : '0',
    );
    await _storage.write(
      key: kKeyCopyEnabled,
      value: profile.copyEnabled ? '1' : '0',
    );
    await _storage.write(
      key: kKeyScreenshotProtect,
      value: profile.screenshotProtect ? '1' : '0',
    );
    await _storage.write(key: kKeyThemeMode, value: profile.themeMode);
    await _storage.write(key: kKeyAccentColor, value: profile.accentColor);
    await _storage.write(
      key: kKeyAmoledDark,
      value: profile.amoledDark ? '1' : '0',
    );
    await _storage.write(
      key: kKeyReadReceiptsEnabled,
      value: profile.readReceiptsEnabled ? '1' : '0',
    );
    await _storage.write(
      key: kKeyTypingIndicatorsEnabled,
      value: profile.typingIndicatorsEnabled ? '1' : '0',
    );
    await _storage.write(
      key: kKeyHomeWelcomeDismissed,
      value: profile.homeWelcomeDismissed ? '1' : '0',
    );
    await _storage.write(
      key: kKeyBiometricLock,
      value: profile.biometricLock ? '1' : '0',
    );
    await _storage.write(
      key: kKeyLockAfterMinutes,
      value: profile.lockAfterMinutes.toString(),
    );
    await _storage.write(
      key: kKeyRingtoneAsset,
      value: profile.ringtoneAsset,
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: kKeyDisplayName);
    await _storage.delete(key: kKeyDiscoverable);
    await _storage.delete(key: kKeyNotifyShowSender);
    await _storage.delete(key: kKeyNotifySound);
    await _storage.delete(key: kKeyCopyEnabled);
    await _storage.delete(key: kKeyScreenshotProtect);
    await _storage.delete(key: kKeyThemeMode);
    await _storage.delete(key: kKeyAccentColor);
    await _storage.delete(key: kKeyAmoledDark);
    await _storage.delete(key: kKeyReadReceiptsEnabled);
    await _storage.delete(key: kKeyTypingIndicatorsEnabled);
    await _storage.delete(key: kKeyHomeWelcomeDismissed);
    await _storage.delete(key: kKeyBiometricLock);
    await _storage.delete(key: kKeyLockAfterMinutes);
    await _storage.delete(key: kKeyRingtoneAsset);
  }
}
