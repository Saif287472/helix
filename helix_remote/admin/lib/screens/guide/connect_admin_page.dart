import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'guide_widgets.dart';

class GuideConnectAdminPage extends StatelessWidget {
  const GuideConnectAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Connect Helix Admin'),
        Text(
          'Once the server is up, this app can manage it directly - no '
          'separate install needed on the server side.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        const GuideDetailExpansion(
          title: 'Option 1: In-App First-Time Setup',
          detail:
              'If you start the backend without setting an admin password in '
              '.env, opening this app and connecting to your server URL '
              'will automatically show the "Create First Admin Password" prompt.\n\n'
              'Enter your chosen master password to initialize and secure your '
              'server immediately.',
        ),
        const GuideDetailExpansion(
          title: 'Option 2: Pre-Configuring in .env',
          detail:
              'In your backend .env file, you can set a password before starting:\n\n'
              'HELIX_REMOTE_ADMIN_PASSWORD=your_secure_password\n\n'
              'This acts as your master password to sign in from '
              'the Helix Admin app. It never expires unless you change it in .env.',
        ),
        const SizedBox(height: 12),
        Text(
          'On the sign-in screen, enter your server URL (e.g. '
          'https://helix.yourdomain.com or http://127.0.0.1:8080) and your '
          'Admin Password, then tap Sign In. Once signed in, your session is '
          'saved securely on this device so you stay logged in indefinitely.',
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
