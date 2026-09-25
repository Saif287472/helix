import 'package:flutter/material.dart';

class GuideHostingChoicePage extends StatelessWidget {
  const GuideHostingChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
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
                '☁️ Infrastructure & Hosting Choice',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              SizedBox(height: 4),
              Text(
                'Select between a cloud VPS for maximum uptime or home hardware for total physical custody.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Option A Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: const BorderSide(color: Color(0xFF2563EB), width: 4), top: const BorderSide(color: Color(0xFFE2E8F0)), right: const BorderSide(color: Color(0xFFE2E8F0)), bottom: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Option A: Rented VPS (Recommended)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA7F3D0))),
                    child: const Text('99.9% Uptime', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Providers: DigitalOcean, Hetzner, Linode, Vultr, or AWS Lightsail.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              const Text('✓ Dedicated static public IPv4, unmetered high-speed uplink, independent of home network.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF059669))),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Option B Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: const BorderSide(color: Color(0xFFD97706), width: 4), top: const BorderSide(color: Color(0xFFE2E8F0)), right: const BorderSide(color: Color(0xFFE2E8F0)), bottom: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Option B: Home Hardware (PC / Mini-PC / Pi 4/5)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
                    child: const Text('\$0 Monthly Cost', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Total physical control over hardware. Must remain powered 24/7.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              const Text('Requires router port-forwarding (80/443/8080) or an encrypted tunnel (Cloudflare Tunnel / Tailscale / WireGuard), plus Dynamic DNS (DDNS).', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }
}
