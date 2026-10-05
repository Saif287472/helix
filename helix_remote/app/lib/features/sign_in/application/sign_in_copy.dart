import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show SignInException, SignInFailure;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode, InviteInvalidReason;

/// Every string a sign-in screen can show.
///
/// They live here so the wording cannot drift between the Global path, the
/// personal-server path and the link path, and so a test can assert the exact
/// sentences. **No exception text is ever shown:** an error is turned into one
/// of these, and nothing here can contain a code, a number, a server or a key.
abstract final class SignInCopy {
  // ------------------------------------------------------------ the code page
  static const emptyCode = 'Enter the invite or recovery code you were given.';

  static const notACode =
      'This is not an invite or recovery code. Paste the whole '
      'HLX-INV- or HLX-REC- code you were given.';

  static const truncatedCode =
      'This code is not complete. Copy the whole code again.';

  static const recoveryInvalid =
      'This recovery code is not valid. It may have expired or been used '
      'already - ask your server admin for a new one.';

  static String inviteInvalid(InviteInvalidReason? reason) => switch (reason) {
    InviteInvalidReason.used => 'This invite code has already been used.',
    InviteInvalidReason.cancelled =>
      'This invite code was cancelled by the server admin.',
    InviteInvalidReason.expired => 'This invite code has expired.',
    InviteInvalidReason.notFound ||
    InviteInvalidReason.unknown ||
    null => 'This invite code is not valid.',
  };

  /// A server that is refused outright: not https, or an address that could
  /// pass for another. Never names the address.
  static const insecureServer =
      'This code points to a server that is not reachable securely, so Helix '
      'will not use it. Ask your server admin for a new code.';

  /// The question asked before any request goes to a server that came from a
  /// code or a link. [host] is the address itself, never the name the server
  /// gives itself.
  static String serverQuestion(String host) =>
      'This code wants to sign you in on $host.';

  static const serverExplanation =
      'Only continue if you know this server and expected this code. Your '
      'phone number and messages will be handled by it.';

  // ----------------------------------------------------------- the phone page
  static const badPhoneNumber = 'Enter a valid phone number.';

  static const phoneAlreadyRegistered =
      'This phone number already has an account on this server. Ask your '
      'server admin for a recovery code to sign back in.';

  // ----------------------------------------------------------------- the code
  static const emptyPassword = 'Enter your password.';

  static const requestCodeFirst = 'Request a new code first.';

  static const badOtpFormat = 'Enter the six-digit code from the SMS.';

  static const enterCodeFirst = 'Enter the code sent to your phone first.';

  static const termsNotAccepted =
      'Accept the Terms of Service and Privacy Policy to continue.';

  // ------------------------------------------------------------ shared wording
  static const connectFailed =
      'Could not reach the server. Check your connection and try again.';

  static const wrongCode =
      'That code is not right. Check the SMS and try again.';

  static const passwordNotRight =
      'That password is not right. Try again, or use "Forgot password".';

  static const passwordLocked =
      'Too many wrong passwords. Try again later, or use "Forgot password".';

  static String passwordLockedUntil(DateTime until) {
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');
    return 'Too many wrong passwords. Try again after $hh:$mm, or use '
        '"Forgot password".';
  }

  static const accountBlocked = 'This account has been blocked.';

  static const couldNotSignIn = 'Could not sign in. Please try again.';

  static const couldNotRegister = 'Could not create the account. Try again.';

  // ------------------------------------------------------------- translation

  /// Password sign-in failures, in the order a person is likely to hit them.
  static String passwordRejected(Object error) {
    if (error is SignInException) {
      return switch (error.reason) {
        SignInFailure.untrustedAccountKey =>
          'This password no longer unlocks your account. Use '
              '"Forgot password" to reset it with an SMS code.',
        _ => couldNotSignIn,
      };
    }
    if (error is NetworkException) return connectFailed;
    if (error is ApiException) {
      switch (error.code) {
        case ErrorCode.passwordLocked:
          final until = error.details?['locked_until'];
          final seconds = until is int ? until : null;
          return seconds == null
              ? passwordLocked
              : passwordLockedUntil(
                  DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
                );
        case ErrorCode.invalidCredentials:
          return passwordNotRight;
        case ErrorCode.accountBanned:
        case ErrorCode.phoneBanned:
        case ErrorCode.accountSuspended:
          return accountBlocked;
        case ErrorCode.rateLimited:
          return 'Too many attempts. Wait a moment and try again.';
        default:
          return couldNotSignIn;
      }
    }
    return couldNotSignIn;
  }

  static String wrongOtp(Object error) {
    if (error is NetworkException) return connectFailed;
    if (error is ApiException) {
      switch (error.code) {
        case ErrorCode.invalidCode:
          return wrongCode;
        case ErrorCode.rateLimited:
          return 'Too many attempts. Wait a moment and try again.';
        case ErrorCode.phoneBanned:
        case ErrorCode.accountBanned:
        case ErrorCode.accountSuspended:
          return accountBlocked;
        case ErrorCode.smsUnavailable:
          return 'This server cannot send SMS codes. Ask your server admin for '
              'an invite code.';
        default:
          return couldNotSignIn;
      }
    }
    return couldNotSignIn;
  }

  static String registrationFailed(Object error) {
    if (error is NetworkException) return connectFailed;
    if (error is ApiException) {
      switch (error.code) {
        case ErrorCode.accountBanned:
        case ErrorCode.phoneBanned:
        case ErrorCode.accountSuspended:
          return accountBlocked;
        case ErrorCode.rateLimited:
          return 'Too many attempts. Wait a moment and try again.';
        case ErrorCode.forbidden:
        case ErrorCode.termsNotAccepted:
        case ErrorCode.notAMember:
          return 'This server would not let this device register. Ask your '
              'server admin for a new invite code.';
        default:
          return couldNotRegister;
      }
    }
    return couldNotRegister;
  }

  /// Network and server failures that are not specific to one step.
  static String connectFailure(Object error) {
    if (error is NetworkException) return connectFailed;
    if (error is ApiException) {
      if (error.code == ErrorCode.rateLimited) {
        return 'Too many attempts. Wait a moment and try again.';
      }
      if (error.code == ErrorCode.maintenance) {
        return 'This server is down for maintenance. Try again shortly.';
      }
    }
    return connectFailed;
  }
}
