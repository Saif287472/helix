import 'package:flutter/material.dart';

/// Static Self-Hosting Guide. Deliberately simple for now - Phase 11
/// rewrites this into a navigable wizard under screens/guide/. Must remain
/// reachable with no server connected, so it's never wrapped by a
/// LockedTabPlaceholder guard.
class GuideTab extends StatelessWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF161624),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Self-Hosting Guide',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Helix is designed to be fully self-hostable. Follow these '
                'general steps to deploy your home server:',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              _guideStep(
                '1. Provision VPS Server',
                'Purchase a minimalist Virtual Private Server (VPS) from '
                    'providers like DigitalOcean, Linode, Hetzner, or AWS. '
                    'We recommend at least 1GB RAM and 1 vCPU running '
                    'Ubuntu 22.04 LTS.',
              ),
              _guideStep(
                '2. Install Docker Environment',
                'Install Docker Engine and Docker Compose on the host '
                    'machine to easily pull and run containerized server '
                    'instances.',
              ),
              _guideStep(
                '3. Configure Docker Compose',
                'Create a docker-compose.yml file detailing backend '
                    'services, volume paths, rate limit parameters, and '
                    'environment config variable settings.',
              ),
              _guideStep(
                '4. Leverage External AI Assistants',
                'Use AI models (like Claude, Gemini, or ChatGPT) as '
                    'operations support to write custom bash scripts, '
                    'configure Nginx reverse proxies, establish SSL '
                    'certificates with Let\'s Encrypt, or set up cron jobs '
                    'for automated system-level backups.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
