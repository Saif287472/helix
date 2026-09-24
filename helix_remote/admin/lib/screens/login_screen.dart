import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Clean, direct login and first-time setup screen for Helix Admin.
/// - If [needsSetup] is true, displays the "Create First Admin Password" form.
/// - If [needsSetup] is false, displays the standard "Sign In" form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.urlController,
    required this.passwordController,
    required this.isConnecting,
    required this.errorMessage,
    required this.onSignIn,
    required this.onOpenGuide,
    this.needsSetup = false,
    this.onSetupPassword,
    this.onCheckUrl,
  });

  final TextEditingController urlController;
  final TextEditingController passwordController;
  final bool isConnecting;
  final String? errorMessage;
  final VoidCallback onSignIn;
  final VoidCallback onOpenGuide;
  final bool needsSetup;
  final void Function(String password)? onSetupPassword;
  final Future<void> Function()? onCheckUrl;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _confirmPasswordController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSetupSubmit() {
    setState(() => _validationError = null);
    final password = widget.passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (password.length < 6) {
      setState(() {
        _validationError = 'Password must be at least 6 characters long.';
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        _validationError = 'Passwords do not match. Please re-enter.';
      });
      return;
    }

    widget.onSetupPassword?.call(password);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveError = _validationError ?? widget.errorMessage;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [HelixColorTokens.cFF0F0F16, HelixColorTokens.cFF1E0B36],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: HelixInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: HelixColorTokens.cFF161624.withValues(alpha: 0.95),
                child: Padding(
                  padding: HelixInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Icon(
                          widget.needsSetup
                              ? Icons.admin_panel_settings_outlined
                              : Icons.radar,
                          size: 56,
                          color: HelixColorTokens.cFF00E5FF,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.needsSetup
                            ? 'CREATE ADMIN PASSWORD'
                            : 'HELIX SERVER ADMIN',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.needsSetup
                            ? 'No admin password configured on this server yet. Create your master password to secure and initialize it.'
                            : 'Enter your backend server address and admin password to sign in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        key: const Key('login_url_field'),
                        controller: widget.urlController,
                        style: const TextStyle(color: Colors.white),
                        onEditingComplete: () {
                          widget.onCheckUrl?.call();
                        },
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          labelStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          hintText: 'https://helix.example.com',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          prefixIcon: const Icon(
                            Icons.dns,
                            color: HelixColorTokens.cFF00E5FF,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: HelixColorTokens.cFF00E5FF,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: Key(
                          widget.needsSetup
                              ? 'setup_password_field'
                              : 'login_password_field',
                        ),
                        controller: widget.passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) {
                          if (widget.isConnecting) return;
                          if (widget.needsSetup) {
                            _handleSetupSubmit();
                          } else {
                            widget.onSignIn();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: widget.needsSetup
                              ? 'New Admin Password'
                              : 'Admin Password / Key',
                          labelStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: HelixColorTokens.cFF00E5FF,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: HelixColorTokens.cFF00E5FF,
                            ),
                          ),
                          helperText: widget.needsSetup
                              ? 'Minimum 6 characters'
                              : 'Configured in .env or during first-time setup',
                          helperStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (widget.needsSetup) ...[
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('setup_confirm_password_field'),
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (_) =>
                              widget.isConnecting ? null : _handleSetupSubmit(),
                          decoration: InputDecoration(
                            labelText: 'Confirm Admin Password',
                            labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: HelixColorTokens.cFF00E5FF,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              tooltip: _obscureConfirmPassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                );
                              },
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: HelixColorTokens.cFF00E5FF,
                              ),
                            ),
                            helperText: 'Re-type password to confirm',
                            helperStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      if (effectiveError != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: HelixInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: HelixColorTokens.cFFFF3366.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: HelixColorTokens.cFFFF3366.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: HelixColorTokens.cFFFF3366,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  effectiveError,
                                  key: const Key('login_error_text'),
                                  style: const TextStyle(
                                    color: HelixColorTokens.cFFFF3366,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: Key(
                          widget.needsSetup
                              ? 'setup_submit_button'
                              : 'login_button',
                        ),
                        onPressed: widget.isConnecting
                            ? null
                            : (widget.needsSetup
                                ? _handleSetupSubmit
                                : widget.onSignIn),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.needsSetup
                              ? const Color(0xFF00B4D8)
                              : HelixColorTokens.cFF8A2BE2,
                          foregroundColor: Colors.white,
                          padding: HelixInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 4,
                        ),
                        child: widget.isConnecting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.needsSetup
                                    ? 'SET PASSWORD & SIGN IN'
                                    : 'SIGN IN',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        key: const Key('login_guide_button'),
                        onPressed: widget.onOpenGuide,
                        icon: const Icon(
                          Icons.menu_book,
                          size: 16,
                          color: HelixColorTokens.cFF00E5FF,
                        ),
                        label: Text(
                          'Self-Hosting Setup Guide',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
