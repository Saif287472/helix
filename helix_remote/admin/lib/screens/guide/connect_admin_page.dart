import 'package:flutter/material.dart';

class GuideConnectAdminPage extends StatelessWidget {
  const GuideConnectAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔑 Password Initialization & Login',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
              ),
              SizedBox(height: 6),
              Text(
                'Authenticate your Helix Admin console to receive a cryptographically signed session token.',
                style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: _optionCard('Option 1: In-App First Time Wizard', 'Boot container without setting a password. Launch Helix Admin, type your URL, and create your master password in the setup dialog.')),
                  const SizedBox(width: 10),
                  Expanded(child: _optionCard('Option 2: .env Pre-Configuration', 'Define HELIX_REMOTE_ADMIN_PASSWORD=your_password in your environment file before container boot.')),
                ],
              );
            }
            return Column(
              children: [
                _optionCard('Option 1: In-App First Time Wizard', 'Boot container without setting a password. Launch Helix Admin, type your URL, and create your master password in the setup dialog.'),
                const SizedBox(height: 10),
                _optionCard('Option 2: .env Pre-Configuration', 'Define HELIX_REMOTE_ADMIN_PASSWORD=your_password in your environment file before container boot.'),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _optionCard(String title, String description) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4)),
        ],
      ),
    );
  }
}
