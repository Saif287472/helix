import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: set or change the password, drawn by `orbit_ui`'s
/// [orbit.PasswordScreen] (its rules tick as you type).
///
/// The password never leaves this phone: only a key derived from it is sent.
/// Changing it needs the current one, so an unlocked phone is kept from
/// taking the account; a linked device that does not know the account's
/// number is asked for it once.
class ChangePasswordPage extends ConsumerWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountOverviewProvider);
    final state = ref.watch(changePasswordProvider);
    ref.listen(changePasswordProvider.select((s) => s.error), (_, next) {
      if (next != null) orbit.showOrbitToast(context, next, error: true);
    });
    final value = overview.value;
    if (value == null) {
      return orbit.OrbitYouPage(
        title: 'Password',
        children: [
          if (overview.hasError)
            orbit.OrbitLoadFailed(
              title: 'Your account details could not be loaded.',
              onRetry: () => ref.invalidate(accountOverviewProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    final hasPassword = value.hasPassword;

    return orbit.PasswordScreen(
      model: orbit.PasswordModel(
        isSet: !hasPassword,
        stage: state.done
            ? orbit.PasswordStage.done
            : state.busy
            ? orbit.PasswordStage.saving
            : orbit.PasswordStage.editing,
        needsPhoneNumber: hasPassword && !value.phoneKnownOnDevice,
        lastChangedLabel: ref.watch(passwordSubtitleProvider) ?? '',
        currentError: state.currentError,
        showMismatch: true,
      ),
      actions: orbit.PasswordActions(
        onSave: ({phone, current, required password}) => ref
            .read(changePasswordProvider.notifier)
            .submit(
              current: current ?? '',
              next: password,
              confirm: password,
              hasPassword: hasPassword,
              phoneNumber: phone,
            ),
        onDone: () => context.pop(),
      ),
    );
  }
}
