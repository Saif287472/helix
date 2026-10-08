import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/dashboard/dashboard_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/invites/invites_screen.dart';
import 'package:helix_admin/src/features/ops/ops_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The console's places. Invites exist only on servers that register people
/// by invite code; Helix Global signs people up by phone number.
enum AdminPlace {
  overview('Overview', 'Overview', Icons.dashboard_outlined, Icons.dashboard),
  accounts('Users & Devices', 'Users', Icons.people_outline, Icons.people),
  invites(
    'Invites',
    'Invites',
    Icons.local_activity_outlined,
    Icons.local_activity,
  ),
  ops('Ops & Logs', 'Ops & Logs', Icons.settings_outlined, Icons.settings);

  const AdminPlace(this.title, this.shortTitle, this.icon, this.selectedIcon);

  /// The name on the wide window's pill and for screen readers.
  final String title;

  /// The name under the icon on the phone's bottom bar.
  final String shortTitle;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation and the per-session [ServerController]: a bottom bar on a
/// phone, pills in the header on a wide window.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.adminContext});

  final AdminContext adminContext;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Below this width the places move to a bottom bar.
  static const _mobile = 700.0;

  /// The widest a screen's content grows on a big window.
  static const _contentWidth = 1100.0;

  late final ServerController _server;
  AdminPlace _place = AdminPlace.overview;

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

  Widget _screen() {
    final ctx = widget.adminContext;
    return switch (_place) {
      AdminPlace.overview => DashboardScreen(server: _server),
      AdminPlace.accounts => AccountsScreen(adminContext: ctx),
      AdminPlace.invites => InvitesScreen(adminContext: ctx),
      AdminPlace.ops => OpsScreen(adminContext: ctx, server: _server),
    };
  }

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
                    Flexible(
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
                      for (final p in places) ...[
                        _Pill(
                          place: p,
                          selected: p == place,
                          onTap: () => setState(() => _place = p),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ],
                ),
              ),
              bottomNavigationBar: mobile
                  ? NavigationBar(
                      selectedIndex: places.indexOf(place),
                      onDestinationSelected: (i) =>
                          setState(() => _place = places[i]),
                      destinations: [
                        for (final p in places)
                          NavigationDestination(
                            icon: Icon(p.icon),
                            selectedIcon: Icon(p.selectedIcon),
                            label: p.shortTitle,
                            tooltip: p.title,
                          ),
                      ],
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
    required this.onTap,
  });

  final AdminPlace place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? HelixConsoleColors.accent
        : HelixConsoleColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: place.title,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
