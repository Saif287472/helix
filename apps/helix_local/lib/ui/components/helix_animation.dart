// lib/ui/components/helix_animation.dart
//
// Reduced-motion-aware animation durations (P9-07).
// When the platform reports disableAnimations = true (user enabled
// "Remove animations" in Android or "Reduce motion" in Windows), every
// HelixAnimation duration collapses to zero so the UI changes instantly
// without vestibular-triggering motion.
//
// Usage:
//   AnimatedContainer(
//     duration: HelixAnimation.fast(context),
//     ...
//   )
import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

abstract final class HelixAnimation {
  static Duration fast(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : HelixTokens.fast;

  static Duration normal(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : HelixTokens.normal;

  static Duration slow(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : HelixTokens.slow;

  static Curve curve(BuildContext context, Curve base) =>
      MediaQuery.disableAnimationsOf(context) ? Curves.linear : base;
}
