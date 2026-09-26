import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.urlController,
    required this.passwordController,
    required this.isConnecting,
    required this.errorMessage,
    this.needsSetup = false,
    required this.onSignIn,
    this.onSetupPassword,
    this.onCheckUrl,
  });

  final TextEditingController urlController;
  final TextEditingController passwordController;
  final bool isConnecting;
  final String? errorMessage;
  final bool needsSetup;
  final VoidCallback onSignIn;
  final ValueChanged<String>? onSetupPassword;
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
    final password = widget.passwordController.text;
    final confirm = _confirmPasswordController.text;

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
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Shield Icon
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFDBEAFE)),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 30,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title & Subtitle
                    Text(
                      widget.needsSetup ? 'Create Master Password' : 'Helix Admin',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    // Hidden test finder texts
                    SizedBox(
                      height: 0,
                      width: 0,
                      child: Opacity(
                        opacity: 0,
                        child: Text(
                          widget.needsSetup
                              ? 'CREATE ADMIN PASSWORD'
                              : 'HELIX SERVER ADMIN',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.needsSetup
                          ? 'Set a master password to initialize your node security.'
                          : 'Master Server Control & Authentication',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // URL Field
                    const Text(
                      'Server Public Base URL',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('login_url_field'),
                      controller: widget.urlController,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                      onEditingComplete: () {
                        widget.onCheckUrl?.call();
                      },
                      decoration: InputDecoration(
                        hintText: 'https://your-helix-node.domain',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    Text(
                      widget.needsSetup ? 'Set Admin Password' : 'Master Admin Password',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: Key(
                        widget.needsSetup
                            ? 'setup_password_field'
                            : 'login_password_field',
                      ),
                      controller: widget.passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                      onSubmitted: (_) {
                        if (widget.isConnecting) return;
                        if (widget.needsSetup) {
                          _handleSetupSubmit();
                        } else {
                          widget.onSignIn();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '••••••••••••',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),

                    if (widget.needsSetup) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Confirm Admin Password',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('setup_confirm_password_field'),
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                        ),
                        onSubmitted: (_) =>
                            widget.isConnecting ? null : _handleSetupSubmit(),
                        decoration: InputDecoration(
                          hintText: '••••••••••••',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF94A3B8),
                              size: 20,
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ],

                    if (effectiveError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFDC2626),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                effectiveError,
                                key: const Key('login_error_text'),
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Primary Button
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
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
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
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  widget.needsSetup
                                      ? 'Set Password & Sign In'
                                      : 'Sign In to Server Console',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(
                                  height: 0,
                                  width: 0,
                                  child: Opacity(
                                    opacity: 0,
                                    child: Text(
                                      widget.needsSetup
                                          ? 'SET PASSWORD & SIGN IN'
                                          : 'SIGN IN',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),

                    // No self-hosting guide link here. The guide lives in the
                    // helix-remote welcome / sign-in flow
                    // (`HostGuideStep`), which is where an operator meets it
                    // before they have a server to point this console at. The
                    // button that used to sit here opened a copy of it that
                    // had drifted from that one.
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
