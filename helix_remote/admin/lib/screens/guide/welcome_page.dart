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
      ],
    );
  }
}
