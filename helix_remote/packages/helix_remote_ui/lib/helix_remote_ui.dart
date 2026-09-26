library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

part 'src/components.dart';

abstract final class HelixColorTokens {
  static const brand = Color(0xFF166A64);
  static const brandDark = Color(0xFF0D4D49);
  static const success = Color(0xFF14804A);
  static const warning = Color(0xFFF4A340);
  static const danger = Color(0xFFBA1A1A);
  static const avatarPalette = <Color>[
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFF00BCD4),
    Color(0xFF795548),
  ];

  // Legacy palette aliases retained while Remote and the operator console
  // converge on the semantic theme palette. Keeping every literal here makes
  // colour review centralized rather than scattered across screen code.
  static const cE61C252B = Color(0xE61C252B);
  static const cF7FFFFFF = Color(0xF7FFFFFF);
  static const cFF005C4B = Color(0xFF005C4B);
  static const cFF0077B6 = Color(0xFF0077B6);
  static const cFF00A884 = Color(0xFF00A884);
  static const cFF00E5FF = Color(0xFF00E5FF);
  static const cFF0284C7 = Color(0xFF0284C7);
  static const cFF08080C = Color(0xFF08080C);
  static const cFF0B0B0C = Color(0xFF0B0B0C);
  static const cFF0B0B12 = Color(0xFF0B0B12);
  static const cFF0B1114 = Color(0xFF0B1114);
  static const cFF0B1417 = Color(0xFF0B1417);
  static const cFF0EA5E9 = Color(0xFF0EA5E9);
  static const cFF0F0F16 = Color(0xFF0F0F16);
  static const cFF101418 = Color(0xFF101418);
  static const cFF11A37F = Color(0xFF11A37F);
  static const cFF14B8A6 = Color(0xFF14B8A6);
  static const cFF161624 = Color(0xFF161624);
  static const cFF171719 = Color(0xFF171719);
  static const cFF1A1A2E = Color(0xFF1A1A2E);
  static const cFF1E0B36 = Color(0xFF1E0B36);
  static const cFF1F2C34 = Color(0xFF1F2C34);
  static const cFF25D366 = Color(0xFF25D366);
  static const cFF2A2A2A = Color(0xFF2A2A2A);
  static const cFF2FA84F = Color(0xFF2FA84F);
  static const cFF34B7F1 = Color(0xFF34B7F1);
  static const cFF3A3A46 = Color(0xFF3A3A46);
  static const cFF3B82F6 = Color(0xFF3B82F6);
  static const cFF4F46E5 = Color(0xFF4F46E5);
  static const cFF53BDEB = Color(0xFF53BDEB);
  static const cFF5B6EE1 = Color(0xFF5B6EE1);
  static const cFF64748B = Color(0xFF64748B);
  static const cFF667781 = Color(0xFF667781);
  static const cFF6D6AAE = Color(0xFF6D6AAE);
  static const cFF7C3AED = Color(0xFF7C3AED);
  static const cFF8A2BE2 = Color(0xFF8A2BE2);
  static const cFF98A4AA = Color(0xFF98A4AA);
  static const cFFB8D5C8 = Color(0xFFB8D5C8);
  static const cFFB91C1C = Color(0xFFB91C1C);
  static const cFFC2185B = Color(0xFFC2185B);
  static const cFFD7DEE2 = Color(0xFFD7DEE2);
  static const cFFD7ECFF = Color(0xFFD7ECFF);
  static const cFFD9FFD2 = Color(0xFFD9FFD2);
  static const cFFDC2626 = Color(0xFFDC2626);
  static const cFFDFF6DE = Color(0xFFDFF6DE);
  static const cFFE11D48 = Color(0xFFE11D48);
  static const cFFE91E63 = Color(0xFFE91E63);
  static const cFFEC4899 = Color(0xFFEC4899);
  static const cFFEDE7DE = Color(0xFFEDE7DE);
  static const cFFEDEAF5 = Color(0xFFEDEAF5);
  static const cFFF24E1E = Color(0xFFF24E1E);
  static const cFFF4F5F7 = Color(0xFFF4F5F7);
  static const cFFF5F3FA = Color(0xFFF5F3FA);
  static const cFFF97316 = Color(0xFFF97316);
  static const cFFFF3366 = Color(0xFFFF3366);
  static const cFFFF6B6B = Color(0xFFFF6B6B);
  static const cFFFFC107 = Color(0xFFFFC107);
  static const cFFFFD54F = Color(0xFFFFD54F);
  static const cFFFFE0CC = Color(0xFFFFE0CC);
}

/// The scrim ladder: colours for content drawn over a dark backdrop.
///
/// Used by every surface that dims what is behind it — the in-call screen,
/// the message-action bar, media previews, modal barriers. Deliberately
/// theme-independent: these surfaces are dark in light mode too, because they
/// sit over video or photos and must not tint them.
///
/// The ladder is the load-bearing part. [onBackdrop] is for primary labels,
/// [onBackdropMuted] for supporting text, [onBackdropSubtle] for chrome that
/// must be visible without competing. Contrast against [backdrop] is what
/// makes each rung legal, so add a rung here rather than inventing an opacity
/// at a call site — three screens each picking their own "white-ish" is how
/// the product ended up with three slightly different action bars.
abstract final class HelixScrimColors {
  /// The backdrop itself.
  static const backdrop = Color(0xFF000000);

  /// Primary text and icons on [backdrop].
  static const onBackdrop = Color(0xFFFFFFFF);

  /// Supporting text — call duration, participant status, captions.
  static const onBackdropMuted = Color(0xB3FFFFFF);

  /// De-emphasised content that is still meant to be read.
  static const onBackdropFaint = Color(0x8AFFFFFF);

  /// Dividers, borders, and inactive control outlines.
  static const onBackdropSubtle = Color(0x3DFFFFFF);

  /// Fill behind an idle round control button.
  static const controlSurface = Color(0x1FFFFFFF);

  /// Modal barrier over the app. [barrierSoft] for a transient sheet,
  /// [barrierStrong] where the content behind must not be legible.
  static const barrierSoft = Color(0x61000000);
  static const barrier = Color(0x8A000000);
  static const barrierStrong = Color(0xDD000000);

  /// Depth cues on light surfaces — bubble shadows and pressed states, which
  /// are a translucent black rather than a grey so they compose over whatever
  /// is beneath them.
  static const shadowSoft = Color(0x10000000);
  static const shadow = Color(0x12000000);
  static const shadowStrong = Color(0x1C000000);

  /// Pressed/selected wash on a dark surface.
  static const highlightOnDark = Color(0x10FFFFFF);
}

/// Fixed neutral fills for chrome that must not follow the colour scheme.
///
/// Small on purpose. Anything that *can* come from `Theme.of(context)
/// .colorScheme` should — these are the few places where it cannot, because
/// they sit under media or need to look identical in both themes.
abstract final class HelixNeutralColors {
  /// Chip and pill backgrounds on a light sheet.
  static const subtle = Color(0xFFF5F5F5);

  /// Drag handles and hairline dividers on a light sheet.
  static const divider = Color(0xFFE0E0E0);

  /// Behind a video tile before the first frame arrives. Near-black rather
  /// than black so the tile edge stays visible against the call backdrop.
  static const videoPlaceholder = Color(0xFF212121);
}

/// Call-specific colours that are about meaning rather than depth.
abstract final class HelixCallColors {
  /// Hang up, decline, and the recording indicator.
  static const endCall = Color(0xFFF44336);

  /// Answer, and the connected indicator.
  static const answerCall = Color(0xFF4CAF50);

  /// A control that cannot be actioned yet — distinct from an idle one, so
  /// "not available" never reads as "available but unlit".
  static const controlDisabled = Color(0xFF9E9E9E);

  /// Ring around the participant tile that currently has the floor.
  static const activeSpeaker = Color(0xFF69F0AE);

  /// Participant is muted.
  static const participantMuted = Color(0xFFFF5252);

  /// Participant is sharing their screen.
  static const participantSharing = Color(0xFF448AFF);
}

/// Severity colours for status affordances — message delivery state, group
/// join requests, connection banners.
///
/// Separate from the colour scheme's `error` because the ladder has four
/// rungs, not one. Delivery state is the reason: "queued", "sent" and
/// "delivered" are all [neutral], and letting each tile pick its own grey is
/// what makes a tick row look inconsistent between messages.
///
/// The `*Container` pairs are for filled banners, and are the only place a
/// status colour should appear as a background.
abstract final class HelixStatusColors {
  /// In progress, or complete and unremarkable. The default.
  static const neutral = Color(0xFF9E9E9E);

  /// Succeeded in a way worth confirming: approved, connected, verified.
  static const positive = Color(0xFF4CAF50);

  /// Needs attention but is not a failure: retrying, safety key changed.
  static const caution = Color(0xFFFF9800);
  static const cautionContainer = Color(0xFFFFE0B2);
  static const onCautionContainer = Color(0xFFE65100);

  /// Failed, revoked, or refused.
  static const danger = Color(0xFFF44336);
  static const dangerContainer = Color(0xFFFFCDD2);
  static const onDangerContainer = Color(0xFFD32F2F);

  /// A quoted or highlighted message.
  static const highlight = Color(0xFF2196F3);
}

abstract final class HelixSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Centralized construction for the layout insets used by Helix surfaces.
///
/// Spacing values stay at the call site when a component needs a deliberate
/// asymmetry, but the Flutter primitive itself is kept in this UI package.
abstract final class HelixInsets {
  static const zero = EdgeInsets.zero;
  static const horizontal12Vertical18 = EdgeInsets.symmetric(
    horizontal: HelixSpace.sm,
    vertical: 18,
  );
  static EdgeInsets all(double value) => EdgeInsets.all(value);
  static EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);
  static EdgeInsets fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) => EdgeInsets.fromLTRB(left, top, right, bottom);
}

abstract final class HelixRadius {
  static const small = Radius.circular(8);
  static const medium = Radius.circular(12);
  static const large = Radius.circular(20);
  static const card = BorderRadius.all(medium);
}

abstract final class HelixElevation {
  static const card = 1.0;
  static const floating = 3.0;
  static const modal = 8.0;
}

abstract final class HelixTypography {
  static const display = TextStyle(fontSize: 32, fontWeight: FontWeight.w700);
  static const title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontSize: 16, height: 1.4);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
}

abstract final class HelixBreakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
  static const expanded = 1200.0;
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= compact;
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}

/// Helix's theme.
///
/// Light and colourful only. Dark mode is deferred for this product, so there
/// is no `dark()` or `highContrastDark()`: the app shell pins
/// `ThemeMode.light` and registers no dark theme, which makes a near-black
/// surface unreachable rather than merely unused. Adding one back is a
/// deliberate act, not something a caller can do by name.
abstract final class HelixThemes {
  static ThemeData light() => _theme(Brightness.light, contrast: 0);
  static ThemeData highContrastLight() => _theme(Brightness.light, contrast: 1);

  static ThemeData _theme(Brightness brightness, {double contrast = 0}) {
    assert(
      brightness == Brightness.light,
      'Helix is light-only. Pass Brightness.light.',
    );
    final colors = ColorScheme.fromSeed(
      seedColor: HelixColorTokens.brand,
      brightness: brightness,
      contrastLevel: contrast,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      textTheme: const TextTheme(
        displaySmall: HelixTypography.display,
        titleLarge: HelixTypography.title,
        bodyLarge: HelixTypography.body,
        labelLarge: HelixTypography.label,
      ),
      cardTheme: const CardThemeData(
        elevation: HelixElevation.card,
        shape: RoundedRectangleBorder(borderRadius: HelixRadius.card),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
