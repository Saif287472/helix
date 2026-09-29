import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One sign-in page, laid out like a web sign-in: the app icon, a title and
/// one line of explanation, the fields, then the actions - the main one on
/// the right. On a wide window the page sits in an outlined box.
class SignInFrame extends StatelessWidget {
  const SignInFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    required this.child,
    this.primaryLabel,
    this.onPrimary,
    this.secondary,
    this.isLoading = false,
    this.errorMessage,
    this.onBack,
    this.footer,
    this.corner,
  });

  final String title;
  final String? subtitle;

  /// Shown under the subtitle, e.g. which personal server this is.
  final Widget? badge;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// A text button on the left of the action row.
  final Widget? secondary;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onBack;

  /// Bottom-left of the screen (legal links).
  final Widget? footer;

  /// Bottom-right of the screen (the hidden advanced-mode corner).
  final Widget? corner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/logo.png',
              width: 56,
              height: 56,
              semanticLabel: 'Helix',
            ),
          ),
        ),
        const SizedBox(height: HelixSpace.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: HelixSpace.xs),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (badge != null) ...[
          const SizedBox(height: HelixSpace.sm),
          Center(child: badge),
        ],
        const SizedBox(height: HelixSpace.xl),
        child,
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: HelixSpace.sm),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: HelixSpace.xs),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: HelixSpace.xl),
        Row(
          children: [
            if (secondary != null) Flexible(child: secondary!),
            const Spacer(),
            if (primaryLabel != null)
              FilledButton(
                onPressed: isLoading ? null : onPrimary,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: isLoading
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurfaceVariant,
                          semanticsLabel: 'Working',
                        ),
                      )
                    : Text(primaryLabel!),
              ),
          ],
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: onBack == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: isLoading ? null : onBack,
                      ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: HelixSpace.lg,
                  vertical: HelixSpace.sm,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: wide
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: scheme.outlineVariant),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(HelixSpace.xl),
                              child: content,
                            ),
                          )
                        : content,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: HelixSpace.xs),
                  ?footer,
                  const Spacer(),
                  ?corner,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hidden way into advanced mode: three taps in the bottom-right corner
/// (each within [tapWindow] of the last) reveal an "Advanced mode" button in
/// the same spot, and a fourth tap - on that button - opens it. The button
/// hides again when it is not tapped within the same window.
class AdvancedModeCorner extends StatefulWidget {
  const AdvancedModeCorner({super.key, required this.onOpen});

  final VoidCallback onOpen;

  static const tapWindow = Duration(seconds: 2);
  static const tapsToReveal = 3;

  @override
  State<AdvancedModeCorner> createState() => _AdvancedModeCornerState();
}

class _AdvancedModeCornerState extends State<AdvancedModeCorner> {
  int _taps = 0;
  bool _revealed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartWindow() {
    _timer?.cancel();
    _timer = Timer(AdvancedModeCorner.tapWindow, () {
      if (!mounted) return;
      setState(() {
        _taps = 0;
        _revealed = false;
      });
    });
  }

  void _onHiddenTap() {
    _taps++;
    if (_taps >= AdvancedModeCorner.tapsToReveal) {
      setState(() => _revealed = true);
    }
    _restartWindow();
  }

  void _open() {
    _timer?.cancel();
    setState(() {
      _taps = 0;
      _revealed = false;
    });
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      height: 56,
      child: _revealed
          ? Center(
              child: TextButton(
                key: const ValueKey('advanced-mode-button'),
                onPressed: _open,
                child: const Text('Advanced mode'),
              ),
            )
          // Deliberately invisible to screen readers too: it is a hidden
          // entrance, not a control.
          : ExcludeSemantics(
              child: GestureDetector(
                key: const ValueKey('advanced-mode-corner'),
                behavior: HitTestBehavior.opaque,
                onTap: _onHiddenTap,
              ),
            ),
    );
  }
}
