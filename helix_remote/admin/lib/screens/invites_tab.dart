import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import '../admin_client.dart';
import '../helix_code.dart';
import '../theme/app_theme.dart';

/// Invite-credential issuance and audit history.
/// Converted to mobile-first cardlet and touch-card system from the Helix Admin demo.
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
  String? _lastShareableCode;
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
        _lastShareableCode = _resolveShareableCode(result);
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

  String _resolveShareableCode(Map<String, dynamic> result) {
    final shareableCode = result['shareable_code'] as String?;
    if (shareableCode != null && isHelixInviteCode(shareableCode)) {
      return shareableCode;
    }
    final inviteCode = result['invite_code'] as String;
    final base = widget.client.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return encodeHelixInviteCode(serverUrl: base, inviteCode: inviteCode);
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Generator Cardlet
          Card(
            child: Padding(
              padding: HelixInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Invitation System',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Single-Use (7 Days)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: context.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Generate single-use shielded invite codes for onboarding new users.',
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
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: HelixInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_lastShareableCode != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: HelixInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.sunkenSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: context.accentColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Latest Generated Invite Code',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _lastShareableCode!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: context.accentColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Copy code',
                            onPressed: () => _copyToClipboard(_lastShareableCode!),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
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
          const SizedBox(height: 20),

          // Invites List Card
          Card(
            child: Padding(
              padding: HelixInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Active & Recent Invites',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reload invites',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => _loadInvites(offset: _offset),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Audit trail of issued invites, redemption states, and expiration.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_invites.isEmpty)
                    Padding(
                      padding: HelixInsets.all(24),
                      child: Text(
                        'No invites issued yet.',
                        style: TextStyle(color: context.textFaint),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final invite in _invites) _buildInviteCard(invite),
                      ],
                    ),
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

  Widget _buildInviteCard(Map<String, dynamic> invite) {
    final inviteId = invite['invite_id'] as String? ?? '';
    final status = invite['status'] as String? ?? 'unknown';
    final isPending = status == 'PENDING';
    final isBusy = _busyInviteId == inviteId;
    final isRedeemed = status == 'REDEEMED';
    final redeemedBy = invite['redeemed_by_account_id'] as String?;
    final issuer = invite['issuer_type'] as String? ?? 'ADMIN';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.sunkenSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          // Icon Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isRedeemed
                  ? Colors.green.withValues(alpha: 0.15)
                  : (isPending
                      ? context.accentColor.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRedeemed
                  ? Icons.check
                  : (isPending ? Icons.local_activity_outlined : Icons.close),
              size: 20,
              color: isRedeemed
                  ? Colors.green
                  : (isPending ? context.accentColor : Colors.red),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      inviteId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      issuer,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isRedeemed && redeemedBy != null
                      ? 'Redeemed by $redeemedBy • ${_formatTimestamp(invite['redeemed_at'] ?? invite['created_at'])}'
                      : 'Issued ${_formatTimestamp(invite['created_at'])} • Expires ${_formatTimestamp(invite['expires_at'])}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Status & Action
          _statusChip(status),
          const SizedBox(width: 8),

          if (isBusy)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (isPending)
            IconButton(
              icon: Icon(
                Icons.cancel_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: 'Cancel invite',
              onPressed: () => _cancelInvite(inviteId),
            ),
        ],
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
      case 'CANCELLED':
        color = Colors.red;
      default:
        color = context.accentColor;
    }
    return Chip(
      label: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      padding: EdgeInsets.zero,
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
