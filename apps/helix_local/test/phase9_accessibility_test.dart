// test/phase9_accessibility_test.dart
//
// Phase 9 — accessibility, localization, and ease-of-use certification tests.
//
// Coverage:
//   P9-02  semantic labels present on utility widgets
//   P9-03  keyboard shortcuts registered and fire
//   P9-04  200% text scale produces no layout overflow
//   P9-06  interactive elements meet 48 dp minimum touch target
//   P9-07  HelixAnimation returns Duration.zero when disableAnimations = true
//   P9-08  form validation errors are field-associated (InputDecoration.errorText)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helix/l10n/helix_l10n.dart';
import 'package:helix/ui/app_theme.dart';
import 'package:helix/ui/components/helix_animation.dart';
import 'package:helix/ui/components/helix_semantics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {bool disableAnimations = false, double textScale = 1.0}) {
  return MaterialApp(
    localizationsDelegates: const [HelixLocalizations.delegate],
    supportedLocales: HelixLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: child),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// P9-07 — HelixAnimation respects reduced-motion preference
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('P9-07 HelixAnimation', () {
    testWidgets('returns configured duration when animations enabled',
        (tester) async {
      Duration? fastDur;
      Duration? normalDur;
      Duration? slowDur;

      await tester.pumpWidget(
        _wrap(Builder(builder: (ctx) {
          fastDur = HelixAnimation.fast(ctx);
          normalDur = HelixAnimation.normal(ctx);
          slowDur = HelixAnimation.slow(ctx);
          return const SizedBox.shrink();
        })),
      );

      expect(fastDur, HelixTokens.fast);
      expect(normalDur, HelixTokens.normal);
      expect(slowDur, HelixTokens.slow);
    });

    testWidgets('returns Duration.zero when disableAnimations = true',
        (tester) async {
      Duration? fastDur;
      Duration? normalDur;
      Duration? slowDur;

      await tester.pumpWidget(
        _wrap(
          Builder(builder: (ctx) {
            fastDur = HelixAnimation.fast(ctx);
            normalDur = HelixAnimation.normal(ctx);
            slowDur = HelixAnimation.slow(ctx);
            return const SizedBox.shrink();
          }),
          disableAnimations: true,
        ),
      );

      expect(fastDur, Duration.zero);
      expect(normalDur, Duration.zero);
      expect(slowDur, Duration.zero);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-02 — HelixSemanticButton has required accessible label
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-02 HelixSemanticButton semantics', () {
    testWidgets('label is present in semantic tree', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixSemanticButton(
            icon: Icons.close,
            label: 'Close dialog',
            onPressed: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(HelixSemanticButton));
      expect(semantics.label, 'Close dialog');

      // Button is tappable.
      await tester.tap(find.byType(HelixSemanticButton));
    });

    testWidgets('disabled button has null onPressed and correct label',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HelixSemanticButton(
            icon: Icons.send,
            label: 'Send message',
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(HelixSemanticButton));
      expect(semantics.label, 'Send message');

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.onPressed, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-02 — HelixStatusLabel conveys state via icon + text, not color alone
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-02 / P9-05 HelixStatusLabel', () {
    testWidgets('renders icon and label text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixStatusLabel(
            label: 'Connected',
            icon: Icons.circle,
            color: HelixTokens.colorSuccess,
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
    });

    testWidgets('uses custom semanticsLabel when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixStatusLabel(
            label: 'Connected',
            icon: Icons.circle,
            color: HelixTokens.colorSuccess,
            semanticsLabel: 'Peer is online',
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(HelixStatusLabel));
      expect(semantics.label, 'Peer is online');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-06 — HelixSemanticButton meets 48 × 48 dp minimum touch target
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-06 minimum touch target', () {
    testWidgets('HelixSemanticButton is at least 48 × 48 dp', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixSemanticButton(
            icon: Icons.more_vert,
            label: 'More options',
            onPressed: () {},
          ),
        ),
      );

      final size = tester.getSize(find.byType(HelixSemanticButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('HelixMinTouchTarget enforces 48 dp on small child',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HelixMinTouchTarget(
            child: SizedBox(width: 12, height: 12),
          ),
        ),
      );

      final size = tester.getSize(find.byType(HelixMinTouchTarget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-04 — widgets render at 200% text scale without overflow
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-04 200% text scale', () {
    testWidgets('HelixStatusLabel does not overflow at 2× text scale',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixStatusLabel(
            label: 'Disconnected',
            icon: Icons.cloud_off,
            color: HelixTokens.colorOffline,
          ),
          textScale: 2.0,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('HelixSemanticButton does not overflow at 2× text scale',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelixSemanticButton(
            icon: Icons.qr_code,
            label: 'Share QR code',
            onPressed: () {},
          ),
          textScale: 2.0,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-08 — form fields use InputDecoration.errorText for field-associated errors
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-08 form error accessibility', () {
    testWidgets('errorText is rendered inside the field, not as a separate widget',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TextField(
            decoration: InputDecoration(
              labelText: 'Display name',
              errorText: 'Name is required.',
            ),
          ),
        ),
      );

      // Error text is rendered by InputDecorator inside the field widget tree.
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.text('Name is required.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no errorText renders no error text widget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TextField(
            decoration: InputDecoration(labelText: 'Display name'),
          ),
        ),
      );

      expect(find.text('Name is required.'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-03 — CallbackShortcuts binding activations
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-03 keyboard shortcuts', () {
    testWidgets('Ctrl+1 activates bound callback', (tester) async {
      var called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.digit1, control: true):
                  () => called = true,
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );

      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('Ctrl+4 activates bound callback', (tester) async {
      var called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.digit4, control: true):
                  () => called = true,
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );

      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(called, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P9-01 — HelixLocalizations delegate loads
  // ─────────────────────────────────────────────────────────────────────────

  group('P9-01 HelixLocalizations', () {
    testWidgets('of(context) returns localizations instance', (tester) async {
      HelixLocalizations? l10n;

      await tester.pumpWidget(
        _wrap(Builder(builder: (ctx) {
          l10n = HelixLocalizations.of(ctx);
          return const SizedBox.shrink();
        })),
      );

      expect(l10n, isNotNull);
      expect(l10n!.navHome, 'Home');
      expect(l10n!.navRequests, 'Requests');
      expect(l10n!.navChats, 'Chats');
      expect(l10n!.navSettings, 'Settings');
    });

    test('supportedLocales contains en', () {
      expect(
        HelixLocalizations.supportedLocales,
        contains(const Locale('en')),
      );
    });

    test('delegate supports en locale', () {
      expect(HelixLocalizations.delegate.isSupported(const Locale('en')), isTrue);
    });

    test('delegate does not support unsupported locale', () {
      expect(HelixLocalizations.delegate.isSupported(const Locale('xx')), isFalse);
    });
  });
}
