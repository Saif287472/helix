import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/delete_account_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the last step of deleting the account, drawn by `orbit_ui`'s
/// [orbit.DeleteAccountScreen]: type DELETE, then prove it is you, the way
/// the server accepts for this account (the password; else this device's
/// key; else, when the server asks, a code texted to the number). Each
/// refusal is said as a toast.
class DeleteAccountPage extends ConsumerWidget {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountOverviewProvider);
    final state = ref.watch(deleteAccountProvider);
    final controller = ref.read(deleteAccountProvider.notifier);
    ref.listen(deleteAccountProvider, (_, next) {
      final said =
          next.confirmError ??
          next.passwordError ??
          next.numberError ??
          next.codeError ??
          next.error;
      if (said != null) orbit.showOrbitToast(context, said, error: true);
    });
    final value = overview.value;
    if (value == null || state.done) {
      return orbit.OrbitYouPage(
        title: 'Delete account',
        children: [
          if (state.done)
            const orbit.OrbitInlineNotice(
              kind: orbit.OrbitNoticeKind.success,
              text:
                  'Your account was deleted and this phone was wiped. '
                  'Signing you out…',
            )
          else if (overview.hasError)
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
    final phoneKnown = value.phoneKnownOnDevice;
    final proof = hasPassword ? DeleteProof.password : state.proof;

    return orbit.DeleteAccountScreen(
      model: orbit.DeleteAccountModel(
        proof: switch (proof) {
          DeleteProof.password => orbit.DeleteProof.password,
          DeleteProof.code => orbit.DeleteProof.sms,
          DeleteProof.device => orbit.DeleteProof.key,
        },
        needsPhoneNumber:
            state.needsNumber || (proof == DeleteProof.password && !phoneKnown),
        codeSent: state.codeSentTo != null,
        phoneMasked: state.codeSentTo ?? value.phoneMasked ?? '',
        deleting: state.busy,
      ),
      actions: orbit.DeleteAccountActions(
        onSendCode: ({phone}) => controller.sendCode(phoneNumber: phone ?? ''),
        onResendCode: controller.sendCode,
        onDelete: ({phone, secret}) => controller.submit(
          // The screen lets Delete through only once DELETE is typed.
          confirmation: 'DELETE',
          hasPassword: hasPassword,
          phoneKnown: phoneKnown,
          password: proof == DeleteProof.password ? secret ?? '' : '',
          code: proof == DeleteProof.code ? secret ?? '' : '',
          phoneNumber: phone ?? '',
        ),
        onExport: ref.read(accountActionsProvider.notifier).exportData,
        onCancel: () => context.pop(),
      ),
    );
  }
}
