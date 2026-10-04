import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/home/application/home_tab.dart';

/// Home: three swipeable tabs and nothing else.
///
/// The tabs are a horizontal [PageView] so a swipe moves between them, and
/// each one is kept alive so its scroll position and loaded rows survive a
/// swipe away and back. The bar below jumps between them with the same
/// animation.
class HomeScreen extends StatefulWidget {
  /// The three tabs' content. Each belongs to its own feature, and a feature
  /// may not import another (the home shell only lays tabs out), so the
  /// router hands them in.
  const HomeScreen({
    super.key,
    required this.chatsTab,
    required this.callsTab,
    required this.settingsTab,
  });

  final Widget chatsTab;
  final Widget callsTab;
  final Widget settingsTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pages = PageController();
  HomeTab _tab = HomeTab.chats;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(HomeTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _pages.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pages,
        onPageChanged: (index) => setState(() => _tab = HomeTab.values[index]),
        children: [
          HomeTabKeepAlive(child: widget.chatsTab),
          HomeTabKeepAlive(child: widget.callsTab),
          HomeTabKeepAlive(child: widget.settingsTab),
        ],
      ),
      bottomNavigationBar: _HomeBar(selected: _tab, onSelected: _select),
    );
  }
}

/// Keeps a tab's state and scroll position while the person is on another.
///
/// Without this, swiping to Calls and back would rebuild the chat list from
/// its watch query and lose the scroll position, which is the one thing a
/// person expects to survive a swipe.
class HomeTabKeepAlive extends StatefulWidget {
  const HomeTabKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<HomeTabKeepAlive> createState() => _HomeTabKeepAliveState();
}

class _HomeTabKeepAliveState extends State<HomeTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _HomeBar extends StatelessWidget {
  const _HomeBar({required this.selected, required this.onSelected});

  final HomeTab selected;
  final ValueChanged<HomeTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
      height: 74,
      backgroundColor: scheme.surface,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      selectedIndex: selected.index,
      onDestinationSelected: (index) => onSelected(HomeTab.values[index]),
      destinations: [
        for (final tab in HomeTab.values)
          NavigationDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: tab.label,
          ),
      ],
    );
  }
}

/// The app bar every tab shares. Each tab keeps its own actions, so this only
/// carries what is common: the title and the back arrow's absence.
class HomeTabScaffold extends ConsumerWidget {
  const HomeTabScaffold({
    super.key,
    required this.title,
    required this.tab,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final HomeTab tab;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: child,
    );
  }
}
