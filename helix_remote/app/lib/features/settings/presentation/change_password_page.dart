import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Account > Change password (or Set a password).
///
/// The passwords typed here stay on this phone: the app derives keys from them
/// and sends only those, so Helix never learns the password. Changing an
/// existing password needs the current one, which is also how a stranger with
/// an unlocked phone is kept from taking the account.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  var _show = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(accountOverviewProvider);
    final state = ref.watch(changePasswordProvider);
    final hasPassword = overview.value?.hasPassword ?? false;
    final needsPhone =
        hasPassword && !(overview.value?.phoneKnownOnDevice ?? true);

    return Scaffold(
      appBar: AppBar(
        title: Text(hasPassword ? 'Change password' : 'Set a password'),
      ),
      body: overview.isLoading
          ? const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: LinearProgressIndicator(),
            )
          : state.done
          ? ListView(
              children: [
                const InlineNotice(
                  kind: InlineNoticeKind.success,
                  message:
                      'Your password is saved. Use it to sign in on a new '
                      'phone.',
                ),
                BusyFilledButton(label: 'Done', onPressed: () => context.pop()),
              ],
            )
          : ListView(
              children: [
                PageIntro(
                  text: hasPassword
                      ? 'Enter your current password, then choose a new one.'
                      : 'A password lets you sign in on a new phone without '
                            'another device. Choose one you will remember: '
                            'Helix cannot reset it.',
                ),
                if (state.error != null)
                  InlineNotice(
                    kind: InlineNoticeKind.error,
                    message: state.error!,
                  ),
                if (needsPhone)
                  _field(
                    controller: _phone,
                    label: 'Your phone number',
                    helper: 'Needed once to check your current password',
                    keyboard: TextInputType.phone,
                  ),
                if (hasPassword)
                  _field(
                    controller: _current,
                    label: 'Current password',
                    error: state.currentError,
                    obscure: !_show,
                  ),
                _field(
                  controller: _new,
                  label: 'New password',
                  helper: 'At least ${PasswordRules.minLength} characters',
                  error: state.newError,
                  obscure: !_show,
                ),
                _field(
                  controller: _confirm,
                  label: 'Confirm new password',
                  error: state.confirmError,
                  obscure: !_show,
                ),
                CheckboxListTile(
                  value: _show,
                  onChanged: (v) => setState(() => _show = v ?? false),
                  title: const Text('Show passwords'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                BusyFilledButton(
                  label: hasPassword ? 'Change password' : 'Set password',
                  busy: state.busy,
                  onPressed: () => ref
                      .read(changePasswordProvider.notifier)
                      .submit(
                        current: _current.text,
                        next: _new.text,
                        confirm: _confirm.text,
                        hasPassword: hasPassword,
                        phoneNumber: needsPhone ? _phone.text.trim() : null,
                      ),
                ),
              ],
            ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? error,
    bool obscure = false,
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
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: error,
        errorMaxLines: 3,
      ),
    ),
  );
}
