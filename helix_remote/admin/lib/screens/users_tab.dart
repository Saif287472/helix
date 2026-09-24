import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import '../admin_client.dart';
import '../theme/app_theme.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key, required this.client});

  final AdminClient client;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _users = [];
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;
  String? _busyAccountId;

  String _filterStatus = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({int offset = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.getUsers(
        limit: _pageSize,
        offset: offset,
      );
      final users = (result['users'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _users = users;
        _offset = offset;
        _hasMore = users.length == _pageSize;
        _loading = false;
        if (_selectedUser != null) {
          final selId = _selectedUser!['account_id'];
          _selectedUser = users.firstWhere(
            (u) => u['account_id'] == selId,
            orElse: () => users.isNotEmpty ? users.first : {},
          );
          if (_selectedUser!.isEmpty) _selectedUser = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _suspend(String accountId) async {
    setState(() => _busyAccountId = accountId);
    try {
      await widget.client.suspendUser(accountId);
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _unsuspend(String accountId) async {
    setState(() => _busyAccountId = accountId);
    try {
      await widget.client.unsuspendUser(accountId);
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _issueRecoveryCode(String accountId, String displayLabel) async {
    setState(() => _busyAccountId = accountId);
    try {
      final result = await widget.client.generateRecoveryCode(accountId);
      final code = result['opaque_code'] as String? ??
          result['code'] as String? ??
          result['recovery_code'] as String? ??
          '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Account Recovery Code',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send this recovery code to $displayLabel. They can enter it on a new '
                  'device to restore their account access. The server address is '
                  'shielded inside this code.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: HelixInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Code'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Recovery code copied to clipboard'),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _confirmDelete(String accountId, String displayLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this user?'),
        content: Text(
          'This permanently deletes $displayLabel\'s account and all of '
          'their messages, devices, and contacts. Their phone number is '
          'left free - it can register a brand-new account here again. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyAccountId = accountId);
    try {
      await widget.client.deleteUser(accountId);
      if (_selectedUser?['account_id'] == accountId) {
        _selectedUser = null;
      }
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _confirmBlock(String accountId, String displayLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this user?'),
        content: Text(
          'This permanently deletes $displayLabel\'s account and all of '
          'their messages, devices, and contacts, and also bans their '
          'phone number from ever registering here again. Use "Delete '
          'permanently" instead if you only want to remove the account. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyAccountId = accountId);
    try {
      await widget.client.blockUser(accountId);
      if (_selectedUser?['account_id'] == accountId) {
        _selectedUser = null;
      }
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _manageDevices(Map<String, dynamic> user) async {
    final accountId = user['account_id'] as String? ?? '';
    final displayName = user['display_name'] as String? ?? accountId;
    final devices = (user['devices'] as List? ?? []).cast<Map<String, dynamic>>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.devices, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Devices for $displayName',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: devices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No active devices registered for this user.'),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final dev = devices[i];
                      final devId = dev['device_id'] as String? ?? '';
                      final devName = dev['device_name'] as String? ?? devId;
                      final isRevoked = dev['status'] == 'REVOKED';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.phone_android, size: 24),
                        title: Text(devName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          devId,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                        trailing: isRevoked
                            ? const Text(
                                'Revoked',
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                                onPressed: () async {
                                  try {
                                    await widget.client.revokeDevice(accountId, devId);
                                    setDialogState(() {
                                      dev['status'] = 'REVOKED';
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Access revoked for $devName')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to revoke device: $e')),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Revoke'),
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _openUserSheet(Map<String, dynamic> user) {
    setState(() => _selectedUser = user);
    final width = MediaQuery.of(context).size.width;
    if (width < 900) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _buildSheetModal(user),
      );
    }
  }

  Widget _buildSheetModal(Map<String, dynamic> user) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: const Color(0xFF64748B),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailPaneContent(user, inSheet: true),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      if (_filterStatus != 'ALL') {
        final status = (u['status'] as String? ?? 'ACTIVE').toUpperCase();
        if (status != _filterStatus) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = (u['display_name'] as String? ?? '').toLowerCase();
        final id = (u['account_id'] as String? ?? '').toLowerCase();
        final phone = (u['phone_last4'] as String? ?? '').toLowerCase();
        if (!name.contains(_searchQuery) &&
            !id.contains(_searchQuery) &&
            !phone.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _users.where((u) => u['status'] != 'SUSPENDED').length;
    final suspendedCount = _users.where((u) => u['status'] == 'SUSPENDED').length;
    final filtered = _filteredUsers;

    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: HelixInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Users & Devices',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload users',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _loadUsers(offset: _offset),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Registered members, linked devices, and security controls.',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Search Bar & Filter Chips
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone number, or ID…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All Users (${_users.length})'),
                    selected: _filterStatus == 'ALL',
                    onSelected: (s) {
                      if (s) setState(() => _filterStatus = 'ALL');
                    },
                  ),
                  ChoiceChip(
                    label: Text('Active ($activeCount)'),
                    selected: _filterStatus == 'ACTIVE',
                    onSelected: (s) {
                      if (s) setState(() => _filterStatus = 'ACTIVE');
                    },
                  ),
                  ChoiceChip(
                    label: Text('Suspended ($suspendedCount)'),
                    selected: _filterStatus == 'SUSPENDED',
                    onSelected: (s) {
                      if (s) setState(() => _filterStatus = 'SUSPENDED');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_loading)
                Center(
                  child: Padding(
                    padding: HelixInsets.all(24),
                    child: const CircularProgressIndicator(),
                  ),
                )
              else if (_users.isEmpty)
                Padding(
                  padding: HelixInsets.all(24),
                  child: Text(
                    'No users registered yet.',
                    style: TextStyle(color: context.textFaint),
                  ),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: HelixInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 40, color: context.textFaint),
                        const SizedBox(height: 10),
                        Text(
                          'No matching users found.',
                          style: TextStyle(color: context.textFaint),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _filterStatus = 'ALL';
                            });
                          },
                          child: const Text('Reset Filters'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSplit = constraints.maxWidth >= 900;
                    if (!isSplit) {
                      return Column(
                        children: [
                          for (final u in filtered) _buildUserCard(u, isSelected: false),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Master List
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              for (final u in filtered)
                                _buildUserCard(
                                  u,
                                  isSelected: _selectedUser?['account_id'] == u['account_id'],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Right Detail Pane
                        Expanded(
                          flex: 4,
                          child: _selectedUser != null
                              ? _buildDetailPaneContent(_selectedUser!, inSheet: false)
                              : Container(
                                  padding: HelixInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: context.sunkenSurface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.touch_app, size: 36, color: context.textFaint),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Select a user from the list to inspect identity, devices, and actions.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: context.textFaint, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              if (!_loading && (_users.isNotEmpty || _offset > 0)) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('users_previous_page'),
                      onPressed: _offset > 0
                          ? () => _loadUsers(
                              offset: (_offset - _pageSize).clamp(0, 1 << 30),
                            )
                          : null,
                      child: const Text('Previous'),
                    ),
                    TextButton(
                      key: const Key('users_next_page'),
                      onPressed: _hasMore
                          ? () => _loadUsers(offset: _offset + _pageSize)
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, {required bool isSelected}) {
    final accountId = user['account_id'] as String? ?? '';
    final status = user['status'] as String? ?? 'ACTIVE';
    final isSuspended = status == 'SUSPENDED';
    final isBusy = _busyAccountId == accountId;
    final displayName = user['display_name'] as String? ?? '';
    final phone = _formatPhone(user['phone_last4'] as String?);
    final inviteId = user['invite_id'] as String? ?? '—';
    final joined = _formatTimestamp(user['created_at']);
    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : (accountId.isNotEmpty ? accountId[0].toUpperCase() : 'U');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openUserSheet(user),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar circle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info Group
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName.isEmpty ? '—' : displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          accountId,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: context.textFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          inviteId,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textFaint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          joined,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Status Chip
              _statusChip(isSuspended),
              const SizedBox(width: 8),

              // Row Actions
              if (isBusy)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.devices_outlined, size: 20),
                      tooltip: 'Manage devices',
                      onPressed: () => _manageDevices(user),
                    ),
                    IconButton(
                      icon: const Icon(Icons.key_outlined, size: 20),
                      tooltip: 'Issue recovery code',
                      onPressed: () => _issueRecoveryCode(
                        accountId,
                        displayName.isEmpty ? accountId : displayName,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isSuspended
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 20,
                      ),
                      tooltip: isSuspended
                          ? 'Restore access'
                          : 'Suspend access (temporary)',
                      onPressed: () => isSuspended
                          ? _unsuspend(accountId)
                          : _suspend(accountId),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_forever_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Delete permanently',
                      onPressed: () => _confirmDelete(
                        accountId,
                        displayName.isEmpty ? accountId : displayName,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.block,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Block (delete + ban phone number)',
                      onPressed: () => _confirmBlock(
                        accountId,
                        displayName.isEmpty ? accountId : displayName,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPaneContent(Map<String, dynamic> user, {required bool inSheet}) {
    final accountId = user['account_id'] as String? ?? '';
    final displayName = user['display_name'] as String? ?? '';
    final phone = _formatPhone(user['phone_last4'] as String?);
    final status = user['status'] as String? ?? 'ACTIVE';
    final isSuspended = status == 'SUSPENDED';
    final joined = _formatTimestamp(user['created_at']);
    final devices = (user['devices'] as List? ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cardlet 1: User Identity & State
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'USER IDENTITY & STATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  _statusChip(isSuspended),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : 'Unnamed User',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phone == '—' ? 'No phone bound' : phone,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Joined $joined',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cardlet 2: Active Sessions / Devices
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ACTIVE SESSIONS / DEVICES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${devices.length} Active',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No active devices registered.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                )
              else
                for (final dev in devices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_android, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dev['device_name'] ?? dev['device_id'] ?? 'Device',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${dev['device_id'] ?? 'unknown'}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (dev['status'] == 'REVOKED')
                          const Text('Revoked', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11))
                        else
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () async {
                              await widget.client.revokeDevice(accountId, dev['device_id']);
                              await _loadUsers(offset: _offset);
                            },
                            child: const Text('Revoke', style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cardlet 3: Administrative Actions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ADMINISTRATIVE ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.key, size: 16),
                label: const Text('Issue 48h Recovery Key'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () => _issueRecoveryCode(accountId, displayName.isEmpty ? accountId : displayName),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy User ID'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: accountId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account ID copied')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cardlet 4: Danger Zone
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DANGER ZONE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFDC2626),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline, size: 16),
                label: Text(isSuspended ? 'Restore Account' : 'Suspend Account'),
                onPressed: () => isSuspended ? _unsuspend(accountId) : _suspend(accountId),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete User Data'),
                onPressed: () => _confirmDelete(accountId, displayName.isEmpty ? accountId : displayName),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF991B1B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Permanent Block Phone'),
                onPressed: () => _confirmBlock(accountId, displayName.isEmpty ? accountId : displayName),
              ),
            ],
          ),
        ),

        if (inSheet) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(bool isSuspended) {
    final bg = isSuspended ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7);
    final fg = isSuspended ? const Color(0xFFB45309) : const Color(0xFF166534);
    final border = isSuspended ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0);
    return Chip(
      label: Text(
        isSuspended ? 'SUSPENDED' : 'ACTIVE',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
      backgroundColor: bg,
      side: BorderSide(color: border),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    return phone;
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
