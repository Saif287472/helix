import 'package:meta/meta.dart';
import 'package:helix_local_domain/core/constants.dart';

enum DiscoverabilityState { discoverable, hidden }

@immutable
class Profile {
  final String displayName;
  final DiscoverabilityState discoverability;
  final bool notifyShowSender;
  final bool notifySound;
  final bool copyEnabled;
  final bool screenshotProtect;
  final String themeMode;
  final String accentColor;
  final bool amoledDark;
  final bool readReceiptsEnabled;
  final bool typingIndicatorsEnabled;
  final bool homeWelcomeDismissed;
  final bool biometricLock;
  final int lockAfterMinutes;
  final String ringtoneAsset;

  const Profile({
    required this.displayName,
    required this.discoverability,
    this.notifyShowSender = false,
    this.notifySound = true,
    this.copyEnabled = false,
    this.screenshotProtect = true,
    this.themeMode = 'system',
    this.accentColor = 'teal',
    this.amoledDark = false,
    this.readReceiptsEnabled = true,
    this.typingIndicatorsEnabled = true,
    this.homeWelcomeDismissed = false,
    this.biometricLock = false,
    this.lockAfterMinutes = 0,
    this.ringtoneAsset = kDefaultRingtoneAsset,
  });

  Profile copyWith({
    String? displayName,
    DiscoverabilityState? discoverability,
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
  }) => Profile(
    displayName: displayName ?? this.displayName,
    discoverability: discoverability ?? this.discoverability,
    notifyShowSender: notifyShowSender ?? this.notifyShowSender,
    notifySound: notifySound ?? this.notifySound,
    copyEnabled: copyEnabled ?? this.copyEnabled,
    screenshotProtect: screenshotProtect ?? this.screenshotProtect,
    themeMode: themeMode ?? this.themeMode,
    accentColor: accentColor ?? this.accentColor,
    amoledDark: amoledDark ?? this.amoledDark,
    readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
    typingIndicatorsEnabled:
        typingIndicatorsEnabled ?? this.typingIndicatorsEnabled,
    homeWelcomeDismissed: homeWelcomeDismissed ?? this.homeWelcomeDismissed,
    biometricLock: biometricLock ?? this.biometricLock,
    lockAfterMinutes: lockAfterMinutes ?? this.lockAfterMinutes,
    ringtoneAsset: ringtoneAsset ?? this.ringtoneAsset,
  );

  /// Returns a copy with every user-configurable preference restored to its
  /// default value. Identity fields (displayName, discoverability) and
  /// [homeWelcomeDismissed] (an internal one-time flag, not a setting) are
  /// left untouched.
  Profile resetToDefaultPreferences() {
    const defaults = Profile(
      displayName: '',
      discoverability: DiscoverabilityState.hidden,
    );
    return copyWith(
      notifyShowSender: defaults.notifyShowSender,
      notifySound: defaults.notifySound,
      copyEnabled: defaults.copyEnabled,
      screenshotProtect: defaults.screenshotProtect,
      themeMode: defaults.themeMode,
      accentColor: defaults.accentColor,
      amoledDark: defaults.amoledDark,
      readReceiptsEnabled: defaults.readReceiptsEnabled,
      typingIndicatorsEnabled: defaults.typingIndicatorsEnabled,
      biometricLock: defaults.biometricLock,
      lockAfterMinutes: defaults.lockAfterMinutes,
      ringtoneAsset: defaults.ringtoneAsset,
    );
  }
}
