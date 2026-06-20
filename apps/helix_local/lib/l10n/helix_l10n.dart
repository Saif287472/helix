// lib/l10n/helix_l10n.dart
//
// Hand-written localizations for Helix Local.
// Mirrors the structure produced by `flutter gen-l10n` so that code-generation
// can replace this file when a translation team onboards.
//
// Usage:
//   final l10n = HelixLocalizations.of(context);
//   Text(l10n.navHome);
//
// Add HelixLocalizations.delegate and HelixLocalizations.supportedLocales to
// MaterialApp.localizationsDelegates / supportedLocales.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class HelixLocalizations {
  const HelixLocalizations(this.locale);

  final Locale locale;

  static HelixLocalizations of(BuildContext context) {
    return Localizations.of<HelixLocalizations>(context, HelixLocalizations) ??
        const HelixLocalizations(Locale('en'));
  }

  static const LocalizationsDelegate<HelixLocalizations> delegate =
      _HelixLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en')];

  // ── App ──────────────────────────────────────────────────────────────────────
  String get appName => 'Helix';
  String get appTagline => 'Private, ephemeral LAN messaging';

  // ── Navigation ────────────────────────────────────────────────────────────────
  String get navHome => 'Home';
  String get navRequests => 'Requests';
  String get navChats => 'Chats';
  String get navSettings => 'Settings';

  // ── Common actions ────────────────────────────────────────────────────────────
  String get actionOk => 'OK';
  String get actionCancel => 'Cancel';
  String get actionDelete => 'Delete';
  String get actionRetry => 'Try again';
  String get actionSave => 'Save';
  String get actionBack => 'Back';
  String get actionClose => 'Close';
  String get actionDone => 'Done';
  String get actionContinue => 'Continue';
  String get actionSkip => 'Skip';
  String get actionAccept => 'Accept';
  String get actionReject => 'Decline';
  String get actionReset => 'Reset';

  // ── Status / connection ───────────────────────────────────────────────────────
  String get statusConnected => 'Connected';
  String get statusConnecting => 'Connecting…';
  String get statusDisconnected => 'Disconnected';
  String get statusOffline => 'Offline';
  String get statusLoading => 'Loading…';
  String get statusError => 'Something went wrong';
  String get statusEmpty => 'Nothing here yet';
  String get statusSearching => 'Searching…';
  String get statusSending => 'Sending…';

  // ── Setup ─────────────────────────────────────────────────────────────────────
  String get setupWelcome => 'Welcome to Helix';
  String get setupSubtitle =>
      'Private, ephemeral peer-to-peer messaging on your local network.';
  String get setupNameLabel => 'Your display name';
  String get setupNameHint => 'e.g. Alex';
  String get setupNameRequired => 'Display name is required.';
  String get setupNameTooLong => 'Name must be 32 characters or fewer.';
  String get setupNameInvalid => 'Name contains unsupported characters.';
  String get setupCodeLabel => 'Secret code';
  String get setupCodeHint => 'Minimum 8 characters';
  String get setupCodeRequired => 'Secret code is required.';
  String get setupCodeTooShort => 'Code must be at least 8 characters.';
  String get setupConfirmCodeLabel => 'Confirm code';
  String get setupConfirmRequired => 'Please confirm your code.';
  String get setupConfirmMismatch => 'Codes do not match.';
  String get setupDiscoverableLabel =>
      'Make me discoverable to nearby devices';
  String get setupCreateButton => 'Create identity';
  String get setupCreating => 'Creating identity…';
  String get setupCodeNote =>
      'Your secret code is never transmitted. It is used locally to prove '
      'identity when another device tries to connect.';

  // ── Home tab ──────────────────────────────────────────────────────────────────
  String get homeNearbyPeers => 'Nearby';
  String get homeNoPeers => 'No devices found nearby';
  String get homeNoPeersHint =>
      'Make sure the other device has Helix open and is on the same network.';
  String get homeConnectQr => 'Connect via QR';
  String get homeConnectSecretCode => 'Connect via secret code';
  String get homeConnectDirectIp => 'Connect by IP address';
  String get homeSessionNotStarted => 'Session not started';
  String get homeSessionStarting => 'Starting session…';
  String get homeSessionError => 'Session failed to start';
  String get homeRefresh => 'Refresh';

  // ── Requests tab ─────────────────────────────────────────────────────────────
  String get requestsEmpty => 'No pending requests';
  String get requestsEmptyHint =>
      'Connection requests from other Helix devices will appear here.';
  String requestsFrom(String name) => 'Request from $name';
  String requestsCount(int count) =>
      '$count pending request${count == 1 ? '' : 's'}';

  // ── Chats tab ────────────────────────────────────────────────────────────────
  String get chatsEmpty => 'No active chats';
  String get chatsEmptyHint =>
      'Accept a connection request or connect via QR to start chatting.';
  String get chatSendHint => 'Message';
  String get chatConnecting => 'Connecting…';
  String get chatDisconnectedBanner => 'Peer disconnected';
  String unreadCount(int n) => '$n unread message${n == 1 ? '' : 's'}';

  // ── Settings ──────────────────────────────────────────────────────────────────
  String get settingsIdentity => 'Identity';
  String get settingsPrivacySecurity => 'Privacy & Security';
  String get settingsTrustedDevices => 'Trusted devices';
  String get settingsThemeAppearance => 'Theme & Appearance';
  String get settingsNotifications => 'Notifications';
  String get settingsAdvanced => 'Advanced';
  String get settingsDanger => 'Danger Zone';
  String get settingsDisplayName => 'Display name';
  String get settingsChangeCode => 'Change secret code';
  String get settingsResetPreferences => 'Reset preferences';
  String get settingsResetHelix => 'Reset Helix';
  String get settingsResetHelixConfirm =>
      'This will delete your identity, trusted devices, and all settings. '
      'You will need to set up Helix again.';
  String get settingsVersion => 'Version';
  String get settingsDiagnostics => 'Diagnostics';
  String get settingsBiometricLock => 'Biometric lock';
  String get settingsDiscoverable => 'Discoverable on network';
  String get settingsScreenshotProtect => 'Screenshot protection';

  // ── QR ───────────────────────────────────────────────────────────────────────
  String get qrShareTitle => 'Share via QR';
  String get qrScanTitle => 'Scan QR code';
  String get qrShareInstruction =>
      'Let a nearby device scan this code to connect directly.';
  String get qrExpired => 'Code expired';
  String get qrGenerateNew => 'Generate new code';
  String get qrScanInstruction => 'Point the camera at a Helix QR code';
  String get qrDesktopNotAvailable =>
      'Camera scanning is not available on desktop.';
  String get qrDesktopAlternative =>
      'Use "Connect by IP" or have a mobile device scan this device\'s QR code instead.';
  String qrExpiresIn(String countdown) => 'Expires in $countdown';

  // ── Call ─────────────────────────────────────────────────────────────────────
  String get callIncoming => 'Incoming call';
  String get callOutgoing => 'Calling…';
  String get callActive => 'Active call';
  String get callEnded => 'Call ended';
  String get callAccept => 'Accept';
  String get callDecline => 'Decline';
  String get callEnd => 'End call';
  String get callMute => 'Mute';
  String get callUnmute => 'Unmute';
  String get callSpeaker => 'Speaker';
  String get callVideo => 'Camera';

  // ── Errors ───────────────────────────────────────────────────────────────────
  String get errNetworkUnavailable =>
      'No local network address found. Connect to Wi-Fi and try again.';
  String get errProfileNotReady =>
      'Profile is not ready yet. Please return to Home and try again.';
  String get errConnectionFailed => 'Connection failed';
  String get errListenerStarting =>
      'The connection listener is still starting. Please try again.';
  String get errQrNotReady => 'QR code is not ready yet. Please try again.';
  String errorWithDetail(String detail) => 'Error: $detail';

  // ── Accessibility semantic labels ─────────────────────────────────────────────
  String get semQrCode => 'QR code for device pairing';
  String get semQrExpired => 'QR code expired. Generate a new code to pair.';
  String get semMessageSent => 'Message sent';
  String get semMessageDelivered => 'Message delivered';
  String get semMessageRead => 'Message read';
  String get semMessageFailed => 'Message failed to send';
  String get semMessageSending => 'Message sending';
  String get semOnline => 'Online';
  String get semOffline => 'Offline';
  String get semPeerConnected => 'Peer connected';
  String get semPeerDisconnected => 'Peer disconnected';
  String get semToggleTorch => 'Toggle torch';
  String get semSwitchCamera => 'Switch camera';
  String get semToggleCodeVisibility => 'Toggle code visibility';
  String get semToggleTheme => 'Toggle dark mode';
  String get semDiscoverabilityOn => 'Discoverable — tap to hide';
  String get semDiscoverabilityOff => 'Hidden — tap to become discoverable';
  String get semCloseSheet => 'Close sheet';
  String get semRefreshPeers => 'Refresh nearby peers';
  String get semPeerAvatar => 'Avatar for peer';
  String get semUnverifiedPeer => 'Unverified peer — tap to verify identity';
  String get semVerifiedPeer => 'Identity verified';
  String get semAttachment => 'Attachment';
  String get semPlayAudio => 'Play audio';
  String get semPauseAudio => 'Pause audio';
  String get semGroupChat => 'Group chat';
  String get semDirectChat => 'Direct message';
  String get semBiometricLock => 'Biometric lock active';
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegate
// ─────────────────────────────────────────────────────────────────────────────

class _HelixLocalizationsDelegate
    extends LocalizationsDelegate<HelixLocalizations> {
  const _HelixLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<HelixLocalizations> load(Locale locale) =>
      SynchronousFuture<HelixLocalizations>(HelixLocalizations(locale));

  @override
  bool shouldReload(_HelixLocalizationsDelegate old) => false;
}
