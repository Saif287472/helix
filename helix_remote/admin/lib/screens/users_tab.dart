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

  /// Applies [status] to the account locally so the row updates immediately,
  /// and returns the status it replaced so a failed call can be rolled back.
  String? _applyStatusLocally(String accountId, String status) {
    String? previous;
    for (final u in _users) {
      if (u['account_id'] == accountId) {
        previous = u['status'] as String?;
        u['status'] = status;
      }
    }
    if (_selectedUser?['account_id'] == accountId) {
      previous ??= _selectedUser!['status'] as String?;
      _selectedUser!['status'] = status;
    }
    return previous;
  }

  Future<void> _suspend(String accountId) async {
    setState(() {
      _busyAccountId = accountId;
      _error = null;
    });
    final previousStatus = _applyStatusLocally(accountId, 'SUSPENDED');

    try {
      await widget.client.suspendUser(accountId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account suspended successfully'),
          duration: Duration(seconds: 2),
        ),
      );
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      // Roll the optimistic row back so a failed suspend is not displayed as
      // a suspended account.
      setState(() {
        if (previousStatus != null) {
          _applyStatusLocally(accountId, previousStatus);
        }
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _unsuspend(String accountId) async {
    setState(() {
      _busyAccountId = accountId;
      _error = null;
    });
    final previousStatus = _applyStatusLocally(accountId, 'ACTIVE');

    try {
      await widget.client.unsuspendUser(accountId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account restored successfully'),
          duration: Duration(seconds: 2),
        ),
      );
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previousStatus != null) {
          _applyStatusLocally(accountId, previousStatus);
        }
        _error = e.toString();
      });
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

    // Marks the account busy for the whole call, exactly as _confirmDelete
    // does. Without it the row's action buttons stayed live during a block
    // that deletes an account, every device and a phone-number ban, so a
    // second tap could fire a concurrent write against an account that was
    // already being torn down.
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header matching right demo image
          const Text(
            'Users & Devices',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),

          // Search Bar (Stadium pill shape)
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, phone number, or ID...',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFF2563EB)),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 14),

          // Filter Pills (No checkmark icon)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill(
                  label: 'All Users (${_users.length})',
                  isSelected: _filterStatus == 'ALL',
                  onTap: () => setState(() => _filterStatus = 'ALL'),
                ),
                const SizedBox(width: 8),
                _buildFilterPill(
                  label: 'Active ($activeCount)',
                  isSelected: _filterStatus == 'ACTIVE',
                  onTap: () => setState(() => _filterStatus = 'ACTIVE'),
                ),
                const SizedBox(width: 8),
                _buildFilterPill(
                  label: 'Suspended ($suspendedCount)',
                  isSelected: _filterStatus == 'SUSPENDED',
                  onTap: () => setState(() => _filterStatus = 'SUSPENDED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

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
        );
  }

  Widget _buildUserCard(Map<String, dynamic> user, {required bool isSelected}) {
    final accountId = user['account_id'] as String? ?? '';
    final status = user['status'] as String? ?? 'ACTIVE';
    final isSuspended = status == 'SUSPENDED';
    final displayName = user['display_name'] as String? ?? '';
    final phone = _formatPhone(user);
    final joined = _formatTimestamp(user['created_at']);
    final devices = (user['devices'] as List? ?? []).cast<Map<String, dynamic>>();
    // `device_count` is the server's own count of ACTIVE devices for this
    // account. Prefer the attached device list when present, fall back to the
    // server count, and never invent a value - an account with no registered
    // devices is genuinely zero, not one.
    final rawCount = user['device_count'];
    final devicesCount = devices.isNotEmpty
        ? devices.length
        : (rawCount is int ? rawCount : 0);
    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : (accountId.isNotEmpty ? accountId[0].toUpperCase() : 'U');
    final isBusy = _busyAccountId == accountId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFEFF6FF)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF2563EB)
              : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openUserSheet(user),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                alignment: Alignment.center,
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              // Info Group
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            displayName.isEmpty ? 'User ($accountId)' : displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(isSuspended),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$devicesCount Device${devicesCount == 1 ? '' : 's'} Connected • Joined $joined',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFF94A3B8),
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
    final inviteId = user['invite_id'] as String? ?? '';
    final phone = _formatPhone(user);
    final status = user['status'] as String? ?? 'ACTIVE';
    final isSuspended = status == 'SUSPENDED';
    final isBusy = _busyAccountId == accountId;
    final joined = _formatTimestamp(user['created_at']);
    final rawDevices = user['devices'];
    final List<Map<String, dynamic>> devices = [];
    if (rawDevices is List) {
      for (final item in rawDevices) {
        if (item is Map) {
          devices.add(Map<String, dynamic>.from(item));
        }
      }
    }

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
              const SizedBox(height: 14),
              // The account id and the invite it was redeemed against.
              //
              // The redesign dropped both from view and left the account id
              // reachable only through "Copy User ID" - a button that copies a
              // value the operator can never read. These are the identifiers an
              // admin actually needs: the account id is what support asks for,
              // and the invite is how you tell which code let someone in.
              _identityRow(label: 'Account ID', value: accountId),
              if (inviteId.isNotEmpty)
                _identityRow(label: 'Redeemed invite', value: inviteId),
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
                    '${devices.where((d) => (d['status'] as String? ?? 'ACTIVE').toUpperCase() == 'ACTIVE').length} Active',
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phonelink_erase_outlined,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No connected devices. This account has not '
                          'registered a device on this server yet.',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
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
                            onPressed: isBusy
                                ? null
                                : () async {
                                    final deviceId = dev['device_id'] as String?;
                                    if (deviceId == null) return;
                                    setState(() {
                                      _busyAccountId = accountId;
                                      _error = null;
                                    });
                                    try {
                                      await widget.client.revokeDevice(
                                        accountId,
                                        deviceId,
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Device access revoked'),
                                        ),
                                      );
                                      await _loadUsers(offset: _offset);
                                    } catch (e) {
                                      if (!mounted) return;
                                      setState(() => _error = e.toString());
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busyAccountId = null);
                                      }
                                    }
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.key, size: 15),
                      label: const Text('Issue 48h Key', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: () => _issueRecoveryCode(accountId, displayName.isEmpty ? accountId : displayName),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Copy User ID', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: accountId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account ID copied')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD97706),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                            )
                          : Icon(isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline, size: 15),
                      label: Text(
                        isSuspended ? 'Restore' : 'Suspend',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: isBusy ? null : () => isSuspended ? _unsuspend(accountId) : _suspend(accountId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 15),
                      label: const Text('Delete Data', style: TextStyle(fontSize: 12)),
                      onPressed: () => _confirmDelete(accountId, displayName.isEmpty ? accountId : displayName),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF991B1B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.block, size: 15),
                label: const Text('Permanent Block Phone', style: TextStyle(fontSize: 12)),
                onPressed: () => _confirmBlock(accountId, displayName.isEmpty ? accountId : displayName),
              ),
            ],
          ),
        ),

        if (inSheet) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: const Color(0xFF2563EB))
              : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  /// A labelled identifier in the detail pane.
  ///
  /// Monospaced and selectable: these are values an operator reads out or
  /// pastes into a support ticket, so wrapping them mid-token would make them
  /// wrong to copy by hand.
  Widget _identityRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool isSuspended) {    final bg = isSuspended ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final fg = isSuspended ? const Color(0xFFDC2626) : const Color(0xFF059669);
    final border = isSuspended ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        isSuspended ? 'SUSPENDED' : 'ACTIVE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatPhone(Map<String, dynamic> user) {
    final rawPhone = user['phone'] as String? ??
        user['phone_number'] as String? ??
        user['phone_last4'] as String? ??
        user['mobile'] as String?;
    if (rawPhone == null || rawPhone.trim().isEmpty) return '—';
    return rawPhone.trim();
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
