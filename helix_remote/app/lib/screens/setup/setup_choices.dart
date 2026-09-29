import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/password_vault.dart';

// What a finished sign-in hands its host when the app has no root for the
// server yet (first launch, or a different server than the saved one). The
// host builds a root for [serverUrl] and completes the sign-in with it.

/// A new account (or, on Global, an existing account without a password)
/// after its SMS code was checked.
class ServerInviteChoice {
  const ServerInviteChoice({
    required this.serverUrl,
    required this.inviteCode,
    this.phoneNumber,
    this.serverName,
    this.displayName,
    this.otpCode,
    this.phoneHash = '',
    this.otpChallengeId = '',
    this.tosAccepted = false,
    this.tosVersion = '',
  });

  final String serverUrl;

  /// Empty on Helix Global, which has no invites.
  final String inviteCode;

  /// The name the server reported for itself, when it has one.
  final String? serverName;

  /// E.164.
  final String? phoneNumber;
  final String? displayName;
  final String? otpCode;
  final String phoneHash;
  final String otpChallengeId;

  /// Whether the user accepted the Global legal documents.
  final bool tosAccepted;
  final String tosVersion;
}

/// A password sign-in: the password was already checked with the server and
/// only the stretched keys - never the password - are handed over.
class ServerPasswordChoice {
  const ServerPasswordChoice({
    required this.serverUrl,
    required this.lookup,
    required this.keys,
  });

  final String serverUrl;
  final RemotePasswordLookup lookup;
  final PasswordKeys keys;
}

/// A recovery-code reset, ready to redeem: the phone number matched the
/// account and its SMS code (when the server sends them) was checked.
class ServerRecoveryChoice {
  const ServerRecoveryChoice({
    required this.serverUrl,
    required this.accountId,
    required this.recoveryCode,
    required this.phoneHash,
    this.phoneNumber,
    this.otpCode,
    this.otpChallengeId,
  });

  final String serverUrl;
  final String accountId;
  final String recoveryCode;
  final String phoneHash;
  final String? phoneNumber;
  final String? otpCode;
  final String? otpChallengeId;
}
