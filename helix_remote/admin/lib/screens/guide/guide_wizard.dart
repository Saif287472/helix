import 'package:flutter/material.dart';
import 'backups_page.dart';
import 'connect_admin_page.dart';
import 'docker_install_page.dart';
import 'domain_ssl_page.dart';
import 'hosting_choice_page.dart';
import 'server_config_page.dart';
import 'sizing_page.dart';
import 'welcome_page.dart';

/// Self-Hosting Guide, rewritten as a navigable wizard (Phase 11) in place
/// of the old static 4-step page. Always reachable with no server
/// connected - callers must never wrap this in a LockedTabPlaceholder
/// guard, and it must not gate progress on anything actually connecting.
class GuideWizard extends StatefulWidget {
  const GuideWizard({super.key, this.initialPage = 0});

  /// Page to open on first build, e.g. jumping straight to "Connect Admin"
  /// from Settings' "Where do I find this?" link.
  final int initialPage;

  @override
  State<GuideWizard> createState() => _GuideWizardState();
}

class _GuideWizardState extends State<GuideWizard> {
  static const _pageTitles = [
    'Welcome',
    'Sizing',
    'Hosting',
    'Docker',
    'Configuration',
    'Domain & SSL',
    'Connect Admin',
    'Backups',
  ];

  static const _pages = <Widget>[
    GuideWelcomePage(),
    GuideSizingPage(),
    GuideHostingChoicePage(),
    GuideDockerInstallPage(),
    GuideServerConfigPage(),
    GuideDomainSslPage(),
    GuideConnectAdminPage(),
    GuideBackupsPage(),
  ];

  late int _pageIndex = widget.initialPage.clamp(0, _pages.length - 1);

  void _goTo(int index) {
    setState(() => _pageIndex = index.clamp(0, _pages.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgressBar(),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              color: const Color(0xFF161624),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: IndexedStack(index: _pageIndex, children: _pages),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildNavRow(),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: const Key('guide_progress_bar'),
            value: (_pageIndex + 1) / _pages.length,
            minHeight: 6,
            backgroundColor: const Color(0xFF0B0B12),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF8A2BE2)),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _pageTitles.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _pageChip(i),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pageChip(int index) {
    final selected = index == _pageIndex;
    return InkWell(
      key: Key('guide_page_chip_$index'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => _goTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF8A2BE2).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF8A2BE2) : Colors.white24,
          ),
        ),
        child: Text(
          '${index + 1}. ${_pageTitles[index]}',
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildNavRow() {
    final isFirst = _pageIndex == 0;
    final isLast = _pageIndex == _pages.length - 1;
    final backButton = OutlinedButton.icon(
      key: const Key('guide_back_button'),
      onPressed: isFirst ? null : () => _goTo(_pageIndex - 1),
      icon: const Icon(Icons.arrow_back),
      label: const Text('Back'),
    );
    final stepText = Text(
      'Step ${_pageIndex + 1} of ${_pages.length}',
      style: const TextStyle(color: Colors.white54, fontSize: 12),
    );
    final nextButton = ElevatedButton.icon(
      key: const Key('guide_next_button'),
      onPressed: isLast ? null : () => _goTo(_pageIndex + 1),
      icon: const Icon(Icons.arrow_forward),
      label: const Text('Next'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8A2BE2),
        foregroundColor: Colors.white,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Back + Step X of Y + Next don't fit on one line on narrow phones -
        // stack the buttons on their own row with the step label centered
        // below instead of letting the row overflow off-screen.
        if (constraints.maxWidth < 420) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: backButton),
                  const SizedBox(width: 12),
                  Expanded(child: nextButton),
                ],
              ),
              const SizedBox(height: 8),
              Center(child: stepText),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [backButton, stepText, nextButton],
        );
      },
    );
  }
}
