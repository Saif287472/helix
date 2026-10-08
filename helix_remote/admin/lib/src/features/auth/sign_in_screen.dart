import 'package:flutter/material.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/password_field.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Server address, then either first-run setup (the server has no admin
/// password yet) or sign-in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _url = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    final session = AdminSessionScope.read(context);
    _url.text = session.lastServerUrl;
    if (_url.text.isNotEmpty) {
      // The saved server: ask it straight away whether this is a sign-in or a
      // first-run setup.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) session.checkServer(_url.text);
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(AdminSessionController session) async {
    if (session.busy) return;
    final needsSetup = session.setupRequired;
    if (needsSetup == null) {
      await session.checkServer(_url.text);
      return;
    }
    if (needsSetup) {
      await session.setup(_password.text, _confirm.text);
    } else {
      await session.signIn(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    final setup = session.setupRequired;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ConsoleCard(
                radius: 20,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: HelixConsoleColors.accentSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: HelixConsoleColors.accentContainer,
                          ),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 30,
                          color: HelixConsoleColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      header: true,
                      child: Text(
                        setup == true ? 'Create admin password' : 'Helix Admin',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: HelixConsoleColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      setup == true
                          ? 'First-time setup for this server'
                          : 'Master server control and authentication',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HelixConsoleColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (session.notice != null) ...[
                      ConsoleBanner(
                        message: session.notice!,
                        tone: ConsoleTone.info,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (session.error != null) ...[
                      ConsoleBanner(message: session.error!),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _url,
                      enabled: !session.busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: setup == null
                          ? TextInputAction.go
                          : TextInputAction.next,
                      onChanged: (_) => session.addressEdited(),
                      onSubmitted: (_) {
                        if (setup == null) _submit(session);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Server address',
                        hintText: 'https://helix.example.com',
                      ),
                    ),
                    if (setup != null) ...[
                      const SizedBox(height: 14),
                      if (setup) ...[
                        const Text(
                          'This server has no admin password yet. Choose one '
                          'with at least ${AdminPasswordRequest.minLength} '
                          'characters. Whoever reaches a new server first can '
                          'do this step, so do it now.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: HelixConsoleColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      PasswordField(
                        controller: _password,
                        label: setup ? 'New admin password' : 'Admin password',
                        enabled: !session.busy,
                        autofocus: true,
                        textInputAction: setup
                            ? TextInputAction.next
                            : TextInputAction.go,
                        onSubmitted: (_) {
                          if (!setup) _submit(session);
                        },
                      ),
                      if (setup) ...[
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _confirm,
                          label: 'Repeat the password',
                          enabled: !session.busy,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(session),
                        ),
                      ],
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: session.busy ? null : () => _submit(session),
                      style: ConsoleButtons.filled,
                      child: session.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(switch (setup) {
                              null => 'Continue',
                              true => 'Set password and sign in',
                              false => 'Sign in',
                            }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
