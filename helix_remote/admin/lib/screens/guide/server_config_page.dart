import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'guide_widgets.dart';

class GuideServerConfigPage extends StatelessWidget {
  const GuideServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Configure the server'),
        Text(
          'The backend reads its settings from environment variables, '
          'usually set in a docker-compose.yml file alongside a '
          'persistent volume for the database and attachments.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'Minimum required settings',
          detail:
              'HELIX_REMOTE_JWT_SECRET - a random 32+ byte secret '
              '(generate with: openssl rand -hex 32)\n'
              'HELIX_REMOTE_DB_PATH - where the SQLite database file lives\n'
              'HELIX_REMOTE_ATTACHMENTS_DIR - where uploaded files are '
              'stored\n'
              'HELIX_REMOTE_PORT / HELIX_REMOTE_HOST - what to bind to '
              '(usually 8080 / 0.0.0.0 inside the container)',
        ),
        const GuideDetailExpansion(
          title: 'Optional settings',
          detail:
              'HELIX_REMOTE_TURN_URL / HELIX_REMOTE_TURN_SECRET for '
              'relay-only call support, HELIX_REMOTE_FCM_PROJECT_ID / '
              'HELIX_REMOTE_FCM_ACCESS_TOKEN for push wakeups. Both are '
              'optional - the server runs fine without them, just with '
              'those features disabled.',
        ),
        const SizedBox(height: 8),
        Text(
          'Mount the database and attachments paths as Docker volumes so '
          'data survives container restarts and image updates.',
          style: TextStyle(
            fontSize: 13,
            color: context.textTertiary,
            height: 1.5,
          ),
        ),
        const AiAssistantTip(
          suggestion:
              'Ask: "Write a docker-compose.yml for the Helix Remote '
              'backend with a persistent volume for the database and '
              'attachments, and a generated JWT secret."',
        ),
      ],
    );
  }
}
