import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_domain/application/contracts/repositories.dart';

class FlutterProfileRepository implements ProfileRepository {
  final FlutterSecureStorage _storage;
  final String keyPrefix;

  const FlutterProfileRepository({
    this._storage = const FlutterSecureStorage(),
    this.keyPrefix = '',
  });

  @override
  Future<Profile?> loadProfile() async {
    final hasPrefixedKey = await _storage.read(key: '$keyPrefix$kKeyDisplayName');
    if (hasPrefixedKey == null && keyPrefix.startsWith('helix_local_')) {
      final oldDisplayName = await _storage.read(key: kKeyDisplayName);
      if (oldDisplayName != null) {
        final oldDisc = await _storage.read(key: kKeyDiscoverable);
        final oldNotify = await _storage.read(key: kKeyNotifyShowSender);
        final oldNotifySound = await _storage.read(key: kKeyNotifySound);
        final oldCopy = await _storage.read(key: kKeyCopyEnabled);
        final oldScreenshot = await _storage.read(key: kKeyScreenshotProtect);
        final oldTheme = await _storage.read(key: kKeyThemeMode);
        final oldAccent = await _storage.read(key: kKeyAccentColor);
        final oldAmoled = await _storage.read(key: kKeyAmoledDark);
        final oldRead = await _storage.read(key: kKeyReadReceiptsEnabled);
        final oldTyping = await _storage.read(key: kKeyTypingIndicatorsEnabled);
        final oldWelcome = await _storage.read(key: kKeyHomeWelcomeDismissed);
        final oldBiometric = await _storage.read(key: kKeyBiometricLock);
        final oldLockMinutes = await _storage.read(key: kKeyLockAfterMinutes);
        final oldRingtone = await _storage.read(key: kKeyRingtoneAsset);

        await _storage.write(key: '$keyPrefix$kKeyDisplayName', value: oldDisplayName);
        if (oldDisc != null) await _storage.write(key: '$keyPrefix$kKeyDiscoverable', value: oldDisc);
        if (oldNotify != null) await _storage.write(key: '$keyPrefix$kKeyNotifyShowSender', value: oldNotify);
        if (oldNotifySound != null) await _storage.write(key: '$keyPrefix$kKeyNotifySound', value: oldNotifySound);
        if (oldCopy != null) await _storage.write(key: '$keyPrefix$kKeyCopyEnabled', value: oldCopy);
        if (oldScreenshot != null) await _storage.write(key: '$keyPrefix$kKeyScreenshotProtect', value: oldScreenshot);
        if (oldTheme != null) await _storage.write(key: '$keyPrefix$kKeyThemeMode', value: oldTheme);
        if (oldAccent != null) await _storage.write(key: '$keyPrefix$kKeyAccentColor', value: oldAccent);
        if (oldAmoled != null) await _storage.write(key: '$keyPrefix$kKeyAmoledDark', value: oldAmoled);
        if (oldRead != null) await _storage.write(key: '$keyPrefix$kKeyReadReceiptsEnabled', value: oldRead);
        if (oldTyping != null) await _storage.write(key: '$keyPrefix$kKeyTypingIndicatorsEnabled', value: oldTyping);
        if (oldWelcome != null) await _storage.write(key: '$keyPrefix$kKeyHomeWelcomeDismissed', value: oldWelcome);
        if (oldBiometric != null) await _storage.write(key: '$keyPrefix$kKeyBiometricLock', value: oldBiometric);
        if (oldLockMinutes != null) await _storage.write(key: '$keyPrefix$kKeyLockAfterMinutes', value: oldLockMinutes);
        if (oldRingtone != null) await _storage.write(key: '$keyPrefix$kKeyRingtoneAsset', value: oldRingtone);

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

    final displayName = await _storage.read(key: '$keyPrefix$kKeyDisplayName');
    if (displayName == null) return null;

    final discRaw = await _storage.read(key: '$keyPrefix$kKeyDiscoverable');
    final notifyRaw = await _storage.read(key: '$keyPrefix$kKeyNotifyShowSender');
    final notifySoundRaw = await _storage.read(key: '$keyPrefix$kKeyNotifySound');
    final copyRaw = await _storage.read(key: '$keyPrefix$kKeyCopyEnabled');
    final screenshotRaw = await _storage.read(key: '$keyPrefix$kKeyScreenshotProtect');
    final themeRaw = await _storage.read(key: '$keyPrefix$kKeyThemeMode');
    final accentRaw = await _storage.read(key: '$keyPrefix$kKeyAccentColor');
    final amoledRaw = await _storage.read(key: '$keyPrefix$kKeyAmoledDark');
    final readRaw = await _storage.read(key: '$keyPrefix$kKeyReadReceiptsEnabled');
    final typingRaw = await _storage.read(key: '$keyPrefix$kKeyTypingIndicatorsEnabled');
    final welcomeRaw = await _storage.read(key: '$keyPrefix$kKeyHomeWelcomeDismissed');
    final biometricRaw = await _storage.read(key: '$keyPrefix$kKeyBiometricLock');
    final lockMinutesRaw = await _storage.read(key: '$keyPrefix$kKeyLockAfterMinutes');
    final ringtoneRaw = await _storage.read(key: '$keyPrefix$kKeyRingtoneAsset');

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
    await _storage.write(key: '$keyPrefix$kKeyDisplayName', value: profile.displayName);
    await _storage.write(
      key: '$keyPrefix$kKeyDiscoverable',
      value: profile.discoverability == DiscoverabilityState.discoverable
          ? '1'
          : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyNotifyShowSender',
      value: profile.notifyShowSender ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyNotifySound',
      value: profile.notifySound ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyCopyEnabled',
      value: profile.copyEnabled ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyScreenshotProtect',
      value: profile.screenshotProtect ? '1' : '0',
    );
    await _storage.write(key: '$keyPrefix$kKeyThemeMode', value: profile.themeMode);
    await _storage.write(key: '$keyPrefix$kKeyAccentColor', value: profile.accentColor);
    await _storage.write(
      key: '$keyPrefix$kKeyAmoledDark',
      value: profile.amoledDark ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyReadReceiptsEnabled',
      value: profile.readReceiptsEnabled ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyTypingIndicatorsEnabled',
      value: profile.typingIndicatorsEnabled ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyHomeWelcomeDismissed',
      value: profile.homeWelcomeDismissed ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyBiometricLock',
      value: profile.biometricLock ? '1' : '0',
    );
    await _storage.write(
      key: '$keyPrefix$kKeyLockAfterMinutes',
      value: profile.lockAfterMinutes.toString(),
    );
    await _storage.write(
      key: '$keyPrefix$kKeyRingtoneAsset',
      value: profile.ringtoneAsset,
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: '$keyPrefix$kKeyDisplayName');
    await _storage.delete(key: '$keyPrefix$kKeyDiscoverable');
    await _storage.delete(key: '$keyPrefix$kKeyNotifyShowSender');
    await _storage.delete(key: '$keyPrefix$kKeyNotifySound');
    await _storage.delete(key: '$keyPrefix$kKeyCopyEnabled');
    await _storage.delete(key: '$keyPrefix$kKeyScreenshotProtect');
    await _storage.delete(key: '$keyPrefix$kKeyThemeMode');
    await _storage.delete(key: '$keyPrefix$kKeyAccentColor');
    await _storage.delete(key: '$keyPrefix$kKeyAmoledDark');
    await _storage.delete(key: '$keyPrefix$kKeyReadReceiptsEnabled');
    await _storage.delete(key: '$keyPrefix$kKeyTypingIndicatorsEnabled');
    await _storage.delete(key: '$keyPrefix$kKeyHomeWelcomeDismissed');
    await _storage.delete(key: '$keyPrefix$kKeyBiometricLock');
    await _storage.delete(key: '$keyPrefix$kKeyLockAfterMinutes');
    await _storage.delete(key: '$keyPrefix$kKeyRingtoneAsset');
  }
}
