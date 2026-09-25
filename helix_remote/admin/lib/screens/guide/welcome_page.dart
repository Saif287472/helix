import 'package:flutter/material.dart';

class GuideWelcomePage extends StatelessWidget {
  const GuideWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Highlight Header Tile
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🛡️ 100% Self-Hosted & Zero-Trust Architecture',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Helix Remote is engineered so that you retain total ownership of your backend infrastructure. No centralized server or third-party relay ever sees your private messages or metadata.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2 Architecture Feature Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: _cardTile('💾', 'Full Database Custody', 'You control the SQLite database file (remote_backend.db) and all voice notes / media stored on disk.')),
                  const SizedBox(width: 10),
                  Expanded(child: _cardTile('⚡', 'Direct Peer Connection', 'Helix Admin communicates directly with your node over HTTPS without requiring external middleware.')),
                ],
              );
            }
            return Column(
              children: [
                _cardTile('💾', 'Full Database Custody', 'You control the SQLite database file (remote_backend.db) and all voice notes / media stored on disk.'),
                const SizedBox(height: 10),
                _cardTile('⚡', 'Direct Peer Connection', 'Helix Admin communicates directly with your node over HTTPS without requiring external middleware.'),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _cardTile(String emoji, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }
}
