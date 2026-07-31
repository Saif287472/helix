import 'package:flutter/material.dart';
import 'guide_widgets.dart';

class GuideConnectAdminPage extends StatelessWidget {
  const GuideConnectAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Connect Helix Admin'),
        const Text(
          'Once the server is up, this app can manage it directly - no '
          'separate install needed on the server side.',
          style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.6),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'Finding your admin token',
          detail:
              'The server prints its admin token once, the first time it '
              'boots, and saves it to ADMIN_TOKEN.txt next to the '
              'database. Lost it? Run bin/reset_admin_token.dart on the '
              'server (with the server stopped) to mint a new one.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Go to Settings in the sidebar, enter your server\'s URL and '
          'admin token, and tap Connect. The token isn\'t saved between '
          'sessions - you\'ll re-enter it each time you reopen this app.',
          style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.5),
        ),
      ],
    );
  }
}
