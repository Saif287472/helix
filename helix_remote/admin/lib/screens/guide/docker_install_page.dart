import 'package:flutter/material.dart';
import 'guide_widgets.dart';

class GuideDockerInstallPage extends StatelessWidget {
  const GuideDockerInstallPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Install Docker'),
        const Text(
          'Helix ships as a Docker image, so the fastest path to a '
          'running server is installing Docker Engine and Docker Compose '
          'on your VPS or home machine.',
          style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.6),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'Quick install (Ubuntu/Debian)',
          detail:
              'curl -fsSL https://get.docker.com | sh\n'
              'sudo usermod -aG docker \$USER\n'
              'Log out and back in, then verify with: docker --version',
        ),
        const GuideDetailExpansion(
          title: 'Other operating systems',
          detail:
              'Docker Desktop (macOS/Windows) or your distro\'s package '
              'manager both work. Any recent Docker Engine (24+) with the '
              'Compose plugin is fine - Helix doesn\'t need anything '
              'exotic.',
        ),
        const AiAssistantTip(
          suggestion:
              'Ask: "Install Docker Engine and Docker Compose on '
              '[your OS], then verify it\'s running" and paste any errors '
              'back for troubleshooting.',
        ),
      ],
    );
  }
}
