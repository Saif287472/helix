import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin_client.dart';
import '../theme/app_theme.dart';

/// Registered-user directory and per-user access controls. Locked like
/// Dashboard/Config/Invites until a server is connected.
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

  @override
  void initState() {
    super.initState();
    _loadUsers();
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
          content: Column(
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
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '• Single-use only\n• Expires in 48 hours\n• Lost/old devices will be revoked',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
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
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  /// Deletes the account like [_confirmDelete], and additionally bans its
  /// phone number so it can never register again on this server - distinct
  /// from a plain delete, which leaves the number free for a fresh account.
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
      await _loadUsers(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: HelixInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Users',
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
                'Everyone registered on this server, and who invited them.',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
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
              else
                _buildTable(),
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

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Display Name')),
          DataColumn(label: Text('Account ID')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Invite Used')),
          DataColumn(label: Text('Joined')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _users.map((user) {
          final accountId = user['account_id'] as String? ?? '';
          final status = user['status'] as String? ?? 'ACTIVE';
          final isSuspended = status == 'SUSPENDED';
          final isBusy = _busyAccountId == accountId;
          final displayName = user['display_name'] as String? ?? '';
          return DataRow(
            cells: [
              DataCell(Text(displayName.isEmpty ? '—' : displayName)),
              DataCell(Text(accountId)),
              DataCell(Text(_maskedPhone(user['phone_last4'] as String?))),
              DataCell(Text(user['invite_id'] as String? ?? '—')),
              DataCell(Text(_formatTimestamp(user['created_at']))),
              DataCell(_statusChip(isSuspended)),
              DataCell(
                isBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.key_outlined),
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
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _statusChip(bool isSuspended) {
    final color = isSuspended ? Colors.orange : Colors.green;
    return Chip(
      label: Text(
        isSuspended ? 'SUSPENDED' : 'ACTIVE',
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color),
    );
  }

  /// The server only ever stores the last 2-4 digits (see
  /// AuthRegistrationHandlers) - there's no full phone number to unmask,
  /// this is simply how that hint is displayed.
  String _maskedPhone(String? last4) {
    if (last4 == null || last4.isEmpty) return '—';
    return '•••• $last4';
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
