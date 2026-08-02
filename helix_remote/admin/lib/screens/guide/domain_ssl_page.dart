import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'guide_widgets.dart';

class GuideDomainSslPage extends StatelessWidget {
  const GuideDomainSslPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Domain and SSL'),
        Text(
          'Clients connect over HTTPS, so you\'ll want a domain (or '
          'subdomain) pointed at your server and a TLS certificate. A '
          'reverse proxy in front of the backend handles both cleanly.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'DNS',
          detail:
              'Point an A record (e.g. remote.example.com) at your '
              'server\'s public IP address. Propagation is usually fast '
              '(minutes), sometimes up to a few hours.',
        ),
        const GuideDetailExpansion(
          title: 'Reverse proxy + free certificate',
          detail:
              'Nginx or Caddy in front of the backend, with Let\'s '
              'Encrypt via Certbot (Nginx) or automatically (Caddy), gets '
              'you free, auto-renewing HTTPS. Caddy is the simplest '
              'option if you want to avoid manual certificate renewal '
              'setup.',
        ),
        const AiAssistantTip(
          suggestion:
              'Ask: "Configure Caddy (or Nginx + Certbot) as a reverse '
              'proxy for a backend on port 8080, with a Let\'s Encrypt '
              'certificate for [your domain]."',
        ),
      ],
    );
  }
}
