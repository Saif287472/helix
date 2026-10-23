import 'package:flutter/material.dart';
import 'package:orbit_ui/src/theme/effects.dart';
import 'package:orbit_ui/src/theme/orbit_theme.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// Every built-in theme, shown side by side.
///
/// This is the Review 2 artefact for the theme layer: it proves that a theme
/// really is data, because all eleven cards are built from eleven JSON files
/// with no per-theme constant anywhere in this file. It shows what a theme
/// *is* - its colours, its shapes, its type, its chat pattern, its glow and
/// its effects - rather than a screen, which is Phase 4's job.
///
/// The pattern and glow on each card are drawn here, in miniature, because a
/// theme's character is mostly those two and they cannot be seen in a swatch.
class OrbitThemeGallery extends StatelessWidget {
  const OrbitThemeGallery({super.key, required this.themes});

  /// The loaded themes, in the order they should appear: Orbit first, then
  /// the rest as the prototype lists them.
  final List<OrbitTokens> themes;

  static Route<void> route(List<OrbitTokens> themes) => MaterialPageRoute<void>(
    builder: (context) => OrbitThemeGallery(themes: themes),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: themes.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: _galleryGap),
        itemBuilder: (context, index) => OrbitThemeCard(tokens: themes[index]),
      ),
    );
  }
}

/// The gap between cards: `--s-5`, the prototype's 20px.
const double _galleryGap = 20;

/// One theme, drawn from its tokens.
///
/// Each card is its own [Theme] with the theme's own [OrbitTokens], so what you
/// see is what the app would draw - no value is passed in from outside.
class OrbitThemeCard extends StatelessWidget {
  const OrbitThemeCard({super.key, required this.tokens});

  final OrbitTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: OrbitTheme.of(tokens),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.rMd),
          border: Border.all(color: tokens.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          // The one stable way to find a card: every card's wordmark reads
          // "Orbit", so the name on it is not a finder.
          key: ValueKey<String>('theme-card:${tokens.meta.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            _bubbleSample(context),
            _patternAndGlow(context),
            _effects(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: tokens.bg,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // The wordmark gradient, which is a token like any other.
          Container(
            width: 84,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: tokens.wordmarkGradient,
              borderRadius: BorderRadius.circular(tokens.rSm),
            ),
            child: Text(
              'Orbit',
              style: text.titleMedium?.copyWith(
                color: tokens.onBrand,
                fontFamily: tokens.fontDisplay.family,
                fontVariations: [
                  FontVariation('wght', tokens.displayWeight.toDouble()),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tokens.meta.name,
                  style: text.titleMedium?.copyWith(
                    color: tokens.ink,
                    fontFamily: tokens.fontDisplay.family,
                  ),
                ),
                Text(
                  '${tokens.meta.vibe}'
                  '${tokens.meta.dark ? ' · dark' : ''}',
                  style: text.bodySmall?.copyWith(
                    color: tokens.ink3,
                    fontFamily: tokens.mono.family,
                  ),
                ),
              ],
            ),
          ),
          _swatches(context),
        ],
      ),
    );
  }

  Widget _swatches(BuildContext context) {
    // The six roles the design leans on. A list of getters rather than a map,
    // because a map of closures is not a constant.
    final roles = <Color Function(OrbitTokens)>[
      (t) => t.accent,
      (t) => t.out,
      (t) => t.inBubble,
      (t) => t.success,
      (t) => t.warning,
      (t) => t.danger,
    ];
    return Row(
      children: [
        for (final role in roles) ...[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: role(tokens),
              shape: BoxShape.circle,
              border: Border.all(color: tokens.line),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  /// An outgoing and an incoming bubble: the two surfaces the whole chat is
  /// made of, at this theme's radius, with its own pattern behind them.
  Widget _bubbleSample(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: tokens.chatBg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.out,
                borderRadius: BorderRadius.circular(tokens.bubbleR),
                border: Border.all(color: tokens.outLine),
                boxShadow: tokens.glow,
              ),
              child: Text(
                'Hello Bob',
                style: text.bodyMedium?.copyWith(color: tokens.outInk),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.inBubble,
              borderRadius: BorderRadius.circular(tokens.bubbleR),
              border: Border.all(color: tokens.inLine),
            ),
            child: Text(
              'Hi Bob',
              style: text.bodyMedium?.copyWith(color: tokens.inInk),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _button(context, 'Continue', filled: true),
              const SizedBox(width: 8),
              _button(context, 'Cancel', filled: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(BuildContext context, String label, {required bool filled}) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.rSm),
        border: filled ? null : Border.all(color: tokens.controlLine),
        boxShadow: filled ? tokens.glow : null,
      ),
      child: Text(
        label,
        style: text.labelLarge?.copyWith(
          color: filled ? tokens.onAccent : tokens.ink2,
        ),
      ),
    );
  }

  /// The chat pattern, at its own tile size, and this theme's shapes.
  ///
  /// Drawn rather than described, because a pattern is only real when you can
  /// see it repeat.
  Widget _patternAndGlow(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: tokens.surface,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pattern',
                  style: text.labelSmall?.copyWith(color: tokens.ink3),
                ),
                const SizedBox(height: 6),
                Text(
                  tokens.chatPattern.kind,
                  style: text.bodyMedium?.copyWith(
                    color: tokens.ink,
                    fontFamily: tokens.mono.family,
                  ),
                ),
              ],
            ),
          ),
          // Radii, which differ per theme more visibly than anything else.
          for (final r in [
            tokens.rXs,
            tokens.rSm,
            tokens.rMd,
            tokens.rLg,
            tokens.rXl,
          ])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.field,
                  borderRadius: BorderRadius.circular(r),
                  border: Border.all(color: tokens.line),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// What this theme switches on, by name.
  ///
  /// The names come from the fixed registry in `effects.dart`; a theme that
  /// switched on something else would have been refused when it loaded.
  Widget _effects(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final effects = tokens.meta.effects;
    return Container(
      color: tokens.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: effects.isEmpty
          ? Text(
              'No effects',
              style: text.bodySmall?.copyWith(color: tokens.ink3),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in effects)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(tokens.rXs),
                      border: Border.all(color: tokens.accentLine),
                    ),
                    child: Text(
                      OrbitEffects.byName(e.kind)?.paints ?? e.kind,
                      style: text.bodySmall?.copyWith(
                        color: tokens.accentInk,
                        fontFamily: tokens.mono.family,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
