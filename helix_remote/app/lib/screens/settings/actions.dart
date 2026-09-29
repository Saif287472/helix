part of '../settings_screen.dart';

extension _SettingsActions on _SettingsScreenState {
  int _blockedContacts() {
    try {
      return _viewModel.blockedContactsCount;
    } catch (_) {
      return 0;
    }
  }

  int _groupCount() {
    try {
      return _viewModel.groupCount;
    } catch (_) {
      try {
        return _viewModel.groupCount;
      } catch (_) {
        return 0;
      }
    }
  }

  int _lockedCount() {
    try {
      return _viewModel.lockedConversationCount;
    } catch (_) {
      return 0;
    }
  }

  static String _visibility(String value) => switch (value) {
    'EVERYONE' => 'everyone',
    'NOBODY' => 'nobody',
    _ => 'contacts',
  };

  List<_SettingsGroup> _settingsGroups(Uri serverUri) {
    final privacy = widget.messagingService.privacySettings;
    final readReceipts = widget.messagingService.readReceiptsEnabled;
    final lockedChats = _lockedCount();
    final blocked = _blockedContacts();
    final privacySummary = [
      'Last seen: ${_visibility(privacy.lastSeenVisibility)}',
      readReceipts ? 'read receipts on' : 'read receipts off',
      if (blocked > 0) '$blocked blocked',
    ].join('  \u00b7  ');
    final securitySummary = [
      AppLock.enabled ? 'App lock on' : 'App lock off',
      if (lockedChats > 0)
        '$lockedChats locked ${lockedChats == 1 ? 'chat' : 'chats'}',
    ].join('  \u00b7  ');

    // Every row opens its own page. The old list dressed up one combined
    // privacy screen behind several rows and apologised for the rest.
    return [
      _SettingsGroup(
        title: 'Account',
        items: [
          _SettingsItem(
            icon: Icons.person_outline,
            color: HelixColorTokens.cFF3B82F6,
            title: 'Account',
            subtitle: 'Profile, QR code, your data, delete account',
            onTap: _openAccount,
          ),
          _SettingsItem(
            icon: Icons.devices_outlined,
            color: HelixColorTokens.cFF5B6EE1,
            title: 'Linked devices',
            subtitle: 'View and manage connected devices',
            onTap: _openDevices,
          ),
          _SettingsItem(
            icon: Icons.backup_outlined,
            color: HelixColorTokens.cFF2FA84F,
            title: 'Backup and restore',
            subtitle: 'Create encrypted backups or restore this device',
            onTap: _openBackup,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Privacy and security',
        items: [
          _SettingsItem(
            icon: Icons.visibility_outlined,
            color: HelixColorTokens.cFF7C3AED,
            title: 'Privacy',
            subtitle: privacySummary,
            onTap: _openPrivacySettings,
          ),
          _SettingsItem(
            icon: Icons.lock_outline,
            color: HelixColorTokens.cFF4F46E5,
            title: 'Security',
            subtitle: securitySummary,
            onTap: _openSecurity,
          ),
          _SettingsItem(
            icon: Icons.notifications_none_outlined,
            color: HelixColorTokens.cFFF24E1E,
            title: 'Notifications and calls',
            subtitle: _viewModel.silenceUnknownCallers
                ? 'Unknown callers silenced'
                : 'All calls ring',
            onTap: _openNotifications,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Chats',
        items: [
          // Contacts is a bottom-tab destination; listing it here as well
          // was pure duplication. Groups has no tab, so it stays.
          _SettingsItem(
            icon: Icons.groups_outlined,
            color: HelixColorTokens.cFF14B8A6,
            title: 'Groups',
            subtitle: 'Group conversations, invites and roles',
            value: '${_groupCount()}',
            onTap: _openGroups,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'System',
        items: [
          _SettingsItem(
            icon: Icons.storage_outlined,
            color: HelixColorTokens.cFF0EA5E9,
            title: 'Storage and data',
            subtitle: 'Space used on this phone and clean-up',
            onTap: _openStorage,
          ),
          _SettingsItem(
            icon: Icons.bug_report_outlined,
            color: HelixColorTokens.cFFF97316,
            title: 'Diagnostics',
            subtitle: 'Crash reports, analytics and the error log',
            onTap: _openDiagnostics,
          ),
          _SettingsItem(
            icon: Icons.dns_outlined,
            color: HelixColorTokens.cFF4F46E5,
            title: 'Server connection',
            subtitle: _serverName ?? 'Private Server',
            onTap: widget.onChangeServerUrl == null
                ? _showServerInfo
                : _confirmChangeServer,
          ),
          _SettingsItem(
            icon: Icons.info_outline,
            color: HelixColorTokens.cFF6D6AAE,
            title: 'About Helix',
            subtitle: 'Version, build and app information',
            onTap: _showAboutHelix,
          ),
        ],
      ),
    ];
  }

  List<_SettingsGroup> _filteredGroups(Uri serverUri) {
    final groups = _settingsGroups(serverUri);
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return [
      for (final group in groups)
        _SettingsGroup(
          title: group.title,
          items: group.items
              .where(
                (item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.subtitle.toLowerCase().contains(q) ||
                    group.title.toLowerCase().contains(q),
              )
              .toList(),
        ),
    ].where((group) => group.items.isNotEmpty).toList();
  }

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final serverUri = widget.root.devConfig.restBaseUri;
    final rawDisplayName = _viewModel.displayName;
    final accountId = _viewModel.accountId;
    final displayName = rawDisplayName.isNotEmpty ? rawDisplayName : 'Account';
    final groups = _filteredGroups(serverUri);
    final destructiveItems = [
      _SettingsItem(
        icon: Icons.logout,
        color: HelixColorTokens.cFFDC2626,
        title: 'Log out',
        subtitle: 'Clear this device session',
        isDestructive: true,
        onTap: _confirmLogout,
      ),
    ].where(_matchesSearch).toList();

    return Scaffold(
      backgroundColor: _settingsPageColor(theme, cs),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: HelixInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _SettingsSearchField(
              controller: _searchController,
              query: _query,
              onChanged: (value) => _update(() => _query = value),
              onClear: () {
                _searchController.clear();
                _update(() => _query = '');
              },
            ),
            const SizedBox(height: 10),
            _ProfileCard(
              displayName: displayName,
              accountId: accountId,
              serverName: _serverName,
              onTap: _openProfile,
              onQrTap: _openMyQr,
              onEditTap: _openProfile,
            ),
            const SizedBox(height: 18),
            if (_query.isNotEmpty)
              Padding(
                padding: HelixInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  groups.isEmpty && destructiveItems.isEmpty
                      ? 'No settings found'
                      : 'Search results',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final group in groups) ...[
              _OneUiSettingsCard(group: group),
              const SizedBox(height: 14),
            ],
            if (destructiveItems.isNotEmpty) ...[
              _OneUiSettingsCard(
                group: _SettingsGroup(
                  title: 'Account actions',
                  items: destructiveItems,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (groups.isEmpty && destructiveItems.isEmpty)
              _EmptySearchState(query: _query),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  bool _matchesSearch(_SettingsItem item) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        item.title.toLowerCase().contains(q) ||
        item.subtitle.toLowerCase().contains(q);
  }
}
