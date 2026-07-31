import 'package:flutter/material.dart';
import 'guide_widgets.dart';

class GuideBackupsPage extends StatelessWidget {
  const GuideBackupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Backups and maintenance'),
        const Text(
          'The Maintenance & Backups tab triggers a clean database '
          'snapshot on demand (SQLite "VACUUM INTO"), saved next to the '
          'main database file.',
          style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.6),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'Automating it',
          detail:
              'A cron job that calls the backup endpoint (or copies the '
              'snapshot file to off-server storage) on a schedule is the '
              'usual setup - Helix doesn\'t schedule this for you, it '
              'just gives you a reliable, consistent snapshot on request.',
        ),
        const GuideDetailExpansion(
          title: 'Keeping the server updated',
          detail:
              'Pull the latest image and recreate the container '
              '(docker compose pull && docker compose up -d) '
              'periodically. Your data volume is untouched by image '
              'updates.',
        ),
        const AiAssistantTip(
          suggestion:
              'Ask: "Write a cron job that calls my Helix backup '
              'endpoint nightly and copies the resulting snapshot to '
              '[off-server location]."',
        ),
        const SizedBox(height: 8),
        const Text(
          'That\'s the whole path from nothing to a self-hosted, '
          'connected server. Jump back to any page any time from the '
          'progress bar.',
          style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.5),
        ),
      ],
    );
  }
}
