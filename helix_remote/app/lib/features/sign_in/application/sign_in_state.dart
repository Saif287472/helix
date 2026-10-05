import 'package:flutter/foundation.dart' show immutable;

/// Which entry the person came in by.
///
/// Helix Global is the default and the only one advertised; a personal server
/// is behind the hidden corner or a shared link. See
/// `presentation/widgets/sign_in_frame.dart` for how the corner works.
enum SignInMode { global, advanced }

/// The pages, in the order a Global sign-in walks through them.
enum SignInPage { code, phone, password, otp, name }

/// What an `HLX-…` code turned out to be.
enum SignInCodeType { invitation, recovery }

/// Everything the sign-in screens draw, and nothing they compute.
///
/// No widget reads the engine, a network model or the clock from here: dates,
/// the server name and the error text are all settled by the controller
/// before they arrive, so a page never does work in `build`.
@immutable
final class SignInState {
  const SignInState({
    this.mode = SignInMode.global,
    this.page = SignInPage.phone,
    this.countryCode = defaultCountryCode,
    this.digits = '',
    this.password = '',
    this.otpCode = '',
    this.codeString = '',
    this.displayName = '',
    this.newPassword = '',
    this.tosAccepted = false,
    this.isLoading = false,
    this.errorMessage,
    this.serverName,
    this.serverHost,
    this.pendingServerHost,
    this.codeType,
    this.accountExists = false,
    this.hasPassword = false,
    this.completed = false,
    this.showPhoneRecoveryPrompt = false,
  });

  /// Bangladesh, because that is where Helix Global starts.
  static const defaultCountryCode = '+880';

  static const termsVersion = '2026-09-25';

  final SignInMode mode;
  final SignInPage page;

  /// Dialling code with its `+`, and the national number separately, so the
  /// field can be shown the way it is dialled and sent as E.164.
  final String countryCode;
  final String digits;

  final String password;
  final String otpCode;
  final String codeString;
  final String displayName;

  /// Optional on sign-up: a password lets the account be recovered on a new
  /// device without another device. It never leaves the device.
  final String newPassword;

  final bool tosAccepted;
  final bool isLoading;
  final String? errorMessage;

  /// The personal server's name, from its invite or recovery code.
  final String? serverName;

  /// The address of the personal server this sign-in is on, as the person is
  /// asked to recognise it (host and non-standard port). Shown on every page
  /// while it is not Helix Global: the name above is the server's own claim,
  /// this is where the traffic goes.
  final String? serverHost;

  /// A server named by a code or a link that the person has not yet approved.
  /// Nothing is sent to it until they do.
  final String? pendingServerHost;

  final SignInCodeType? codeType;

  /// Whether the number already has an account here, and whether that account
  /// has a password. Both come from the phone verification, which is why the
  /// code is asked for before the password.
  final bool accountExists;
  final bool hasPassword;

  /// Set once the device is signed in; the shell's redirect takes over.
  final bool completed;

  /// An invite was entered for a number that already has an account. The
  /// invite cannot be used; the way back in is a recovery code.
  final bool showPhoneRecoveryPrompt;

  bool get isAdvanced => mode == SignInMode.advanced;

  bool get isRecovery => isAdvanced && codeType == SignInCodeType.recovery;

  /// A new account is created here; an existing one is taken over with the
  /// SMS code that was just verified.
  bool get isNewAccount => !accountExists;

  /// Only Helix Global asks for the Terms and Privacy Policy. A personal
  /// server has its own operator policies and its own legal documents.
  bool get requiresTerms => !isAdvanced;

  /// The number as it is dialled, for the page subtitle.
  String get phoneLabel =>
      digits.isEmpty ? countryCode : '$countryCode $digits';

  /// E.164, or null when the number is not complete enough to send.
  String? get e164 {
    final national = digits.replaceAll(RegExp(r'\D'), '');
    if (national.isEmpty) return null;
    return '$countryCode$national';
  }

  bool get canGoBack =>
      page != SignInPage.phone || isAdvanced || page == SignInPage.code;

  SignInState copyWith({
    SignInMode? mode,
    SignInPage? page,
    String? countryCode,
    String? digits,
    String? password,
    String? otpCode,
    String? codeString,
    String? displayName,
    String? newPassword,
    bool? tosAccepted,
    bool? isLoading,
    String? errorMessage,
    String? serverName,
    String? serverHost,
    String? pendingServerHost,
    SignInCodeType? codeType,
    bool? accountExists,
    bool? hasPassword,
    bool? completed,
    bool? showPhoneRecoveryPrompt,
    bool clearError = false,
    bool clearCodeType = false,
    bool clearServerName = false,
    bool clearServerHost = false,
    bool clearPendingServer = false,
  }) => SignInState(
    mode: mode ?? this.mode,
    page: page ?? this.page,
    countryCode: countryCode ?? this.countryCode,
    digits: digits ?? this.digits,
    password: password ?? this.password,
    otpCode: otpCode ?? this.otpCode,
    codeString: codeString ?? this.codeString,
    displayName: displayName ?? this.displayName,
    newPassword: newPassword ?? this.newPassword,
    tosAccepted: tosAccepted ?? this.tosAccepted,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    serverName: clearServerName ? null : serverName ?? this.serverName,
    serverHost: clearServerHost ? null : serverHost ?? this.serverHost,
    pendingServerHost: clearPendingServer
        ? null
        : pendingServerHost ?? this.pendingServerHost,
    codeType: clearCodeType ? null : codeType ?? this.codeType,
    accountExists: accountExists ?? this.accountExists,
    hasPassword: hasPassword ?? this.hasPassword,
    completed: completed ?? this.completed,
    showPhoneRecoveryPrompt:
        showPhoneRecoveryPrompt ?? this.showPhoneRecoveryPrompt,
  );

  @override
  bool operator ==(Object other) =>
      other is SignInState &&
      other.mode == mode &&
      other.page == page &&
      other.countryCode == countryCode &&
      other.digits == digits &&
      other.password == password &&
      other.otpCode == otpCode &&
      other.codeString == codeString &&
      other.displayName == displayName &&
      other.newPassword == newPassword &&
      other.tosAccepted == tosAccepted &&
      other.isLoading == isLoading &&
      other.errorMessage == errorMessage &&
      other.serverName == serverName &&
      other.serverHost == serverHost &&
      other.pendingServerHost == pendingServerHost &&
      other.codeType == codeType &&
      other.accountExists == accountExists &&
      other.hasPassword == hasPassword &&
      other.completed == completed &&
      other.showPhoneRecoveryPrompt == showPhoneRecoveryPrompt;

  @override
  int get hashCode => Object.hashAll([
    mode,
    page,
    countryCode,
    digits,
    password,
    otpCode,
    codeString,
    displayName,
    newPassword,
    tosAccepted,
    isLoading,
    errorMessage,
    serverName,
    serverHost,
    pendingServerHost,
    codeType,
    accountExists,
    hasPassword,
    completed,
    showPhoneRecoveryPrompt,
  ]);
}
