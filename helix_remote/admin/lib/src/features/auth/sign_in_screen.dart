import 'package:flutter/material.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
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
    return Theme(
      data: HelixThemes.signIn(),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final theme = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(HelixSpace.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 56,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: HelixSpace.md),
                        Semantics(
                          header: true,
                          child: Text(
                            'Helix Admin',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: HelixSpace.xs),
                        Text(
                          setup == true
                              ? 'First-time setup'
                              : 'Sign in to your Helix server',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: HelixSpace.lg),
                        if (session.notice != null)
                          _Banner(
                            text: session.notice!,
                            background: scheme.secondaryContainer,
                            foreground: scheme.onSecondaryContainer,
                            icon: Icons.info_outline,
                          ),
                        if (session.error != null)
                          _Banner(
                            text: session.error!,
                            background: scheme.errorContainer,
                            foreground: scheme.onErrorContainer,
                            icon: Icons.error_outline,
                            live: true,
                          ),
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
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (setup != null) ...[
                          const SizedBox(height: HelixSpace.md),
                          if (setup) ...[
                            Text(
                              'This server has no admin password yet. Choose '
                              'one with at least '
                              '${AdminPasswordRequest.minLength} characters. '
                              'Whoever reaches a new server first can do '
                              'this step, so do it now.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: HelixSpace.sm),
                          ],
                          PasswordField(
                            controller: _password,
                            label: setup
                                ? 'New admin password'
                                : 'Admin password',
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
                            const SizedBox(height: HelixSpace.sm),
                            PasswordField(
                              controller: _confirm,
                              label: 'Repeat the password',
                              enabled: !session.busy,
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _submit(session),
                            ),
                          ],
                        ],
                        const SizedBox(height: HelixSpace.lg),
                        FilledButton(
                          onPressed: session.busy
                              ? null
                              : () => _submit(session),
                          child: session.busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
    this.live = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;
  final bool live;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HelixSpace.md),
    child: Semantics(
      liveRegion: live,
      child: Container(
        padding: const EdgeInsets.all(HelixSpace.sm),
        decoration: BoxDecoration(
          color: background,
          borderRadius: HelixRadius.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: HelixSpace.xs),
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    ),
  );
}
