import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/widgets/onboarding_security_badges.dart';

const _securityClaim = 'Protected by military-grade AES-256 encryption';
const _otpCaution =
    'This verification code is a placeholder, not a secure '
    'delivery channel yet.';

void main() {
  testWidgets('OnboardingSecurityBadge renders its claim with a lock icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OnboardingSecurityBadge())),
    );

    expect(find.text(_securityClaim), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('OtpPlaceholderNotice renders its caution with a warning icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OtpPlaceholderNotice())),
    );

    expect(find.text(_otpCaution), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets(
    'the two claims render with visually and textually distinct styling '
    'when shown together, so they can never be conflated',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [OnboardingSecurityBadge(), OtpPlaceholderNotice()],
            ),
          ),
        ),
      );

      // Distinct claims, distinct icons.
      expect(find.text(_securityClaim), findsOneWidget);
      expect(find.text(_otpCaution), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      final badgeText = tester.widget<Text>(find.text(_securityClaim));
      final noticeText = tester.widget<Text>(find.text(_otpCaution));

      // The badge is a bold, non-italic reassurance; the notice is an
      // italic caution that isn't bold - the two text treatments must not
      // match each other.
      expect(badgeText.style?.fontWeight, equals(FontWeight.w600));
      expect(badgeText.style?.fontStyle, isNot(equals(FontStyle.italic)));
      expect(noticeText.style?.fontStyle, equals(FontStyle.italic));
      expect(noticeText.style?.fontWeight, isNot(equals(FontWeight.w600)));

      // The notice is boxed with a visible border (a warning card); the
      // badge is a borderless pill - distinct container treatments too.
      final badgeContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(_securityClaim),
              matching: find.byType(Container),
            )
            .first,
      );
      final noticeContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(_otpCaution),
              matching: find.byType(Container),
            )
            .first,
      );
      final badgeDecoration = badgeContainer.decoration as BoxDecoration?;
      final noticeDecoration = noticeContainer.decoration as BoxDecoration?;
      expect(badgeDecoration?.border, isNull);
      expect(noticeDecoration?.border, isNotNull);
    },
  );
}
