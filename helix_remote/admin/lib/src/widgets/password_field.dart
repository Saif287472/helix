import 'package:flutter/material.dart';

/// A password text field with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: !_visible,
    enabled: widget.enabled,
    autofocus: widget.autofocus,
    autocorrect: false,
    enableSuggestions: false,
    // The operator's own password manager may fill it; the console never
    // stores it.
    keyboardType: TextInputType.visiblePassword,
    textInputAction: widget.textInputAction,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: _visible ? 'Hide password' : 'Show password',
        icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _visible = !_visible),
      ),
    ),
  );
}
