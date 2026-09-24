import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'guide_widgets.dart';

class GuideWelcomePage extends StatelessWidget {
  const GuideWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Welcome to self-hosting Helix'),
        Text(
          'Helix Remote is designed to be fully self-hostable: you run the '
          'backend, you hold the database, nobody else has access to your '
          'messages. This guide walks through the whole path from '
          '"nothing installed" to "Helix Admin connected to your own '
          'server" - at your own pace, in any order.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Use the progress bar above to jump to any page, or Back/Next to '
          'move step by step. Nothing here is required to use this app - '
          'come back any time from the sidebar.',
          style: TextStyle(
            fontSize: 13,
            color: context.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        // 3 Architecture Feature Cards from demo spec
        _featureCard(
          icon: Icons.shield_outlined,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          iconBorder: const Color(0xFFDBEAFE),
          title: '100% Self-Hosted & Zero-Trust Architecture',
          description:
              'Run entirely on your own infrastructure (VPS or home server). No proprietary telemetry, third-party analytics, or vendor lock-in.',
        ),
        const SizedBox(height: 12),
        _featureCard(
          icon: Icons.save_outlined,
          iconColor: const Color(0xFF059669),
          iconBg: const Color(0xFFECFDF5),
          iconBorder: const Color(0xFFA7F3D0),
          title: 'Full Database Custody',
          description:
              'All user registries, ratchet state, cryptographic identity keys, and encrypted mailboxes reside exclusively in your local SQLite store.',
        ),
        const SizedBox(height: 12),
        _featureCard(
          icon: Icons.bolt_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFFFBEB),
          iconBorder: const Color(0xFFFDE68A),
          title: 'Direct Peer Connection',
          description:
              'Clients communicate with your CipherNode over end-to-end encrypted TLS WebSockets and WebRTC direct media streams.',
        ),
      ],
    );
  }

  Widget _featureCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color iconBorder,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconBorder),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
