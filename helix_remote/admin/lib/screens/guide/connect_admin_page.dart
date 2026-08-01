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
          title: 'Easiest: get a pairing code (works any time)',
          detail:
              'In Settings, tap "Get a Pairing Code from the Server", then '
              'run the curl command it shows over SSH/Termius on the '
              'server - while it\'s already running, no restart needed. '
              'It prints a 16-digit code, valid for 10 minutes and usable '
              'once; entering it in the app exchanges it for a fresh '
              'admin token automatically.',
        ),
        const GuideDetailExpansion(
          title: 'On first boot: scan the QR code or read ADMIN_TOKEN.txt',
          detail:
              'The server also prints its admin token - and a QR code '
              'encoding it - once, the first time it boots, and saves the '
              'token to ADMIN_TOKEN.txt next to the database. "Scan Token '
              'from Server Terminal" in Settings reads that QR code '
              'directly. Missed both and the server won\'t restart '
              'fresh? Run bin/reset_admin_token.dart on the server (with '
              'the server stopped) to mint a new one - or use the pairing '
              'code above instead, which needs no downtime.',
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
