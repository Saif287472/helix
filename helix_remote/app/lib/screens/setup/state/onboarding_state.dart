import 'package:flutter/foundation.dart';
import 'package:helix_remote_domain/models.dart';

/// Which server the sign-in is for. Global is the only thing most people
/// ever see; advanced mode (a personal server, reached through a hidden
/// corner of the sign-in page or an invite link) is for everyone else.
enum SetupMode { global, advanced }

/// The page of the sign-in flow on screen.
///
/// Global: phone → password or SMS code → name (new accounts) / terms.
/// Advanced: code → phone → password or SMS code → name (invites only).
enum SetupPage { code, phone, password, otp, name }

/// What a code typed on the advanced page turned out to be.
enum CodeType { invitation, recovery }

@immutable
class OnboardingState {
  const OnboardingState({
    this.mode = SetupMode.global,
    this.page = SetupPage.phone,
    this.countryCode = '+880',
    this.phoneNumber = '',
    this.password = '',
    this.otpCode = '',
    this.phoneHash = '',
    this.otpChallengeId = '',
    this.displayName = '',
    this.tosAccepted = false,
    this.tosVersion = HelixLegalDocuments.termsVersion,
    this.codeString = '',
    this.codeType,
    this.serverUrl,
    this.serverName,
    this.inviteCode,
    this.accountExists = false,
    this.isLoading = false,
    this.errorMessage,
    this.showPhoneRecoveryPrompt = false,
    this.isComplete = false,
  });

  final SetupMode mode;
  final SetupPage page;
  final String countryCode;
  final String phoneNumber;

  /// Typed on the password page; cleared as soon as it has been used.
  final String password;
  final String otpCode;
  final String phoneHash;
  final String otpChallengeId;
  final String displayName;
  final bool tosAccepted;
  final String tosVersion;

  /// Advanced mode: the invite or recovery code as typed or pasted.
  final String codeString;
  final CodeType? codeType;

  /// Advanced mode: the personal server the code points at, and the name it
  /// reported for itself.
  final String? serverUrl;
  final String? serverName;
  final String? inviteCode;

  /// Whether this phone number already has an account on the server, as far
  /// as the server said before the SMS code. Existing accounts skip the name.
  final bool accountExists;
  final bool isLoading;
  final String? errorMessage;
  final bool showPhoneRecoveryPrompt;
  final bool isComplete;

  bool get isAdvanced => mode == SetupMode.advanced;
  bool get isRecovery => isAdvanced && codeType == CodeType.recovery;

  OnboardingState copyWith({
    SetupMode? mode,
    SetupPage? page,
    String? countryCode,
    String? phoneNumber,
    String? password,
    String? otpCode,
    String? phoneHash,
    String? otpChallengeId,
    String? displayName,
    bool? tosAccepted,
    String? tosVersion,
    String? codeString,
    CodeType? codeType,
    bool clearCodeType = false,
    String? serverUrl,
    String? serverName,
    bool clearServer = false,
    String? inviteCode,
    bool? accountExists,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? showPhoneRecoveryPrompt,
    bool? isComplete,
  }) {
    return OnboardingState(
      mode: mode ?? this.mode,
      page: page ?? this.page,
      countryCode: countryCode ?? this.countryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      password: password ?? this.password,
      otpCode: otpCode ?? this.otpCode,
      phoneHash: phoneHash ?? this.phoneHash,
      otpChallengeId: otpChallengeId ?? this.otpChallengeId,
      displayName: displayName ?? this.displayName,
      tosAccepted: tosAccepted ?? this.tosAccepted,
      tosVersion: tosVersion ?? this.tosVersion,
      codeString: codeString ?? this.codeString,
      codeType: clearCodeType ? null : (codeType ?? this.codeType),
      serverUrl: clearServer ? null : (serverUrl ?? this.serverUrl),
      serverName: clearServer ? null : (serverName ?? this.serverName),
      inviteCode: clearServer ? null : (inviteCode ?? this.inviteCode),
      accountExists: accountExists ?? this.accountExists,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      showPhoneRecoveryPrompt:
          showPhoneRecoveryPrompt ?? this.showPhoneRecoveryPrompt,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
