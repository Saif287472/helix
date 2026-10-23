import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/dashboard_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/invites/invites_screen.dart';
import 'package:helix_admin/src/features/ops/ops_screen.dart';
import 'package:helix_admin/src/features/reports/reports_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Which half of the navigation a place belongs to: the phone's dock has
/// room for the operate places, the system ones live behind the gear.
enum AdminGroup { operate, system }

/// The console's places, split in two. The operate group is what an operator
/// does to the server's people day after day; the system group is what they
/// read or set rarely. Invites exist only on servers that register people by
/// invite code; Helix Global signs people up by phone number.
enum AdminPlace {
  overview(
    'Overview',
    'Overview',
    Icons.dashboard_outlined,
    Icons.dashboard,
    AdminGroup.operate,
  ),
  accounts(
    'Users & Devices',
    'Users',
    Icons.people_outline,
    Icons.people,
    AdminGroup.operate,
  ),
  invites(
    'Invites',
    'Invites',
    Icons.local_activity_outlined,
    Icons.local_activity,
    AdminGroup.operate,
  ),
  reports(
    'Reports',
    'Reports',
    Icons.shield_outlined,
    Icons.shield,
    AdminGroup.operate,
  ),
  system(
    'System',
    'System',
    Icons.settings_outlined,
    Icons.settings,
    AdminGroup.system,
  );

  const AdminPlace(
    this.title,
    this.shortTitle,
    this.icon,
    this.selectedIcon,
    this.group,
  );

  /// The name on the wide window's pill and for screen readers.
  final String title;

  /// The name beside the icon when the phone's dock is open on this place.
  final String shortTitle;
  final IconData icon;
  final IconData selectedIcon;
  final AdminGroup group;
}

/// Navigation and the per-session [ServerController]: the operate places on a
/// pill dock with the system places behind a gear in a drawer on a phone, and
/// all five places as pills in the header on a wide window.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.adminContext});

  final AdminContext adminContext;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Below this width the places move to a bottom bar and the system group
  /// to a drawer.
  static const _mobile = 700.0;

  /// The widest a screen's content grows on a big window.
  static const _contentWidth = 1100.0;

  late final ServerController _server;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  AdminPlace _place = AdminPlace.overview;

  /// Where inside the system place the operator is; the phone's drawer rows
  /// choose it, the segmented bar on the screen changes it.
  OpsTab _opsTab = OpsTab.audit;

  @override
  void initState() {
    super.initState();
    _server = ServerController(widget.adminContext)..refresh();
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  /// Every place the server this console is signed in to has.
  List<AdminPlace> get _places => [
    for (final p in AdminPlace.values)
      if (p != AdminPlace.invites || _server.usesInvites) p,
  ];

  String get _serverName {
    final name = _server.config?.serverName;
    if (name != null && name.isNotEmpty) return name;
    final host = widget.adminContext.api.transport.baseUrl.host;
    return host.isEmpty ? 'Helix server' : host;
  }

  /// Green when the server says it is ready, amber when it says it is not
  /// (or has not answered yet), red when it cannot be reached.
  Color get _dot {
    if (_server.offline) return HelixConsoleColors.danger;
    final ready = _server.ready;
    if (ready == null) return HelixConsoleColors.warn;
    return ready.ready ? HelixConsoleColors.ok : HelixConsoleColors.warn;
  }

  /// The drawer's one line about the session, in the same words the
  /// configuration screen uses for it.
  String get _sessionLine {
    final expires = AdminSessionScope.of(context).sessionExpiresAt;
    if (expires == null) return 'Signed in on this device';
    if (!expires.isAfter(widget.adminContext.now())) {
      return 'This session has ended';
    }
    return 'Signed in until ${formatTime(expires)}';
  }

  void _goTo(AdminPlace place) => setState(() => _place = place);

  /// A drawer row: close the drawer and open the system place on that tab.
  void _openSystem(OpsTab tab) {
    _scaffoldKey.currentState?.closeEndDrawer();
    setState(() {
      _place = AdminPlace.system;
      _opsTab = tab;
    });
  }

  Widget _screen() {
    final ctx = widget.adminContext;
    return switch (_place) {
      AdminPlace.overview => DashboardScreen(server: _server),
      AdminPlace.accounts => AccountsScreen(adminContext: ctx),
      AdminPlace.invites => InvitesScreen(adminContext: ctx),
      AdminPlace.reports => ReportsScreen(
        adminContext: ctx,
        onOpenCount: _server.reportOpenReports,
      ),
      AdminPlace.system => OpsScreen(
        adminContext: ctx,
        server: _server,
        tab: _opsTab,
        onTabChanged: (tab) => setState(() => _opsTab = tab),
      ),
    };
  }

  /// The phone's place switcher: the Orbit dock shape, the console's colours.
  /// The system group is not here: a gear in the header opens it as a drawer.
  Widget _dock(Iterable<AdminPlace> places, AdminPlace selected) => ConsoleDock(
    items: [
      for (final p in places)
        ConsoleDockItem(
          icon: p.icon,
          selectedIcon: p.selectedIcon,
          label: p.shortTitle,
          tooltip: p.title,
          on: p == selected,
          badge: p == AdminPlace.reports ? _server.openReports : 0,
          badgeMore: p == AdminPlace.reports && _server.openReportsMore,
          onTap: () => _goTo(p),
        ),
    ],
  );

  /// The phone's system drawer: what the dock has no room for, the session,
  /// and the way out.
  Widget _drawer(bool inSystemPlace) => ConsoleDrawer(
    title: _serverName,
    subtitle: _sessionLine,
    groups: [
      ConsoleDrawerGroup(
        label: 'System activity',
        rows: [
          ConsoleDrawerRow(
            icon: Icons.history,
            label: 'Audit trail',
            subtitle: 'What this console has done',
            selected: inSystemPlace && _opsTab == OpsTab.audit,
            onTap: () => _openSystem(OpsTab.audit),
          ),
          ConsoleDrawerRow(
            icon: Icons.terminal,
            label: 'Live log',
            subtitle: 'What the server is saying now',
            selected: inSystemPlace && _opsTab == OpsTab.logs,
            onTap: () => _openSystem(OpsTab.logs),
          ),
        ],
      ),
      ConsoleDrawerGroup(
        label: 'Environment setup',
        rows: [
          ConsoleDrawerRow(
            icon: Icons.build_outlined,
            label: 'Configuration',
            subtitle: 'Server settings and this sign-in session',
            selected: inSystemPlace && _opsTab == OpsTab.config,
            onTap: () => _openSystem(OpsTab.config),
          ),
        ],
      ),
    ],
    onSignOut: () {
      _scaffoldKey.currentState?.closeEndDrawer();
      confirmAndSignOut(context);
    },
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _server,
      builder: (context, _) {
        final places = _places;
        final place = places.contains(_place) ? _place : AdminPlace.overview;
        return LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < _mobile;
            return Scaffold(
              key: _scaffoldKey,
              appBar: AppBar(
                automaticallyImplyLeading: false,
                titleSpacing: 16,
                title: Row(
                  children: [
                    ConsoleDot(color: _dot),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        _serverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (!mobile) ...[
                      const SizedBox(width: 24),
                      // The pills scroll rather than overflow: five places and
                      // a long server name are wider than a narrow window.
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final p in places) ...[
                                _Pill(
                                  place: p,
                                  selected: p == place,
                                  badge: p == AdminPlace.reports
                                      ? _server.openReports
                                      : 0,
                                  badgeMore:
                                      p == AdminPlace.reports &&
                                      _server.openReportsMore,
                                  onTap: () => _goTo(p),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (mobile)
                    IconButton(
                      tooltip: 'System and configuration options',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                ],
              ),
              bottomNavigationBar: mobile
                  ? SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        // Centred when it fits, swipeable when it does not:
                        // the operate places and a large text size are wider
                        // than a 360 dp phone.
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: constraints.maxWidth,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _dock(
                                        places.where(
                                          (p) => p.group == AdminGroup.operate,
                                        ),
                                        place,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ),
                      ),
                    )
                  : null,
              endDrawer: mobile ? _drawer(place == AdminPlace.system) : null,
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentWidth),
                  // Each place gets its own state, so a screen's controller
                  // starts fresh when the operator comes back to it.
                  child: KeyedSubtree(key: ValueKey(place), child: _screen()),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// One place on the wide window's header.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.place,
    required this.selected,
    required this.badge,
    required this.badgeMore,
    required this.onTap,
  });

  final AdminPlace place;
  final bool selected;

  /// Open reports, when this pill is the Reports place. Zero shows nothing.
  final int badge;
  final bool badgeMore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? HelixConsoleColors.accent
        : HelixConsoleColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0
          ? '${place.title}, ${consoleCount(badge, more: badgeMore)} open'
          : place.title,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? HelixConsoleColors.accentContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? place.selectedIcon : place.icon,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    place.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    ConsoleCount(badge, more: badgeMore),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
