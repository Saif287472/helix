// lib/ui/screens/setup/setup_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/app_router.dart';
import 'package:helix/ui/app_theme.dart';
import 'package:helix/ui/widgets/app_logo.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _confirmController = TextEditingController();

  int _step = 0;
  bool _codeVisible = false;
  bool _confirmVisible = false;
  bool _discoverable = true;
  bool _isSubmitting = false;
  double _deriveProgress = 0;
  Timer? _progressTimer;

  String? _nameError;
  String? _codeError;
  String? _confirmError;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _pageController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _validateName(String value) {
    final profileService = ref.read(profileServiceProvider);
    setState(() => _nameError = profileService.validateDisplayName(value));
  }

  void _validateCode(String value) {
    final profileService = ref.read(profileServiceProvider);
    setState(() {
      _codeError = profileService.validateSecretCode(value);
      if (_confirmController.text.isNotEmpty) {
        _validateConfirm(_confirmController.text);
      }
    });
  }

  void _validateConfirm(String value) {
    setState(() {
      if (value.isEmpty) {
        _confirmError = 'Please confirm your code.';
      } else if (value != _codeController.text) {
        _confirmError = 'Codes do not match.';
      } else {
        _confirmError = null;
      }
    });
  }

  bool get _identityValid {
    final name = _nameController.text.trim();
    return name.isNotEmpty &&
        _nameError == null &&
        ref.read(profileServiceProvider).validateDisplayName(name) == null;
  }

  bool get _securityValid {
    final code = _codeController.text;
    return code.isNotEmpty &&
        code == _confirmController.text &&
        _codeError == null &&
        _confirmError == null;
  }

  void _generatePassphrase() {
    try {
      final phrase = ref
          .read(profileServiceProvider)
          .generateDicewarePassphrase();
      setState(() {
        _codeController.text = phrase;
        _confirmController.text = phrase;
        _codeError = null;
        _confirmError = null;
      });
      _validateCode(phrase);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate passphrase: $e')),
      );
    }
  }

  Future<void> _next() async {
    if (_step == 1) {
      _validateName(_nameController.text.trim());
      if (!_identityValid) return;
    }
    if (_step == 2) {
      await _submit();
      return;
    }
    await _pageController.nextPage(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : HelixTokens.normal,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _submit() async {
    _validateName(_nameController.text.trim());
    _validateCode(_codeController.text);
    _validateConfirm(_confirmController.text);
    if (!_identityValid || !_securityValid) return;

    setState(() {
      _isSubmitting = true;
      _deriveProgress = 0.08;
    });
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _deriveProgress >= 0.92) return;
      setState(() => _deriveProgress += 0.035);
    });

    try {
      final profileService = ref.read(profileServiceProvider);
      await profileService.createProfile(
        _nameController.text.trim(),
        _codeController.text,
        _discoverable
            ? DiscoverabilityState.discoverable
            : DiscoverabilityState.hidden,
      );
      _progressTimer?.cancel();
      if (!mounted) return;
      setState(() => _deriveProgress = 1);
      await _showReadySheet();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    } catch (e) {
      _progressTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _deriveProgress = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Setup failed: $e')));
    }
  }

  Future<void> _showReadySheet() async {
    final name = _nameController.text.trim();
    final code = _discoverable ? 'discoverable' : 'hidden';
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(HelixTokens.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: HelixTokens.space12),
                  Text(
                    "You're ready",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: HelixTokens.space16),
                  QrImageView(
                    data: 'helix:onboard;name=$name;mode=$code',
                    size: 140,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: HelixTokens.space12),
                  Text(
                    'Share your session QR from Home when both devices are on the same local network.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: HelixTokens.space16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Open Helix'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width > 760;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (!reduceMotion) const Positioned.fill(child: _RadioBackdrop()),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: HelixTokens.setupMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide
                        ? HelixTokens.space40
                        : HelixTokens.space20,
                    vertical: HelixTokens.space24,
                  ),
                  child: Column(
                    children: [
                      _StepDots(step: _step),
                      const SizedBox(height: HelixTokens.space20),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (value) =>
                              setState(() => _step = value),
                          children: [
                            _WelcomeStep(theme: theme),
                            _IdentityStep(
                              controller: _nameController,
                              errorText: _nameError,
                              onChanged: _validateName,
                            ),
                            _SecurityStep(
                              codeController: _codeController,
                              confirmController: _confirmController,
                              codeError: _codeError,
                              confirmError: _confirmError,
                              codeVisible: _codeVisible,
                              confirmVisible: _confirmVisible,
                              discoverable: _discoverable,
                              isSubmitting: _isSubmitting,
                              deriveProgress: _deriveProgress,
                              onCodeChanged: _validateCode,
                              onConfirmChanged: _validateConfirm,
                              onGenerate: _generatePassphrase,
                              onToggleCode: () =>
                                  setState(() => _codeVisible = !_codeVisible),
                              onToggleConfirm: () => setState(
                                () => _confirmVisible = !_confirmVisible,
                              ),
                              onDiscoverableChanged: (value) =>
                                  setState(() => _discoverable = value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: HelixTokens.space16),
                      Row(
                        children: [
                          if (_step > 0)
                            OutlinedButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _pageController.previousPage(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : HelixTokens.normal,
                                      curve: Curves.easeOutCubic,
                                    ),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Back'),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _isSubmitting ? null : _next,
                            icon: Icon(
                              _step == 2
                                  ? Icons.lock_outline
                                  : Icons.arrow_forward,
                            ),
                            label: Text(
                              _step == 2 ? 'Create identity' : 'Next',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final selected = index == step;
        return AnimatedContainer(
          duration: HelixTokens.fast,
          margin: const EdgeInsets.symmetric(
            horizontal: HelixTokens.space4,
          ),
          width: selected ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(HelixTokens.radius8),
          ),
        );
      }),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      showLogo: true,
      title: 'Helix',
      subtitle: 'Private local messaging. No cloud, no accounts.',
      child: Column(
        children: [
          _PrincipleTile(
            icon: Icons.router_outlined,
            title: 'Local network only',
            body:
                'Peers are found over LAN discovery, QR, direct IP, or a shared secret sentence.',
          ),
          _PrincipleTile(
            icon: Icons.security_outlined,
            title: 'Your identity stays here',
            body:
                'Keys live on this device. There is no account server to contact.',
          ),
        ],
      ),
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.controller,
    required this.errorText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = controller.text.trim().isEmpty
        ? '?'
        : controller.text.trim().characters.first.toUpperCase();
    return _StepScaffold(
      icon: Icons.person_outline,
      title: 'Identity',
      subtitle: 'Choose how nearby peers will recognize you.',
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: HelixTokens.space20),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'Alex',
              errorText: errorText,
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SecurityStep extends StatelessWidget {
  const _SecurityStep({
    required this.codeController,
    required this.confirmController,
    required this.codeError,
    required this.confirmError,
    required this.codeVisible,
    required this.confirmVisible,
    required this.discoverable,
    required this.isSubmitting,
    required this.deriveProgress,
    required this.onCodeChanged,
    required this.onConfirmChanged,
    required this.onGenerate,
    required this.onToggleCode,
    required this.onToggleConfirm,
    required this.onDiscoverableChanged,
  });

  final TextEditingController codeController;
  final TextEditingController confirmController;
  final String? codeError;
  final String? confirmError;
  final bool codeVisible;
  final bool confirmVisible;
  final bool discoverable;
  final bool isSubmitting;
  final double deriveProgress;
  final ValueChanged<String> onCodeChanged;
  final ValueChanged<String> onConfirmChanged;
  final VoidCallback onGenerate;
  final VoidCallback onToggleCode;
  final VoidCallback onToggleConfirm;
  final ValueChanged<bool> onDiscoverableChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.enhanced_encryption_outlined,
      title: 'Security',
      subtitle:
          'Choose a secret sentence both you and your contact will type to find each other. It does not replace cryptographic identity verification.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate secret sentence'),
          ),
          const SizedBox(height: HelixTokens.space8),
          TextField(
            controller: codeController,
            obscureText: !codeVisible,
            decoration: InputDecoration(
              labelText: 'Secret sentence',
              hintText: 'e.g. blue forest flying high',
              errorText: codeError,
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  codeVisible ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: codeVisible ? 'Hide' : 'Show',
                onPressed: onToggleCode,
              ),
            ),
            onChanged: onCodeChanged,
          ),
          const SizedBox(height: HelixTokens.space12),
          LinearProgressIndicator(value: _strengthValue(codeController.text)),
          const SizedBox(height: HelixTokens.space12),
          TextField(
            controller: confirmController,
            obscureText: !confirmVisible,
            decoration: InputDecoration(
              labelText: 'Confirm sentence',
              errorText: confirmError,
              prefixIcon: const Icon(Icons.check_circle_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  confirmVisible ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: confirmVisible
                    ? 'Hide confirmation'
                    : 'Show confirmation',
                onPressed: onToggleConfirm,
              ),
            ),
            onChanged: onConfirmChanged,
          ),
          const SizedBox(height: HelixTokens.space12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Discoverable after setup'),
            subtitle: const Text(
              'Peers on the same network can see your name.',
            ),
            value: discoverable,
            onChanged: onDiscoverableChanged,
            secondary: Icon(
              discoverable ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            ),
          ),
          if (isSubmitting) ...[
            const SizedBox(height: HelixTokens.space12),
            LinearProgressIndicator(value: deriveProgress),
            const SizedBox(height: HelixTokens.space6),
            Text(
              'Deriving local identity key...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  double _strengthValue(String value) {
    final classes = [
      RegExp('[a-z]').hasMatch(value),
      RegExp('[A-Z]').hasMatch(value),
      RegExp('[0-9]').hasMatch(value),
      RegExp(r'[^A-Za-z0-9]').hasMatch(value),
    ].where((v) => v).length;
    final lengthScore = (value.length / 24).clamp(0.0, 1.0);
    return ((classes / 4) * 0.35 + lengthScore * 0.65).clamp(0.0, 1.0);
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    this.icon,
    this.showLogo = false,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData? icon;
  final bool showLogo;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLogo)
            const Center(child: AppLogo(size: 80))
          else
            Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: HelixTokens.space16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: HelixTokens.space8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: HelixTokens.space32),
          child,
        ],
      ),
    );
  }
}

class _PrincipleTile extends StatelessWidget {
  const _PrincipleTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: HelixTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: HelixTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: HelixTokens.space4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadioBackdrop extends StatefulWidget {
  const _RadioBackdrop();

  @override
  State<_RadioBackdrop> createState() => _RadioBackdropState();
}

class _RadioBackdropState extends State<_RadioBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _RadioPainter(
          progress: _controller.value,
          color: Theme.of(context).colorScheme.primary.withAlpha(34),
        ),
      ),
    );
  }
}

class _RadioPainter extends CustomPainter {
  const _RadioPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final center = Offset(size.width * 0.5, size.height * 0.44);
    final maxRadius = math.max(size.width, size.height) * 0.62;
    for (var i = 0; i < 7; i++) {
      final phase = (progress + i / 7) % 1;
      final radius = 40 + phase * maxRadius;
      paint.color = color.withAlpha(((1 - phase) * 42).clamp(0, 42).round());
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadioPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
