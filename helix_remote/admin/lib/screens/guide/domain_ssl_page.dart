import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GuideDomainSslPage extends StatelessWidget {
  const GuideDomainSslPage({super.key});

  @override
  Widget build(BuildContext context) {
    const caddyCode = 'helix.yourdomain.com {\n    reverse_proxy 127.0.0.1:8080\n}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔒 Domain Setup & Automated SSL Proxy',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              SizedBox(height: 4),
              Text(
                'All Helix clients connect strictly over TLS (HTTPS). Configure automated certificate renewal.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step 1: Point DNS A Record', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              SizedBox(height: 4),
              Text('Create an A record pointing your domain (e.g., helix.yourdomain.com) to your server\'s public IPv4 address.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
        const SizedBox(height: 12),

        const Text('Step 2: Caddy Reverse Proxy Config (Auto SSL):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SelectableText(
                caddyCode,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF0F172A), height: 1.4),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy Caddyfile', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: caddyCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caddyfile config copied')));
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
