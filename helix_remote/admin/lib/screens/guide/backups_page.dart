import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GuideBackupsPage extends StatelessWidget {
  const GuideBackupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const cronCmd = '0 3 * * * rsync -avz /var/helix/backups/ backup-server:/storage/helix-backups/';
    const updateCmd = 'docker compose pull && docker compose up -d';

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
                '💾 Maintenance, Backups & Container Upgrades',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              SizedBox(height: 4),
              Text(
                'Ensure uninterrupted node uptime with hot SQLite snapshots and automated offsite backups.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        const Text('Nightly Offsite Backup Cron Example:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
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
                  cronCmd,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Cron', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: cronCmd));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cron backup command copied')));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        const Text('Updating Server Container (Zero Data Loss):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
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
                  updateCmd,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Command', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: updateCmd));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Container update command copied')));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
