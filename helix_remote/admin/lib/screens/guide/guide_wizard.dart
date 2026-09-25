import 'package:flutter/material.dart';
import 'backups_page.dart';
import 'connect_admin_page.dart';
import 'docker_install_page.dart';
import 'domain_ssl_page.dart';
import 'hosting_choice_page.dart';
import 'server_config_page.dart';
import 'sizing_page.dart';
import 'welcome_page.dart';

/// Self-Hosting Guide Wizard matching demo specification in helix_admin.
class GuideWizard extends StatefulWidget {
  const GuideWizard({
    super.key,
    this.initialPage = 0,
    this.onClose,
  });

  final int initialPage;
  final VoidCallback? onClose;

  @override
  State<GuideWizard> createState() => _GuideWizardState();
}

class _GuideWizardState extends State<GuideWizard> {
  static const _pageTitles = [
    '1. Architecture',
    '2. Sizing',
    '3. Hosting',
    '4. Docker',
    '5. Config & Env',
    '6. Domain & SSL',
    '7. Admin Connect',
    '8. Maintenance',
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

  late int _pageIndex;
  late final PageController _pageController;
  final ScrollController _stepPillScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.initialPage.clamp(0, _pages.length - 1);
    _pageController = PageController(initialPage: _pageIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPill(_pageIndex));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stepPillScrollController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final clamped = index.clamp(0, _pages.length - 1);
    if (clamped == _pageIndex) return;
    setState(() => _pageIndex = clamped);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _scrollToPill(clamped);
  }

  void _scrollToPill(int index) {
    if (!_stepPillScrollController.hasClients) return;
    const approxItemWidth = 110.0;
    final targetOffset = (index * approxItemWidth) - 80.0;
    final clamped = targetOffset.clamp(
      0.0,
      _stepPillScrollController.position.maxScrollExtent,
    );
    _stepPillScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 10),
        _buildProgressBar(),
        const SizedBox(height: 12),
        _buildStepPills(),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.all(20),
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _pageIndex = index);
                _scrollToPill(index);
              },
              children: _pages,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildNavRow(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🌐 Self-Hosting Guide',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              const SizedBox(height: 2),
              const Text(
                'Complete 8-Step Blueprint for Deploying Your Node',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: (_pageIndex + 1) / _pages.length,
        minHeight: 4,
        backgroundColor: const Color(0xFFE2E8F0),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
      ),
    );
  }

  Widget _buildStepPills() {
    return SingleChildScrollView(
      controller: _stepPillScrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_pageTitles.length, (i) {
          final isSelected = i == _pageIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => _goTo(i),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF2563EB))
                      : Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  _pageTitles[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavRow() {
    final isFirst = _pageIndex == 0;
    final isLast = _pageIndex == _pages.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF334155),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: isFirst ? null : () => _goTo(_pageIndex - 1),
        ),
        FilledButton.icon(
          icon: Icon(isLast ? Icons.check : Icons.arrow_forward, size: 16),
          label: Text(isLast ? 'Finish' : 'Next Step →'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          onPressed: () {
            if (isLast) {
              if (widget.onClose != null) {
                widget.onClose!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            } else {
              _goTo(_pageIndex + 1);
            }
          },
        ),
      ],
    );
  }
}
