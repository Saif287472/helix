import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/password_vault.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Keeps a signed-in account without a password on the "create a password"
/// screen until it has one. Every account needs a password: it is how the
/// account is reached from a new device without an SMS code.
///
/// When the server cannot be asked (offline), the app is let through and the
/// question is asked again on the next launch - a dead network must never
/// lock someone out of messages already on their phone.
class PasswordRequiredGate extends StatefulWidget {
  const PasswordRequiredGate({
    super.key,
    required this.root,
    required this.child,
  });

  final RemoteCompositionRoot root;
  final Widget child;

  @override
  State<PasswordRequiredGate> createState() => _PasswordRequiredGateState();
}

class _PasswordRequiredGateState extends State<PasswordRequiredGate> {
  bool _needsPassword = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final has = await widget.root.accountHasPassword();
    if (!mounted) return;
    setState(() => _needsPassword = has == false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsPassword) return widget.child;
    return SetPasswordScreen(
      root: widget.root,
      mode: SetPasswordMode.create,
      onDone: () => setState(() => _needsPassword = false),
    );
  }
}

enum SetPasswordMode { create, change }

/// Creates the account's first password, or changes it. Changing needs the
/// current password - or, for someone who forgot it, an SMS code to the
/// account's own number. Either way no device is signed out.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({
    super.key,
    required this.root,
    required this.mode,
    this.onDone,
  });

  final RemoteCompositionRoot root;
  final SetPasswordMode mode;
  final VoidCallback? onDone;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _smsCode = TextEditingController();
  bool _busy = false;
  bool _obscured = true;
  String? _error;
  RemoteOtpRequestResult? _otp;

  bool get _isChange => widget.mode == SetPasswordMode.change;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    _smsCode.dispose();
    super.dispose();
  }

  Future<void> _sendSmsCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final otp = await widget.root.requestOtpForOwnNumber();
      if (mounted) setState(() => _otp = otp);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the code. Try again shortly.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final password = _password.text;
    if (PasswordVault.passwordError(password) != null) {
      setState(
        () =>
            _error = 'Use at least ${PasswordVault.minimumLength} characters.',
      );
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    if (_isChange && _otp == null && _current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_otp != null && _smsCode.text.trim().isEmpty) {
      setState(() => _error = 'Enter the code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.root.setAccountPassword(
        newPassword: password,
        currentPassword: _isChange && _otp == null ? _current.text : null,
        otpCode: _otp == null ? null : _smsCode.text.trim(),
        otpChallengeId: _otp?.challengeId,
      );
      if (!mounted) return;
      messenger?.showSnackBar(const SnackBar(content: Text('Password saved.')));
      widget.onDone?.call();
      if (_isChange && navigator.canPop()) navigator.pop(true);
    } on RemoteRestException catch (e) {
      AppLogger.instance.warn(
        'password',
        'save failed: HTTP ${e.statusCode} ${e.serverCode ?? e.failureKind.name}',
      );
      if (!mounted) return;
      setState(
        () => _error = switch (e.serverCode) {
          'password_incorrect' => 'Your current password is not right.',
          'password_locked' =>
            'Too many wrong passwords. Try again later, or reset with an SMS code.',
          'invalid_otp' => 'That SMS code is not right or has expired.',
          _ =>
            'Could not save the password. Check your connection and try again.',
        },
      );
    } catch (e, st) {
      // The type only: a message could echo input, and this screen holds the
      // password.
      AppLogger.instance.warn('password', 'save failed: ${e.runtimeType}', st);
      if (mounted) {
        setState(
          () => _error =
              'Could not save the password. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    List<String> autofill = const [AutofillHints.newPassword],
    bool obscure = true,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HelixSpace.md),
      child: TextField(
        controller: controller,
        obscureText: obscure && _obscured,
        enableSuggestions: !obscure,
        autocorrect: false,
        keyboardType: keyboard,
        autofillHints: autofill,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_isChange ? 'Change password' : 'Create a password'),
        automaticallyImplyLeading: _isChange,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: HelixInsets.all(24),
              children: [
                Text(
                  _isChange
                      ? 'Use your phone number and this password to sign in on any device. Devices already signed in stay signed in.'
                      : 'Your account needs a password. With it you can sign in on this phone or any other device without waiting for an SMS code, and all your devices stay signed in together.',
                  style: muted,
                ),
                const SizedBox(height: HelixSpace.lg),
                AutofillGroup(
                  child: Column(
                    children: [
                      if (_isChange && _otp == null)
                        _field(
                          _current,
                          'Current password',
                          autofill: const [AutofillHints.password],
                        ),
                      if (_otp != null)
                        _field(
                          _smsCode,
                          'SMS code',
                          autofill: const [AutofillHints.oneTimeCode],
                          obscure: false,
                          keyboard: TextInputType.number,
                        ),
                      _field(_password, 'New password'),
                      _field(_confirm, 'Confirm new password'),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: !_obscured,
                  onChanged: (v) => setState(() => _obscured = v != true),
                  title: const Text('Show passwords'),
                ),
                Text(
                  'At least ${PasswordVault.minimumLength} characters. Helix never sees your password; if you forget it you can reset it with an SMS code.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: HelixSpace.md),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: HelixSpace.lg),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save password'),
                  ),
                ),
                if (_isChange && _otp == null) ...[
                  const SizedBox(height: HelixSpace.sm),
                  TextButton(
                    onPressed: _busy ? null : _sendSmsCode,
                    child: const Text('Forgot it? Reset with an SMS code'),
                  ),
                ],
                if (_otp != null) ...[
                  const SizedBox(height: HelixSpace.sm),
                  Text(
                    'We sent a code to your phone number.',
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
