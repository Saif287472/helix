import 'package:flutter/material.dart';

/// Consistent page heading used across every wizard page.
class GuidePageTitle extends StatelessWidget {
  const GuidePageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00E5FF),
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
        tilePadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF00E5FF),
            fontWeight: FontWeight.w600,
          ),
        ),
        iconColor: const Color(0xFF00E5FF),
        collapsedIconColor: Colors.white54,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                detail,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
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
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.smart_toy_outlined,
            size: 18,
            color: Color(0xFF00E5FF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              suggestion ??
                  'Stuck on this step? Paste it into an AI assistant '
                      '(Claude, Gemini, ChatGPT) and ask it to walk you '
                      'through it on your specific machine.',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
