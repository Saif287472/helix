import 'package:flutter/foundation.dart';

/// What an admin has done to this account, as far as the app knows.
enum AccountRestriction {
  /// In good standing.
  none,

  /// Suspended: still signed in and can read and receive, but the server
  /// refuses sending, contact requests, calls, groups and uploads.
  suspended,

  /// Permanently blocked: the account is gone and its number is banned. The
  /// local session has already been purged; the blocked screen stays up until
  /// the user chooses what to do.
  blocked,
}

/// A fact the REST client observed about the account on a response.
enum AccountSignal {
  /// An authenticated request succeeded with no suspension marker, which is
  /// how a lifted suspension is noticed.
  active,

  /// The server tagged the response `X-Helix-Account-Status: suspended`.
  suspended,

  /// The server refused an action with `account_suspended`.
  refusedWhileSuspended,

  /// The server answered `account_blocked` or `phone_blocked`.
  blocked,
}

/// Response header the backend sets for a suspended account.
const kAccountStatusHeader = 'x-helix-account-status';

/// Helix Global's support address, as published in the Terms of Service.
const kHelixSupportEmail = 'support@helix.agiletechbd.com';

/// App-wide restriction state.
///
/// Static because the app shell - which draws the suspension banner and the
/// blocked screen over every route - sits above the bootstrap that owns the
/// composition root. The composition root is the only writer.
abstract final class AccountRestrictionState {
  static final restriction = ValueNotifier<AccountRestriction>(
    AccountRestriction.none,
  );

  /// Bumped every time the server refuses an action because the account is
  /// suspended, so the shell can explain the refusal as it happens.
  static final refusedAttempts = ValueNotifier<int>(0);

  /// Whether the connected server is Helix Global. Decides whether the user
  /// is pointed at Helix support or at their own server's admin - Helix
  /// support cannot act on someone else's self-hosted server.
  static bool serverIsGlobal = true;
}
