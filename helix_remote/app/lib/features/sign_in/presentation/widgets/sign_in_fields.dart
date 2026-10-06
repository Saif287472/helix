import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/legal_documents_sheet.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A text field that owns its controller, so the typed value survives the
/// controller rebuilding the page on every keystroke.
class _OwnedField extends StatefulWidget {
  const _OwnedField({super.key, required this.initial, required this.builder});

  final String initial;
  final Widget Function(TextEditingController controller) builder;

  @override
  State<_OwnedField> createState() => _OwnedFieldState();
}

class _OwnedFieldState extends State<_OwnedField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

/// The national part of a phone number, under a country dialling code.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
  });

  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: TextField(
        key: const ValueKey('phone-field'),
        enabled: enabled,
        autofocus: true,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [
          // Spaces and hyphens are typed but never sent; the controller joins
          // the digits and prefixes the country code.
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Phone number',
          prefixText: '${SignInState.defaultCountryCode} ',
          border: OutlineInputBorder(),
        ),
        onChanged: onChanged,
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

/// The password, with a show/hide toggle. It never round-trips through state
/// other than as the value to sign in with, and is cleared the moment it has
/// been used.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    this.labelText = 'Password',
    this.obscure = true,
  });

  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final String labelText;

  /// False for the optional "choose a password" field on sign-up, where the
  /// point is that it can be read back.
  final bool obscure;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: TextField(
        key: widget.obscure
            ? const ValueKey('password-sign-in-field')
            : const ValueKey('new-password-field'),
        enabled: widget.enabled,
        autofocus: widget.obscure,
        obscureText: _obscured,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _obscured ? 'Show password' : 'Hide password',
            icon: Icon(
              _obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmit(),
      ),
    );
  }
}

/// The six-digit SMS code, filled in by the keyboard's suggestion where the
/// platform offers one, and submitted as soon as the sixth digit lands.
class OtpField extends StatelessWidget {
  const OtpField({
    super.key,
    required this.initial,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
  });

  final String initial;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _OwnedField(
      initial: initial,
      builder: (controller) => TextField(
        key: const ValueKey('otp-field'),
        controller: controller,
        enabled: enabled,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 22, letterSpacing: 8),
        decoration: const InputDecoration(
          labelText: 'Enter code',
          counterText: '',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          onChanged(value);
          if (value.length == 6) onSubmit();
        },
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

/// The advanced page's single field. Whether the code is an invite or a
/// recovery code is worked out from the code itself.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.initial,
    required this.enabled,
    required this.detected,
    required this.onChanged,
    required this.onSubmit,
  });

  final String initial;
  final bool enabled;
  final SignInCodeType? detected;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OwnedField(
          // A code arriving from a link replaces whatever was typed.
          key: ValueKey('code:$initial'),
          initial: initial,
          builder: (controller) => TextField(
            key: const ValueKey('code-field'),
            controller: controller,
            enabled: enabled,
            autofocus: initial.isEmpty,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Invite or recovery code',
              hintText: 'HLX-INV-… or HLX-REC-…',
              border: OutlineInputBorder(),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(height: HelixSpace.xs),
        Text(
          switch (detected) {
            SignInCodeType.recovery =>
              'Recovery code: you will sign back in to your account.',
            SignInCodeType.invitation =>
              'Invite code: you will create an account on that server.',
            null => 'Your server admin gives you this code.',
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The last page: the name for a new account, the optional password that lets
/// it be recovered without another device, and on Helix Global the Terms.
class NameFields extends StatelessWidget {
  const NameFields({
    super.key,
    required this.askName,
    required this.initialName,
    required this.showTerms,
    required this.termsAccepted,
    required this.enabled,
    required this.onNameChanged,
    required this.onTermsChanged,
    required this.onSubmit,
  });

  final bool askName;
  final String initialName;
  final bool showTerms;
  final bool termsAccepted;
  final bool enabled;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (askName)
          _OwnedField(
            initial: initialName,
            builder: (controller) => TextField(
              key: const ValueKey('name-field'),
              controller: controller,
              enabled: enabled,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Your name',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onChanged: onNameChanged,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
        if (askName) const SizedBox(height: HelixSpace.md),
        // Only Helix Global asks. A personal server has its own operator
        // policies and its own legal documents, which its operator publishes.
        if (showTerms) ...[
          CheckboxListTile(
            key: const ValueKey('terms-checkbox'),
            value: termsAccepted,
            onChanged: enabled ? (v) => onTermsChanged(v ?? false) : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I agree to the Helix Terms of Service and Privacy Policy',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showLegalDocumentsSheet(context),
              child: const Text('Read the Terms and Privacy Policy'),
            ),
          ),
        ],
      ],
    );
  }
}
