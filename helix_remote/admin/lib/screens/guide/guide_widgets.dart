import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Consistent page heading used across every wizard page.
class GuidePageTitle extends StatelessWidget {
  const GuidePageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: HelixInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
        ),
      ),
    );
  }
}

/// Tap-to-expand technical detail block. Short main text on the page stays
/// visible by default; this holds the deeper, copy-pasteable detail.
class GuideDetailExpansion extends StatelessWidget {
  const GuideDetailExpansion({
    super.key,
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: HelixInsets.zero,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: context.accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconColor: context.accentColor,
        collapsedIconColor: context.textTertiary,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: HelixInsets.only(bottom: 12),
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small recurring nudge to paste the technical step into an AI assistant
/// for hands-on, machine-specific help. Shown on every technical page.
class AiAssistantTip extends StatelessWidget {
  const AiAssistantTip({super.key, this.suggestion});

  final String? suggestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: HelixInsets.only(top: 16),
      padding: HelixInsets.all(12),
      decoration: BoxDecoration(
        color: context.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: context.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              suggestion ??
                  'Stuck on this step? Paste it into an AI assistant '
                      '(Claude, Gemini, ChatGPT) and ask it to walk you '
                      'through it on your specific machine.',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
