import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/audit/audit_screen.dart';
import 'package:helix_admin/src/features/dashboard/dashboard_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/invites/invites_screen.dart';
import 'package:helix_admin/src/features/logs/logs_screen.dart';
import 'package:helix_admin/src/features/reports/reports_screen.dart';
import 'package:helix_admin/src/features/settings/settings_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The console's places. Invites exist only on servers that register people
/// by invite code.
enum AdminPlace {
  overview('Overview', Icons.dashboard_outlined, Icons.dashboard),
  accounts('Accounts', Icons.people_outline, Icons.people),
  invites('Invites', Icons.local_activity_outlined, Icons.local_activity),
  reports('Reports', Icons.flag_outlined, Icons.flag),
  activity('Audit log', Icons.history, Icons.history),
  logs('Server log', Icons.article_outlined, Icons.article),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AdminPlace(this.title, this.icon, this.selectedIcon);

  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation and the per-session [ServerController]: a side list on wide
/// windows, a drawer on narrow ones.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.adminContext});

  final AdminContext adminContext;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const _wide = 800.0;

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

  void _go(AdminPlace place) {
    setState(() => _place = place);
  }

  Widget _screen() {
    final ctx = widget.adminContext;
    return switch (_place) {
      AdminPlace.overview => DashboardScreen(server: _server),
      AdminPlace.accounts => AccountsScreen(adminContext: ctx),
      AdminPlace.invites => InvitesScreen(adminContext: ctx),
      AdminPlace.reports => ReportsScreen(adminContext: ctx),
      AdminPlace.activity => AuditScreen(adminContext: ctx),
      AdminPlace.logs => LogsScreen(adminContext: ctx),
      AdminPlace.settings => SettingsScreen(server: _server),
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
            final wide = constraints.maxWidth >= _wide;
            final nav = _NavList(
              serverName: _serverName,
              places: places,
              selected: place,
              onSelected: (p) {
                _go(p);
                if (!wide) Navigator.of(context).pop();
              },
            );
            return Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.title),
                    Text(
                      _serverName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                actions: [
                  if (place == AdminPlace.overview)
                    IconButton(
                      tooltip: 'Reload server status',
                      icon: const Icon(Icons.refresh),
                      onPressed: _server.loading ? null : _server.refresh,
                    ),
                ],
              ),
              drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
              body: wide
                  ? Row(
                      children: [
                        SizedBox(width: 240, child: nav),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _KeyedScreen(place: place, child: _screen()),
                        ),
                      ],
                    )
                  : _KeyedScreen(place: place, child: _screen()),
            );
          },
        );
      },
    );
  }
}

/// Gives each place its own state, so a screen's controller starts fresh when
/// the operator comes back to it.
class _KeyedScreen extends StatelessWidget {
  const _KeyedScreen({required this.place, required this.child});

  final AdminPlace place;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(place), child: child);
}

class _NavList extends StatelessWidget {
  const _NavList({
    required this.serverName,
    required this.places,
    required this.selected,
    required this.onSelected,
  });

  final String serverName;
  final List<AdminPlace> places;
  final AdminPlace selected;
  final ValueChanged<AdminPlace> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HelixSpace.md,
            HelixSpace.sm,
            HelixSpace.md,
            HelixSpace.sm,
          ),
          child: Text(
            serverName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final place in places)
          ListTile(
            selected: place == selected,
            leading: Icon(place == selected ? place.selectedIcon : place.icon),
            title: Text(place.title),
            onTap: () => onSelected(place),
          ),
      ],
    );
  }
}
