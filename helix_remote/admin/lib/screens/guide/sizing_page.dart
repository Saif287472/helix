import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'guide_widgets.dart';

class GuideSizingPage extends StatelessWidget {
  const GuideSizingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('How big a server do you need?'),
        Text(
          'Helix is lightweight - most personal or small-group servers run '
          'comfortably on the smallest tier most providers sell.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        _tierCard(
          context,
          'Small - a handful of people',
          'Messaging only: 1 vCPU, 1GB RAM is plenty.',
          'With voice/video calls: bump to 2GB RAM - calls relay through '
              'TURN, which is more CPU-hungry than messaging.',
        ),
        _tierCard(
          context,
          'Medium - a small community or team',
          'Messaging only: 2 vCPU, 2GB RAM.',
          'With calls: 2 vCPU, 4GB RAM, and consider a dedicated TURN '
              'relay if group calls are common.',
        ),
        _tierCard(
          context,
          'Large - hundreds of active users',
          'Messaging only: 4 vCPU, 4GB+ RAM, and watch SQLite file growth.',
          'With calls: plan for a separate TURN/media relay box - don\'t '
              'run heavy call relay on the same host as the database.',
        ),
      ],
    );
  }

  Widget _tierCard(
    BuildContext context,
    String title,
    String messagingOnly,
    String withCalling,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.sunkenSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '• $messagingOnly',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '• $withCalling',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
