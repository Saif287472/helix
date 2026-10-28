import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/dashboard/dashboard_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/invites/invites_screen.dart';
import 'package:helix_admin/src/features/payments/payments_screen.dart';
import 'package:helix_admin/src/features/reports/reports_screen.dart';
import 'package:helix_admin/src/features/settings/settings_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The console's places. Everything before Configuration is what an operator
/// does to the server's people day after day; Configuration is where the
/// server itself is read and set, and where sign-out lives. Invites exist
/// only on servers that register people by invite code; Helix Global signs
/// people up by phone number.
enum AdminPlace {
  overview('Overview', 'Overview', Icons.dashboard_outlined, Icons.dashboard),
  accounts('Users & Devices', 'Users', Icons.people_outline, Icons.people),
  invites(
    'Invites',
    'Invites',
    Icons.local_activity_outlined,
    Icons.local_activity,
  ),
  payments('Payments', 'Payments', Icons.payments_outlined, Icons.payments),
  reports('Reports', 'Reports', Icons.shield_outlined, Icons.shield),
  config('Configuration', 'Config', Icons.settings_outlined, Icons.settings);

  const AdminPlace(this.title, this.shortTitle, this.icon, this.selectedIcon);

  /// The name on the wide window's pill and for screen readers.
  final String title;

  /// The name beside the icon when the phone's dock is open on this place.
  final String shortTitle;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation and the per-session [ServerController]: the places an operator
/// works in on a pill dock with Configuration behind a gear in the header on
/// a phone, and every place as a pill in the header on a wide window.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.adminContext});

  final AdminContext adminContext;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Below this width the places move to a bottom bar and Configuration
  /// behind the header gear.
  static const _mobile = 700.0;

  /// The widest a screen's content grows on a big window.
  static const _contentWidth = 1100.0;

  late final ServerController _server;
  AdminPlace _place = AdminPlace.overview;

  /// The place the header gear was tapped from, so Configuration has a way back.
  AdminPlace _returnTo = AdminPlace.overview;

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
    return host.isEmpty ? 'Orbit server' : host;
  }

  /// Green when the server says it is ready, amber when it says it is not
  /// (or has not answered yet), red when it cannot be reached.
  Color get _dot {
    if (_server.offline) return HelixConsoleColors.danger;
    final ready = _server.ready;
    if (ready == null) return HelixConsoleColors.warn;
    return ready.ready ? HelixConsoleColors.ok : HelixConsoleColors.warn;
  }

  void _goTo(AdminPlace place) => setState(() {
    // Configuration is a screen of its own on the phone, so it needs one way
    // back to wherever the gear was tapped from.
    if (place == AdminPlace.config && _place != AdminPlace.config) {
      _returnTo = _place;
    }
    _place = place;
  });

  Widget _screen() {
    final ctx = widget.adminContext;
    return switch (_place) {
      AdminPlace.overview => DashboardScreen(server: _server),
      AdminPlace.accounts => AccountsScreen(adminContext: ctx),
      AdminPlace.invites => InvitesScreen(adminContext: ctx),
      AdminPlace.payments => PaymentsScreen(adminContext: ctx),
      AdminPlace.reports => ReportsScreen(
        adminContext: ctx,
        onOpenCount: _server.reportOpenReports,
      ),
      AdminPlace.config => ConfigView(server: _server, adminContext: ctx),
    };
  }

  /// The phone's place switcher: the Orbit dock shape, the console's colours.
  /// Configuration is not here: a gear in the header opens the place.
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
                  // Configuration is a screen of its own on the phone: the gear
                  // takes the operator in, an arrow takes them back to wherever
                  // they were. Nothing else about the shell changes.
                  if (mobile && place == AdminPlace.config)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _goTo(_returnTo),
                    )
                  else if (mobile)
                    IconButton(
                      tooltip: AdminPlace.config.title,
                      icon: Icon(AdminPlace.config.icon),
                      onPressed: () => _goTo(AdminPlace.config),
                    ),
                ],
              ),
              bottomNavigationBar: mobile && place != AdminPlace.config
                  ? SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        // Centred when it fits, swipeable when it does not:
                        // the places and a large text size are wider than a
                        // 360 dp phone.
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
                                          (p) => p != AdminPlace.config,
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
