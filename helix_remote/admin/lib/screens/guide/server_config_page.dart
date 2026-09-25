import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GuideServerConfigPage extends StatelessWidget {
  const GuideServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    const jwtCmd = 'openssl rand -hex 32';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚙️ Server Configuration (`docker-compose.yml` & `.env`)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              SizedBox(height: 4),
              Text(
                'Generate secret keys and mount persistent volumes for SQLite and attachments storage.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        const Text('Generate 32-Byte Cryptographic JWT Secret:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: SelectableText(
                  jwtCmd,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: jwtCmd));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JWT secret command copied')));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Grid of Mandatory vs Optional Variables
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _varTile('Mandatory Variables', const Color(0xFF2563EB), 'HELIX_REMOTE_JWT_SECRET\nHELIX_REMOTE_DB_PATH\nHELIX_REMOTE_ATTACHMENTS_DIR\nHELIX_REMOTE_PORT (8080)')),
                  const SizedBox(width: 10),
                  Expanded(child: _varTile('Optional Integrations', const Color(0xFF059669), 'HELIX_REMOTE_TURN_URL & SECRET\nHELIX_REMOTE_FCM_PROJECT_ID\nHELIX_REMOTE_SMS_API_KEY')),
                ],
              );
            }
            return Column(
              children: [
                _varTile('Mandatory Variables', const Color(0xFF2563EB), 'HELIX_REMOTE_JWT_SECRET\nHELIX_REMOTE_DB_PATH\nHELIX_REMOTE_ATTACHMENTS_DIR\nHELIX_REMOTE_PORT (8080)'),
                const SizedBox(height: 10),
                _varTile('Optional Integrations', const Color(0xFF059669), 'HELIX_REMOTE_TURN_URL & SECRET\nHELIX_REMOTE_FCM_PROJECT_ID\nHELIX_REMOTE_SMS_API_KEY'),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _varTile(String title, Color headerColor, String varsText) {
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
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: headerColor)),
          const SizedBox(height: 6),
          SelectableText(
            varsText,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF64748B), height: 1.5),
          ),
        ],
      ),
    );
  }
}
