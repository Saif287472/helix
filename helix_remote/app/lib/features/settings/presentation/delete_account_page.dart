import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/delete_account_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Account > Delete my account (the last step).
///
/// Deleting needs the word DELETE and proof that this is the account's owner,
/// not only a signed-in phone: the password for an account that has one, a code
/// texted to the account's number for one the server can text, and nothing to
/// type for the rest (this phone signs a challenge with its own key). The page
/// asks only for what the account needs and says why when it refuses.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  var _show = false;

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(accountOverviewProvider);
    final state = ref.watch(deleteAccountProvider);
    final controller = ref.read(deleteAccountProvider.notifier);
    final hasPassword = overview.value?.hasPassword ?? false;
    final phoneKnown = overview.value?.phoneKnownOnDevice ?? true;
    final proof = hasPassword ? DeleteProof.password : state.proof;
    final showNumber =
        state.needsNumber || (proof == DeleteProof.password && !phoneKnown);

    return HelixSettingsScaffold(
      title: 'Delete my account',
      body: overview.isLoading
          ? const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: LinearProgressIndicator(),
            )
          : state.done
          ? ListView(
              children: const [
                InlineNotice(
                  kind: InlineNoticeKind.success,
                  message:
                      'Your account was deleted and this phone was wiped. '
                      'Signing you out...',
                ),
              ],
            )
          : ListView(
              children: [
                if (state.busy) const LinearProgressIndicator(),
                const PageIntro(
                  title: 'This cannot be undone',
                  text:
                      'Your account, devices and profile are removed from the '
                      'server for good, and this phone is wiped. People you '
                      'chatted with keep their own copies of the messages.',
                ),
                if (state.error != null)
                  InlineNotice(
                    kind: InlineNoticeKind.error,
                    message: state.error!,
                  ),
                _field(
                  controller: _confirm,
                  label: 'Type DELETE to confirm',
                  error: state.confirmError,
                  capitals: true,
                  enabled: !state.busy,
                ),
                ..._proofFields(
                  proof: proof,
                  state: state,
                  showNumber: showNumber,
                  hasPassword: hasPassword,
                ),
                if (proof == DeleteProof.device)
                  const PageIntro(
                    text:
                        'This phone will prove it is yours with its own key. '
                        'Nothing else to enter.',
                  ),
                BusyFilledButton(
                  label: proof == DeleteProof.code && state.codeSentTo == null
                      ? 'Send me a code'
                      : 'Delete my account',
                  icon: Icons.delete_forever_outlined,
                  busy: state.busy,
                  onPressed: () => _submit(
                    controller,
                    proof: proof,
                    state: state,
                    hasPassword: hasPassword,
                    phoneKnown: phoneKnown,
                  ),
                ),
                BusyFilledButton(
                  label: 'Cancel',
                  tonal: true,
                  onPressed: state.busy ? null : () => context.pop(),
                ),
                const SizedBox(height: HelixSpace.lg),
              ],
            ),
    );
  }

  List<Widget> _proofFields({
    required DeleteProof proof,
    required DeleteAccountState state,
    required bool showNumber,
    required bool hasPassword,
  }) => [
    if (showNumber)
      _field(
        controller: _phone,
        label: 'Your phone number',
        helper: proof == DeleteProof.password
            ? 'Needed once to check your password, with its country code'
            : 'The number of this account, with its country code',
        error: state.numberError,
        keyboard: TextInputType.phone,
        enabled: !state.busy,
      ),
    if (proof == DeleteProof.password) ...[
      _field(
        controller: _password,
        label: 'Your password',
        helper: 'It is checked on this phone; Helix never sees it.',
        error: state.passwordError,
        obscure: !_show,
        enabled: !state.busy,
      ),
      CheckboxListTile(
        value: _show,
        onChanged: (v) => setState(() => _show = v ?? false),
        title: const Text('Show password'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    ],
    if (proof == DeleteProof.code) ...[
      if (state.codeSentTo == null)
        const PageIntro(
          text:
              'Helix will text a code to your phone number to check that it '
              'is you.',
        )
      else ...[
        PageIntro(text: 'We sent a 6-digit code to ${state.codeSentTo}.'),
        _field(
          controller: _code,
          label: 'Code',
          error: state.codeError,
          keyboard: TextInputType.number,
          enabled: !state.busy,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HelixSpace.xs),
            child: TextButton(
              onPressed: state.busy
                  ? null
                  : () => ref
                        .read(deleteAccountProvider.notifier)
                        .sendCode(phoneNumber: _phone.text),
              child: const Text('Send a new code'),
            ),
          ),
        ),
      ],
    ],
  ];

  Future<void> _submit(
    DeleteAccountController controller, {
    required DeleteProof proof,
    required DeleteAccountState state,
    required bool hasPassword,
    required bool phoneKnown,
  }) async {
    FocusScope.of(context).unfocus();
    // The first press of a code flow only asks for the code.
    if (proof == DeleteProof.code && state.codeSentTo == null) {
      if (_confirm.text.trim() != 'DELETE') {
        await controller.submit(
          confirmation: _confirm.text,
          hasPassword: hasPassword,
          phoneKnown: phoneKnown,
        );
        return;
      }
      await controller.sendCode(phoneNumber: _phone.text);
      return;
    }
    await controller.submit(
      confirmation: _confirm.text,
      hasPassword: hasPassword,
      phoneKnown: phoneKnown,
      password: _password.text,
      phoneNumber: _phone.text,
      code: _code.text,
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? error,
    bool obscure = false,
    bool capitals = false,
    bool enabled = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: HelixSpace.md,
      vertical: HelixSpace.xs,
    ),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: capitals
          ? TextCapitalization.characters
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: error,
        errorMaxLines: 3,
      ),
    ),
  );
}
