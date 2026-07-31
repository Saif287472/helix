import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'guide_widgets.dart';

enum _HostingMode { vps, homePc }

/// Toggle banner switching between "rented VPS" (provider links, plain
/// outbound only, explicitly unordered) and "my own PC" sub-views. The
/// toggle is switchable at any time, not a one-way choice.
class GuideHostingChoicePage extends StatefulWidget {
  const GuideHostingChoicePage({super.key});

  @override
  State<GuideHostingChoicePage> createState() => _GuideHostingChoicePageState();
}

class _GuideHostingChoicePageState extends State<GuideHostingChoicePage> {
  _HostingMode _mode = _HostingMode.vps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GuidePageTitle('Where will this run?'),
        _toggleBanner(),
        const SizedBox(height: 20),
        _mode == _HostingMode.vps ? _vpsView() : _homePcView(),
      ],
    );
  }

  Widget _toggleBanner() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleButton('Rented VPS', _HostingMode.vps)),
          Expanded(child: _toggleButton('My own PC', _HostingMode.homePc)),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, _HostingMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      key: Key('hosting_toggle_${mode.name}'),
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8A2BE2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _vpsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rent a small Virtual Private Server and run Helix there. '
          'Providers below, in no particular order:',
          style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.6),
        ),
        const SizedBox(height: 16),
        const _ProviderLink(
          name: 'DigitalOcean',
          url: 'https://www.digitalocean.com',
        ),
        const _ProviderLink(name: 'Hetzner', url: 'https://www.hetzner.com'),
        const _ProviderLink(
          name: 'Linode (Akamai)',
          url: 'https://www.linode.com',
        ),
        const _ProviderLink(name: 'Vultr', url: 'https://www.vultr.com'),
        const _ProviderLink(
          name: 'AWS Lightsail',
          url: 'https://aws.amazon.com/lightsail',
        ),
      ],
    );
  }

  Widget _homePcView() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run Helix on a spare PC, mini PC, or a machine like a '
          'Raspberry Pi 4/5 at home. You\'ll need to keep it powered on '
          'and forward a port on your router (or use a tunnel service) so '
          'people outside your network can reach it.',
          style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.6),
        ),
        SizedBox(height: 12),
        Text(
          'Trade-off versus a VPS: no monthly fee, but your home IP '
          'address, uptime, and bandwidth become part of the equation.',
          style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.5),
        ),
      ],
    );
  }
}

class _ProviderLink extends StatelessWidget {
  const _ProviderLink({required this.name, required this.url});

  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: Key('provider_link_$name'),
        onTap: () => launchUrl(Uri.parse(url)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, size: 16, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 14, color: Color(0xFF00E5FF)),
            ),
          ],
        ),
      ),
    );
  }
}
