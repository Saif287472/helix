import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/share_adapter.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/shared/format.dart';

/// What the Account page shows about this account.
final accountOverviewProvider = FutureProvider.autoDispose<AccountOverview>(
  (ref) => ref.watch(settingsGatewayProvider).account(),
);

/// "Never changed" or "Changed 3 days ago", for the password row.
final passwordSubtitleProvider = Provider.autoDispose<String?>((ref) {
  final overview = ref.watch(accountOverviewProvider).value;
  if (overview == null) return null;
  if (!overview.hasPassword) {
    return 'Not set. Add one to sign in on a new phone.';
  }
  final changed = overview.passwordUpdatedAt;
  if (changed == null) return 'Set';
  return 'Changed ${formatAgo(changed, ref.read(clockProvider)()).toLowerCase()}';
});

// -------------------------------------------------------- change password

abstract final class PasswordRules {
  static const minLength = 8;

  static String? newPasswordProblem(String value) {
    if (value.length < minLength) {
      return 'Use at least $minLength characters.';
    }
    return null;
  }
}

class ChangePasswordState {
  const ChangePasswordState({
    this.busy = false,
    this.done = false,
    this.currentError,
    this.newError,
    this.confirmError,
    this.error,
  });

  final bool busy;
  final bool done;

  /// Under the "current password" field: wrong, or locked out.
  final String? currentError;
  final String? newError;
  final String? confirmError;

  /// A failure that is not about one field (offline, rate limited).
  final String? error;
}

final changePasswordProvider =
    NotifierProvider.autoDispose<ChangePasswordController, ChangePasswordState>(
      ChangePasswordController.new,
    );

final class ChangePasswordController extends Notifier<ChangePasswordState> {
  @override
  ChangePasswordState build() => const ChangePasswordState();

  /// Validates, then sets the password. The password is used to derive keys
  /// on this device; only those keys are sent. [current] is empty when the
  /// account has no password yet.
  Future<void> submit({
    required String current,
    required String next,
    required String confirm,
    required bool hasPassword,
    String? phoneNumber,
  }) async {
    if (state.busy) return;
    final newError = PasswordRules.newPasswordProblem(next);
    final confirmError = next == confirm ? null : 'The passwords do not match.';
    final currentError = hasPassword && current.isEmpty
        ? 'Enter your current password.'
        : null;
    if (newError != null || confirmError != null || currentError != null) {
      state = ChangePasswordState(
        newError: newError,
        confirmError: confirmError,
        currentError: currentError,
      );
      return;
    }
    state = const ChangePasswordState(busy: true);
    try {
      await ref
          .read(settingsGatewayProvider)
          .changePassword(
            newPassword: next,
            currentPassword: hasPassword ? current : null,
            phoneNumber: phoneNumber,
          );
      ref.invalidate(accountOverviewProvider);
      state = const ChangePasswordState(done: true);
    } on Object catch (error) {
      final failure = describeFailure(error, now: ref.read(clockProvider)());
      state = switch (failure.kind) {
        FailureKind.rejected => const ChangePasswordState(
          currentError: 'That is not your current password.',
        ),
        FailureKind.locked => ChangePasswordState(
          currentError: failure.message,
        ),
        _ => ChangePasswordState(error: failure.message),
      };
    }
  }
}

// -------------------------------------------------- export, delete, sign out

class AccountActionState {
  const AccountActionState({this.busy = false, this.error, this.notice});

  final bool busy;
  final String? error;
  final String? notice;
}

final accountActionsProvider =
    NotifierProvider.autoDispose<AccountActions, AccountActionState>(
      AccountActions.new,
    );

final class AccountActions extends Notifier<AccountActionState> {
  @override
  AccountActionState build() => const AccountActionState();

  /// Gets everything the server holds about the account and hands it to the
  /// share sheet as a file. The server holds metadata only (it never has
  /// message content), and the file is as sensitive as the account: it goes
  /// wherever the person sends it and nowhere else.
  Future<bool> exportData() async {
    if (state.busy) return false;
    state = const AccountActionState(busy: true);
    try {
      final bytes = await ref.read(settingsGatewayProvider).exportAccount();
      final now = ref.read(clockProvider)();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final shared = await ref
          .read(shareAdapterProvider)
          .shareFile(
            filename: 'helix-account-export-$stamp.json',
            bytes: bytes,
            mimeType: 'application/json',
          );
      state = AccountActionState(
        notice: shared
            ? null
            : 'The export was ready but could not be shared from this '
                  'device.',
      );
      return shared;
    } on Object catch (error) {
      state = AccountActionState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
      return false;
    }
  }

  /// Deletes the account on the server, then signs this device out and wipes
  /// it. [confirmation] must be exactly `DELETE`: the same word the operator's
  /// console asks for, so it cannot be done by a stray tap.
  Future<bool> deleteAccount(String confirmation) async {
    if (state.busy) return false;
    if (confirmation.trim() != 'DELETE') {
      state = const AccountActionState(
        error: 'Type DELETE in capital letters to confirm.',
      );
      return false;
    }
    state = const AccountActionState(busy: true);
    try {
      await ref.read(settingsGatewayProvider).deleteAccount();
    } on Object catch (error) {
      state = AccountActionState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
      return false;
    }
    // The account is gone. Signing out here wipes the phone's copy; if the
    // server says the session is already over, the wipe still happens.
    try {
      await ref.read(signOutProvider)();
    } on Object {
      // Nothing more to do: the router moves to sign-in when the engine
      // reports signed out.
    }
    return true;
  }

  Future<void> signOut() async {
    if (state.busy) return;
    state = const AccountActionState(busy: true);
    try {
      await ref.read(signOutProvider)();
    } on Object catch (error) {
      state = AccountActionState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }
}
