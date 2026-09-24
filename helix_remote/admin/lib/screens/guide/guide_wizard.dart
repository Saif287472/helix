import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
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
        _buildHeader(),
        const SizedBox(height: 12),
        _buildProgressBar(),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
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

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Self-Hosting Guide',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  'STEP ${_pageIndex + 1} OF ${_pages.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2563EB),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
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
            minHeight: 5,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
          ),
        ),
        const SizedBox(height: 10),
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
      borderRadius: BorderRadius.circular(20),
      onTap: () => _goTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '${index + 1}. ${_pageTitles[index]}',
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : const Color(0xFF475569),
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
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
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Back'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
    final stepText = Text(
      'Step ${_pageIndex + 1} of ${_pages.length}',
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    final nextButton = ElevatedButton.icon(
      key: const Key('guide_next_button'),
      onPressed: isLast ? null : () => _goTo(_pageIndex + 1),
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: const Text('Next Step →'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
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
