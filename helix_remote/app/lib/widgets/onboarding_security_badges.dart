import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';

/// Reassuring onboarding highlight: "Protected by military-grade AES-256
/// encryption". No pre-existing onboarding-highlight component exists
/// elsewhere in the app, so this is a small, deliberately generic badge
/// rather than something folded into an existing widget.
///
/// Styled as a calm, positive highlight - never mix this styling with
/// [OtpPlaceholderNotice] below, which makes an intentionally different
/// (cautionary) claim and must stay visually distinguishable from this one.
class OnboardingSecurityBadge extends StatelessWidget {
  const OnboardingSecurityBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: HelixInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Protected by military-grade AES-256 encryption',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cautionary note shown next to the OTP step: the verification code is a
/// development placeholder (delivered via a local notification, not real
/// SMS/push), not a claim about the transport being secure. Deliberately
/// styled as a warning (amber, outlined, warning icon) so it can never be
/// mistaken for - or visually blend into - [OnboardingSecurityBadge]'s
/// encryption claim above.
class OtpPlaceholderNotice extends StatelessWidget {
  const OtpPlaceholderNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: HelixInsets.all(12),
      decoration: BoxDecoration(
        color: HelixStatusColors.caution.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HelixStatusColors.onCautionContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: HelixStatusColors.onCautionContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This verification code is a placeholder, not a secure '
              'delivery channel yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
