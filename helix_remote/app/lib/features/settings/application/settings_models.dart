import 'package:flutter/foundation.dart' show immutable;

/// What the Account page knows about this account.
@immutable
final class AccountOverview {
  const AccountOverview({
    this.phoneMasked,
    this.helixName,
    this.hasPassword = false,
    this.passwordUpdatedAt,
    this.phoneKnownOnDevice = true,
  });

  /// `+88017*****01`. Never the whole number.
  final String? phoneMasked;
  final String? helixName;
  final bool hasPassword;
  final DateTime? passwordUpdatedAt;

  /// This device remembers the account's phone number. A device that was
  /// linked rather than signed in with a password does not, and then checking
  /// the current password needs the number typed once.
  final bool phoneKnownOnDevice;
}

/// The server refused to delete the account on this device's word alone: it
/// wants a code texted to the account's phone number (the account has no
/// password and the server sends texts). Thrown by
/// `SettingsGateway.deleteAccount`; the Delete page then asks for the code.
final class DeletionNeedsCode implements Exception {
  const DeletionNeedsCode();

  @override
  String toString() => 'DeletionNeedsCode';
}

/// The account's phone number is needed and this device does not know it (it
/// was linked, not signed in with a number): ask for it once. Thrown by the
/// gateway before anything is sent.
final class PhoneNumberNeeded implements Exception {
  const PhoneNumberNeeded();

  @override
  String toString() => 'PhoneNumberNeeded';
}

/// A code was texted for confirming the deletion.
@immutable
final class DeletionCodeRequest {
  const DeletionCodeRequest({required this.challengeId, required this.sentTo});

  final String challengeId;

  /// The number it went to, masked (`+88017*****01`).
  final String sentTo;
}

/// Who may see something.
enum AudienceChoice { everyone, contacts, nobody }

@immutable
final class PrivacyPrefs {
  const PrivacyPrefs({
    this.discoverableByPhone = true,
    this.discoverableByName = true,
    this.lastSeen = AudienceChoice.everyone,
    this.online = AudienceChoice.everyone,
    this.groupAdd = AudienceChoice.everyone,
  });

  final bool discoverableByPhone;
  final bool discoverableByName;
  final AudienceChoice lastSeen;
  final AudienceChoice online;
  final AudienceChoice groupAdd;

  PrivacyPrefs copyWith({
    bool? discoverableByPhone,
    bool? discoverableByName,
    AudienceChoice? lastSeen,
    AudienceChoice? online,
    AudienceChoice? groupAdd,
  }) => PrivacyPrefs(
    discoverableByPhone: discoverableByPhone ?? this.discoverableByPhone,
    discoverableByName: discoverableByName ?? this.discoverableByName,
    lastSeen: lastSeen ?? this.lastSeen,
    online: online ?? this.online,
    groupAdd: groupAdd ?? this.groupAdd,
  );

  @override
  bool operator ==(Object other) =>
      other is PrivacyPrefs &&
      other.discoverableByPhone == discoverableByPhone &&
      other.discoverableByName == discoverableByName &&
      other.lastSeen == lastSeen &&
      other.online == online &&
      other.groupAdd == groupAdd;

  @override
  int get hashCode => Object.hash(
    discoverableByPhone,
    discoverableByName,
    lastSeen,
    online,
    groupAdd,
  );
}

@immutable
final class BlockedPerson {
  const BlockedPerson({required this.id, required this.name});

  final String id;

  /// Phone-book name, nickname, number, then `~name` (the naming order).
  final String name;
}

@immutable
final class MutedChat {
  const MutedChat({required this.id, required this.title, this.until});

  final String id;
  final String title;

  /// Null means muted until further notice.
  final DateTime? until;
}

/// What the About and Advanced pages know about the server.
@immutable
final class ServerDetails {
  const ServerDetails({
    required this.name,
    required this.host,
    required this.version,
    required this.openRegistration,
    required this.maxAttachmentBytes,
    required this.termsVersion,
    required this.privacyVersion,
    this.federationDomain,
    this.features = const {},
  });

  final String name;
  final String host;
  final String version;

  /// Whether new accounts can join (phone or invite) rather than closed.
  final bool openRegistration;
  final int maxAttachmentBytes;
  final String termsVersion;
  final String privacyVersion;
  final String? federationDomain;

  /// Feature flags the server allows clients to act on.
  final Map<String, bool> features;

  bool get allowsCrashReports => features['crash_reporting_upload'] ?? false;
}

@immutable
final class LegalText {
  const LegalText({
    required this.termsTitle,
    required this.termsVersion,
    required this.terms,
    required this.privacyTitle,
    required this.privacyVersion,
    required this.privacy,
    this.fromServer = false,
  });

  final String termsTitle;
  final String termsVersion;
  final String terms;
  final String privacyTitle;
  final String privacyVersion;
  final String privacy;

  /// The server supplied these; false means the copy shipped with the app,
  /// shown when the server could not be reached.
  final bool fromServer;
}

/// How much room Helix uses, for the storage page.
@immutable
final class StorageSummary {
  const StorageSummary({this.databaseBytes = 0, this.mediaBytes = 0});

  final int databaseBytes;
  final int mediaBytes;

  int get totalBytes => databaseBytes + mediaBytes;
}

/// The top of the Settings tab.
@immutable
final class SettingsHeader {
  const SettingsHeader({
    this.accountId = '',
    this.name = 'Helix',
    this.about = '',
    this.serverHost = '',
  });

  final String accountId;
  final String name;
  final String about;

  /// The host of the server this device is on.
  final String serverHost;

  @override
  bool operator ==(Object other) =>
      other is SettingsHeader &&
      other.accountId == accountId &&
      other.name == name &&
      other.about == about &&
      other.serverHost == serverHost;

  @override
  int get hashCode => Object.hash(accountId, name, about, serverHost);
}
