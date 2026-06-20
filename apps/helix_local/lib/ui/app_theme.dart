// lib/ui/app_theme.dart
import 'package:flutter/material.dart';
import 'package:helix_local_domain/domain/models.dart';

class HelixTokens {
  HelixTokens._();

  // ── Spacing (2px base scale) ────────────────────────────────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;

  // ── Border radius ───────────────────────────────────────────────────────────
  static const double radius4 = 4;
  static const double radius6 = 6;
  static const double radius8 = 8;
  static const double radius12 = 12;
  static const double radius16 = 16;
  static const double radius20 = 20;
  static const double radius28 = 28;

  // ── Component sizes ─────────────────────────────────────────────────────────
  static const double touchTarget = 48;
  static const double peerGridMin = 340;
  static const double contentMaxWidth = 1120;
  static const double setupMaxWidth = 560;

  // ── Responsive breakpoints ──────────────────────────────────────────────────
  /// Compact → wide: switch from BottomNavigationBar to NavigationRail.
  static const double breakpointWide = 600;

  /// Wide → extra-wide: master-detail pane layout.
  static const double breakpointExtraWide = 1024;

  // ── Icon sizes ──────────────────────────────────────────────────────────────
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 40;

  // ── Motion ──────────────────────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve easeStandard = Curves.easeInOutCubicEmphasized;
  static const Curve easeEnter = Curves.easeOutCubic;
  static const Curve easeExit = Curves.easeInCubic;

  // ── Semantic colors (theme-independent; do not use for text on colored bg) ──
  static const Color colorSuccess = Color(0xFF2E8B57);
  static const Color colorWarning = Color(0xFF9A6A00);
  static const Color colorError = Color(0xFFD32F2F);
  static const Color colorInfo = Color(0xFF0369A1);
  static const Color colorOffline = Color(0xFF7E8793);

  // ── Shadows ─────────────────────────────────────────────────────────────────
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x16000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  // ── Typography helpers ──────────────────────────────────────────────────────
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
}

enum HelixAccent {
  teal('teal', 'Teal', Color(0xFF0F766E), Color(0xFFD5F3EF)),
  emerald('emerald', 'Emerald', Color(0xFF047857), Color(0xFFD8F3E7)),
  ocean('ocean', 'Ocean Blue', Color(0xFF0369A1), Color(0xFFDCEFFC)),
  indigo('indigo', 'Indigo', Color(0xFF4F46E5), Color(0xFFE5E7FF)),
  violet('violet', 'Violet', Color(0xFF7C3AED), Color(0xFFEEE5FF)),
  rose('rose', 'Rose', Color(0xFFBE185D), Color(0xFFFCE3ED)),
  coral('coral', 'Coral', Color(0xFFD95745), Color(0xFFFBE5E1)),
  cyan('cyan', 'Ocean Cyan', Color(0xFF06B6D4), Color(0xFFCFFAFE));

  const HelixAccent(this.id, this.label, this.seed, this.tint);

  final String id;
  final String label;
  final Color seed;
  final Color tint;

  static HelixAccent fromId(String id) {
    return values.firstWhere(
      (accent) => accent.id == id,
      orElse: () => HelixAccent.teal,
    );
  }
}

class HelixTheme {
  HelixTheme._();

  static ThemeData light({
    String accentColor = 'teal',
    bool highContrast = false,
  }) {
    return _build(
      brightness: Brightness.light,
      accent: HelixAccent.fromId(accentColor),
      highContrast: highContrast,
    );
  }

  static ThemeData dark({
    String accentColor = 'teal',
    bool amoled = false,
    bool highContrast = false,
  }) {
    return _build(
      brightness: Brightness.dark,
      accent: HelixAccent.fromId(accentColor),
      amoled: amoled,
      highContrast: highContrast,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required HelixAccent accent,
    bool amoled = false,
    bool highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
      contrastLevel: highContrast ? 1.0 : 0.0,
    );
    final background = isDark
        ? (amoled ? Colors.black : const Color(0xFF101418))
        : const Color(0xFFF7F9FC);
    final surface = isDark
        ? (amoled ? Colors.black : const Color(0xFF171B20))
        : Colors.white;
    final surfaceHigh = isDark
        ? (amoled ? const Color(0xFF070707) : const Color(0xFF22272E))
        : const Color(0xFFEAF0F6);
    final fixedScheme = scheme.copyWith(
      surface: surface,
      surfaceContainerLowest: background,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
    );

    final base = ThemeData.from(colorScheme: fixedScheme, useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: fixedScheme.onSurface,
      displayColor: fixedScheme.onSurface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: fixedScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isDark ? 0 : 1,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withAlpha(isDark ? 0 : 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
          side: BorderSide(color: fixedScheme.outlineVariant.withAlpha(170)),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: HelixTokens.space12,
          vertical: HelixTokens.space4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(HelixTokens.touchTarget, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: HelixTokens.space20,
            vertical: HelixTokens.space14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HelixTokens.radius8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(HelixTokens.touchTarget, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HelixTokens.radius8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(HelixTokens.touchTarget, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HelixTokens.radius8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
          borderSide: BorderSide(color: fixedScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
          borderSide: BorderSide(color: fixedScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HelixTokens.space16,
          vertical: HelixTokens.space14,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: HelixTokens.space8,
        contentPadding: EdgeInsets.symmetric(
          horizontal: HelixTokens.space16,
          vertical: HelixTokens.space4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HelixTokens.radius8),
        ),
      ),
      dividerTheme: DividerThemeData(color: fixedScheme.outlineVariant),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static Color localBubbleColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color remoteBubbleColor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHigh;

  static Color localBubbleTextColor(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

  static Color remoteBubbleTextColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color statusColor(BuildContext ctx, ThreadStatus s) {
    switch (s) {
      case ThreadStatus.active:
        return connectedColor;
      case ThreadStatus.connecting:
        return pendingColor;
      case ThreadStatus.disconnected:
        return disconnectedColor;
    }
  }

  static Color deliveryColor(BuildContext ctx, MessageDeliveryStatus s) {
    switch (s) {
      case MessageDeliveryStatus.sending:
        return const Color(0xFF7E8793);
      case MessageDeliveryStatus.delivered:
        return connectedColor;
      case MessageDeliveryStatus.read:
        return const Color(0xFF1E88E5);
      case MessageDeliveryStatus.failed:
        return const Color(0xFFD32F2F);
      case MessageDeliveryStatus.disconnected:
        return disconnectedColor;
    }
  }

  static Color get connectedColor => HelixTokens.colorSuccess;
  static Color get pendingColor => HelixTokens.colorWarning;
  static Color get disconnectedColor => HelixTokens.colorOffline;
  static Color get accentColor => HelixAccent.teal.seed;
  static Color get primaryColor => HelixAccent.teal.seed;
}
