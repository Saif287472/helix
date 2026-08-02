import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin_client.dart';
import '../theme/app_theme.dart';

/// Invite-credential issuance and audit history. Locked like Dashboard/
/// Config until a server is connected. Generated codes are clipboard-only
/// for v1 (decision: no new share_plus dependency) and shown exactly once,
/// since the server never persists the raw code - only its hash.
class InvitesTab extends StatefulWidget {
  const InvitesTab({super.key, required this.client});

  final AdminClient client;

  @override
  State<InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<InvitesTab> {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _invites = [];
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _generating = false;
  String? _error;
  String? _lastShareableUrl;
  String? _busyInviteId;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites({int offset = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.listInvites(
        limit: _pageSize,
        offset: offset,
      );
      final invites = (result['invites'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _offset = offset;
        _hasMore = invites.length == _pageSize;
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

  Future<void> _generateInvite() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await widget.client.createInvite();
      if (!mounted) return;
      setState(() {
        _lastShareableUrl = _resolveShareableUrl(result);
        _generating = false;
      });
      await _loadInvites(offset: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  /// The server includes `shareable_url`, but it's only a full link when
  /// HELIX_REMOTE_PUBLIC_BASE_URL was set at deploy time - a step many
  /// self-hosters miss, which otherwise leaves it schemeless/host-less
  /// (e.g. `/join?invite=CODE`, unusable when pasted elsewhere). Fall back
  /// to building the link from the address this admin console is already
  /// connected to, which is always a real, reachable URL.
  String _resolveShareableUrl(Map<String, dynamic> result) {
    final serverUrl = result['shareable_url'] as String?;
    if (serverUrl != null &&
        (serverUrl.startsWith('http://') ||
            serverUrl.startsWith('https://'))) {
      return serverUrl;
    }
    final inviteCode = result['invite_code'] as String;
    final base = widget.client.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/join?invite=$inviteCode';
  }

  Future<void> _cancelInvite(String inviteId) async {
    setState(() => _busyInviteId = inviteId);
    try {
      await widget.client.cancelInvite(inviteId);
      await _loadInvites(offset: _offset);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyInviteId = null);
    }
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Generate Invite',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Single-use, expires in 7 days. The code is shown once '
                    '- copy it now.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _generating ? null : _generateInvite,
                    icon: _generating
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_link),
                    label: Text(
                      _generating ? 'Generating…' : 'Generate Invite',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2BE2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  if (_lastShareableUrl != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.sunkenSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.accentColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _lastShareableUrl!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: context.accentColor,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy link',
                            onPressed: () =>
                                _copyToClipboard(_lastShareableUrl!),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Invite History',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => _loadInvites(offset: _offset),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_invites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No invites issued yet.',
                        style: TextStyle(color: context.textFaint),
                      ),
                    )
                  else
                    _buildTable(),
                  if (!_loading && (_invites.isNotEmpty || _offset > 0)) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: const Key('invites_previous_page'),
                          onPressed: _offset > 0
                              ? () => _loadInvites(
                                  offset: (_offset - _pageSize).clamp(
                                    0,
                                    1 << 30,
                                  ),
                                )
                              : null,
                          child: const Text('Previous'),
                        ),
                        TextButton(
                          key: const Key('invites_next_page'),
                          onPressed: _hasMore
                              ? () => _loadInvites(offset: _offset + _pageSize)
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
        ],
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Issuer')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Issued')),
          DataColumn(label: Text('Expires')),
          DataColumn(label: Text('Redeemed By')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _invites.map((invite) {
          final inviteId = invite['invite_id'] as String? ?? '';
          final status = invite['status'] as String? ?? 'unknown';
          final isPending = status == 'PENDING';
          final isBusy = _busyInviteId == inviteId;
          return DataRow(
            cells: [
              DataCell(Text(invite['issuer_type'] as String? ?? 'unknown')),
              DataCell(_statusChip(status)),
              DataCell(Text(_formatTimestamp(invite['created_at']))),
              DataCell(Text(_formatTimestamp(invite['expires_at']))),
              DataCell(
                Text(invite['redeemed_by_account_id'] as String? ?? '—'),
              ),
              DataCell(
                isBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : isPending
                    ? IconButton(
                        icon: Icon(
                          Icons.cancel_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        tooltip: 'Cancel invite',
                        onPressed: () => _cancelInvite(inviteId),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _statusChip(String status) {
    final Color color;
    switch (status) {
      case 'REDEEMED':
        color = Colors.green;
      case 'EXPIRED':
        color = Colors.orange;
      default:
        color = context.accentColor;
    }
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)} '
        '${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
