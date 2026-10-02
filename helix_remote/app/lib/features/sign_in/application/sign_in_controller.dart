import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// The Helix Global server. Sign-in opens here and nowhere else unless a
/// code, a link or the hidden corner says otherwise.
final kHelixGlobalServer = Uri.parse('https://helix.agiletechbd.com');

/// Drives sign-in: the page machine, the validation and every call to the
/// engine's [AccountService].
///
/// Nothing here is a widget, and nothing here draws. The screens read
/// [SignInState] and call these methods; the rules (which page follows which,
/// when the Terms are required, what an error says) live in one place so they
/// cannot drift between the Global and the personal-server path.
final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);

final class SignInController extends Notifier<SignInState> {
  String? _challengeId;

  @override
  SignInState build() => const SignInState();

  // ------------------------------------------------------------- entering

  /// Opens the hidden personal-server entry. [code] arrives from a shared
  /// link, in which case it is checked straight away.
  Future<void> openAdvancedMode({String? code}) async {
    state = const SignInState(mode: SignInMode.advanced, page: SignInPage.code);
    if (code != null && code.trim().isNotEmpty) {
      updateCode(code.trim());
      await submitCode();
    }
  }

  /// The hidden corner's fourth tap, and a shared link, both land here.
  void leaveAdvancedMode() {
    _challengeId = null;
    state = const SignInState();
  }

  /// A shared link: opens advanced mode and checks the code at once.
  Future<void> openWithCode(String code) => openAdvancedMode(code: code.trim());

  /// Takes the code a link left in [pendingLinkProvider], if any. Called once
  /// when the screen appears, so a link tapped while the app was closed lands
  /// on the same path as one tapped while it was open.
  Future<void> consumePendingCode() async {
    final code = ref.read(pendingLinkProvider.notifier).take()?.setupCode;
    if (code == null || code.isEmpty) return;
    await openWithCode(code);
  }

  // -------------------------------------------------------------- editing

  void updateDigits(String value) =>
      state = state.copyWith(digits: value, clearError: true);

  void updatePassword(String value) =>
      state = state.copyWith(password: value, clearError: true);

  void updateOtpCode(String value) => state = state.copyWith(
    otpCode: value,
    clearError: true,
    showPhoneRecoveryPrompt: false,
  );

  void updateCode(String value) =>
      state = state.copyWith(codeString: value, clearError: true);

  void updateDisplayName(String value) =>
      state = state.copyWith(displayName: value, clearError: true);

  void updateNewPassword(String value) =>
      state = state.copyWith(newPassword: value, clearError: true);

  void setTosAccepted(bool value) => state = state.copyWith(tosAccepted: value);

  /// The page's back arrow. Global's phone page has none: there is nothing
  /// before it, and a back button there would promise otherwise.
  void goBack() {
    _challengeId = null;
    switch (state.page) {
      case SignInPage.code:
        leaveAdvancedMode();
      case SignInPage.phone:
        if (state.isAdvanced) {
          state = state.copyWith(
            page: SignInPage.code,
            clearCodeType: true,
            clearServerName: true,
            codeString: '',
            clearError: true,
          );
        }
      case SignInPage.password:
        state = state.copyWith(page: SignInPage.name, clearError: true);
      case SignInPage.otp:
      case SignInPage.name:
        state = state.copyWith(page: SignInPage.phone, clearError: true);
    }
  }

  // ----------------------------------------------------------- the code page

  /// Checks an invite or recovery code and, when it is good, points the app at
  /// the server it names.
  Future<bool> submitCode() async {
    final raw = state.codeString.trim();
    if (raw.isEmpty) {
      return _fail(SignInCopy.emptyCode);
    }
    // A prefix with nothing after it is a truncated paste or a half-typed
    // code. It is caught here so the person is told the code is incomplete
    // rather than shown a decoder error they cannot act on.
    if (_isTruncated(raw)) return _fail(SignInCopy.truncatedCode);
    final upper = raw.toUpperCase();
    final isRecovery = upper.startsWith(kHelixRecoveryPrefix);
    final isInvite = upper.startsWith(kHelixInvitePrefix);
    if (!isRecovery && !isInvite) return _fail(SignInCopy.notACode);
    final type = isRecovery
        ? SignInCodeType.recovery
        : SignInCodeType.invitation;

    // The two decoders return differently shaped records, so each branch keeps
    // its own names rather than widening them to a map.
    final invite = isInvite ? decodeHelixInviteCode(raw) : null;
    final recovery = isRecovery ? decodeHelixRecoveryCode(raw) : null;
    final serverUrlText = invite?.serverUrl ?? recovery?.serverUrl;
    if (serverUrlText == null) return _fail(SignInCopy.notACode);

    final serverUrl = Uri.tryParse(serverUrlText);
    if (serverUrl == null || !serverUrl.hasScheme) {
      return _fail(SignInCopy.notACode);
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await _runtimeFor(serverUrl);
      final api = runtime.api.identity;
      // A code is checked before the phone page so a typo, an expired invite
      // or a cancelled one is reported where it was pasted, not two pages
      // later.
      if (isInvite) {
        final result = await api.inviteLookup(invite!.inviteCode);
        if (!result.valid) {
          return _fail(SignInCopy.inviteInvalid(result.reason));
        }
        state = state.copyWith(serverName: result.serverName);
      } else {
        final result = await api.recoveryLookup(recovery!.recoveryCode);
        if (!result.valid) return _fail(SignInCopy.recoveryInvalid);
        state = state.copyWith(serverName: result.serverName);
      }
      state = state.copyWith(
        codeType: type,
        page: SignInPage.phone,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  /// After an invite was entered for a number that already has an account:
  /// the invite cannot be used, and a recovery code is the way back in.
  void beginPhoneRecovery() {
    _challengeId = null;
    state = state.copyWith(
      page: SignInPage.code,
      codeString: '',
      clearCodeType: true,
      clearServerName: true,
      showPhoneRecoveryPrompt: false,
      clearError: true,
    );
  }

  // ----------------------------------------------------------- the phone page

  /// Texts a code to the number and moves to it.
  Future<bool> submitPhone() async {
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      final challenge = await runtime.engine.account.requestPhoneCode(number);
      _challengeId = challenge.challengeId;
      state = state.copyWith(page: SignInPage.otp, isLoading: false);
      return true;
    } on Object catch (error) {
      if (_isAccountExists(error)) {
        return _fail(SignInCopy.phoneAlreadyRegistered, loading: false);
      }
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  /// Checks the SMS code. What happens next depends on what the number turns
  /// out to be: a new account, an existing one with a password, or an
  /// existing one without.
  Future<bool> submitOtp() async {
    final challengeId = _challengeId;
    if (challengeId == null) return _fail(SignInCopy.requestCodeFirst);
    if (!RegExp(r'^\d{6}$').hasMatch(state.otpCode)) {
      return _fail(SignInCopy.badOtpFormat);
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      final verified = await runtime.engine.account.verifyPhone(
        challengeId,
        state.otpCode,
      );
      // The verification token is single-use and short-lived; it is presented
      // by register() below, so it is read from the response and held only
      // until then.
      _verificationToken = verified.verificationToken;
      _verifiedAccountId = verified.accountId;
      state = state.copyWith(
        page: verified.hasPassword ? SignInPage.password : SignInPage.name,
        accountExists: verified.accountExists,
        hasPassword: verified.hasPassword,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.wrongOtp(error), loading: false);
    }
  }

  String? _verificationToken;
  String? _verifiedAccountId;

  /// Asks for the code again.
  Future<bool> resendOtp() async {
    final number = state.e164;
    if (number == null) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      final challenge = await runtime.engine.account.requestPhoneCode(number);
      _challengeId = challenge.challengeId;
      state = state.copyWith(otpCode: '', isLoading: false);
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  // -------------------------------------------------------- the password page

  /// Signs in with the password. The password never leaves the device: the
  /// engine derives the auth key and sends only that.
  Future<bool> signInWithPassword() async {
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);
    if (state.password.isEmpty) return _fail(SignInCopy.emptyPassword);

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      await runtime.engine.account.signInWithPassword(
        phoneNumber: number,
        password: state.password,
      );
      await _rememberServer(runtime.serverUrl);
      state = state.copyWith(
        completed: true,
        isLoading: false,
        // The password is not kept in UI state a moment longer than it is
        // needed.
        password: '',
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.passwordRejected(error), loading: false);
    }
  }

  /// "Forgot password?": the SMS code was already verified, so instead of a
  /// password the account moves to this phone and the other devices are
  /// signed out.
  void forgotPassword() {
    state = state.copyWith(
      page: SignInPage.name,
      password: '',
      clearError: true,
    );
  }

  // ------------------------------------------------------------ the name page

  /// Creates the account, or takes the existing one over with the verified
  /// code. Both end with this device signed in.
  Future<bool> completeSetup({bool skip = false}) async {
    if (state.requiresTerms && !state.tosAccepted) {
      return _fail(SignInCopy.termsNotAccepted);
    }
    final token = _verificationToken;
    if (token == null) {
      state = state.copyWith(page: SignInPage.otp);
      return _fail(SignInCopy.enterCodeFirst);
    }
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      final invite = state.codeType == SignInCodeType.invitation
          ? decodeHelixInviteCode(state.codeString)?.inviteCode
          : null;
      await runtime.engine.account.register(
        verificationToken: token,
        inviteCode: invite,
        password: state.newPassword.isEmpty ? null : state.newPassword,
        accountId: state.accountExists ? _verifiedAccountId : null,
        replaceExisting: state.accountExists,
        phoneNumber: number,
        deviceName: (await ref.read(engineConfigProvider.future)).deviceName,
      );
      final name = skip ? '' : state.displayName.trim();
      if (name.isNotEmpty) {
        // Best effort: a failure here must not undo a registration that
        // already succeeded.
        try {
          await runtime.engine.people.setOwnProfile(name: name);
        } on Object {
          // The profile can be set again from Settings.
        }
      }
      await _rememberServer(runtime.serverUrl);
      state = state.copyWith(
        completed: true,
        isLoading: false,
        newPassword: '',
        otpCode: '',
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.registrationFailed(error), loading: false);
    }
  }

  // -------------------------------------------------------------- internals

  /// The runtime for [serverUrl], switching servers if needed. Changing the
  /// server tears the old runtime down first, so two never hold the database.
  Future<HelixRuntime> _runtimeFor(Uri serverUrl) {
    if (ref.read(serverUrlProvider) != serverUrl) {
      ref.read(serverUrlProvider.notifier).use(serverUrl);
    }
    return ref.read(runtimeProvider.future);
  }

  Future<void> _rememberServer(Uri serverUrl) =>
      ref.read(serverUrlStoreProvider).save(serverUrl.toString());

  /// Puts [message] on the current page and reports false, so every caller
  /// can `return _fail(...)`.
  bool _fail(String message, {bool? loading}) {
    state = state.copyWith(
      errorMessage: message,
      isLoading: loading ?? false,
      showPhoneRecoveryPrompt:
          state.isAdvanced && state.codeType == SignInCodeType.invitation,
    );
    return false;
  }

  bool _isAccountExists(Object error) =>
      error is ApiException && error.code == ErrorCode.accountExists;
}

/// True when [raw] starts with a Helix prefix but carries no payload after it.
///
/// A person who pasted `HLX-REC-` and nothing else needs to be told the code is
/// incomplete; the same goes for one that has a payload but not three parts.
bool _isTruncated(String raw) {
  final upper = raw.toUpperCase();
  final prefix = upper.startsWith(kHelixRecoveryPrefix)
      ? kHelixRecoveryPrefix
      : upper.startsWith(kHelixInvitePrefix)
      ? kHelixInvitePrefix
      : null;
  if (prefix == null) return false;
  final payload = upper.substring(prefix.length);
  if (payload.isEmpty) return true;
  // An invite is one `server|code` pair; a recovery code is three parts. Fewer
  // separators than that means the paste was cut short.
  final parts = payload.split('|');
  final expected = prefix == kHelixRecoveryPrefix ? 3 : 2;
  return parts.length < expected || parts.any((part) => part.isEmpty);
}
