import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The Settings tab: a search field, the profile card and the settings in
/// rounded groups, each row with its own coloured icon.
///
/// Every row opens a page of its own (the paths are shared in [RoutePaths]);
/// the search narrows the rows by title, description or group.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _groups = <_Group>[
    _Group('Your account', [
      _Row(
        Icons.person_outline,
        HelixColorTokens.cFF3B82F6,
        'Account',
        'Password, export, sign out, delete',
        RoutePaths.account,
      ),
      _Row(
        Icons.devices_outlined,
        HelixColorTokens.cFF5B6EE1,
        'Devices',
        'Where you are signed in',
        RoutePaths.devices,
      ),
      _Row(
        Icons.backup_outlined,
        HelixColorTokens.cFF2FA84F,
        'Backup',
        'Encrypted history and transfer',
        RoutePaths.backup,
      ),
    ]),
    _Group('Privacy and notifications', [
      _Row(
        Icons.visibility_outlined,
        HelixColorTokens.cFF7C3AED,
        'Privacy',
        'Last seen, receipts, blocked, app lock',
        RoutePaths.privacy,
      ),
      _Row(
        Icons.notifications_none_outlined,
        HelixColorTokens.cFFF24E1E,
        'Notifications',
        'Messages, groups and calls',
        RoutePaths.notifications,
      ),
    ]),
    _Group('Messaging', [
      _Row(
        Icons.chat_outlined,
        HelixColorTokens.cFF14B8A6,
        'Chats',
        'Text size, Enter key, media downloads',
        RoutePaths.chats,
      ),
    ]),
    _Group('System', [
      _Row(
        Icons.storage_outlined,
        HelixColorTokens.cFF0EA5E9,
        'Storage and data',
        'What Helix keeps on this phone',
        RoutePaths.storage,
      ),
      _Row(
        Icons.info_outline,
        HelixColorTokens.cFF6D6AAE,
        'Help and about',
        'Version, terms, privacy policy',
        RoutePaths.about,
      ),
      _Row(
        Icons.tune,
        HelixColorTokens.cFF4F46E5,
        'Advanced',
        'Server details and connection',
        RoutePaths.advanced,
      ),
    ]),
  ];

  /// The groups with only the rows that match the search.
  List<_Group> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return [
      for (final group in _groups)
        _Group(group.title, [
          for (final row in group.rows)
            if (row.title.toLowerCase().contains(q) ||
                row.subtitle.toLowerCase().contains(q) ||
                group.title.toLowerCase().contains(q))
              row,
        ]),
    ].where((g) => g.rows.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(settingsHeaderProvider).value;
    final avatar = ref.watch(settingsAvatarProvider);
    final name = header?.name ?? 'Helix';
    final about = (header?.about ?? '').isNotEmpty ? header!.about : null;
    final host = header?.serverHost;
    final shown = _shown;
    final searching = _query.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return HelixSettingsScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search settings',
                prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: HelixSettingsColors.card(scheme),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!searching)
            HelixProfileHeaderTile(
              avatar: HelixAvatarModel(
                name: name,
                image: avatar == null ? null : MemoryImage(avatar),
                colorIndex: HelixAvatarModel.colorIndexFor(
                  (header?.accountId ?? '').isEmpty
                      ? 'helix'
                      : header!.accountId,
                ),
              ),
              name: name,
              about: about,
              detail: host == null || host.isEmpty
                  ? null
                  : 'Available on $host',
              onTap: () => context.push(RoutePaths.profile),
              onEdit: () => context.push(RoutePaths.profile),
            ),
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                shown.isEmpty ? 'No settings found' : 'Search results',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final group in shown)
            HelixSettingsSection(
              title: searching ? null : group.title,
              children: [
                for (final row in group.rows)
                  HelixSettingsTile(
                    icon: row.icon,
                    iconColor: row.color,
                    title: row.title,
                    subtitle: row.subtitle,
                    showChevron: true,
                    onTap: () => context.push(row.path),
                  ),
              ],
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Material(
                color: HelixSettingsColors.card(scheme),
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 28,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 42,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No settings match "${_query.trim()}"',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try a different title or description.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Group {
  const _Group(this.title, this.rows);

  final String title;
  final List<_Row> rows;
}

class _Row {
  const _Row(this.icon, this.color, this.title, this.subtitle, this.path);

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String path;
}
