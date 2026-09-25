import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:share_plus/share_plus.dart';
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

  String? get _effectiveCode {
    if (_lastShareableCode != null && _lastShareableCode!.isNotEmpty) {
      return _lastShareableCode;
    }
    if (_invites.isNotEmpty) {
      final firstPending = _invites.firstWhere(
        (inv) => (inv['status'] as String? ?? '').toUpperCase() == 'PENDING',
        orElse: () => _invites.first,
      );
      return _resolveShareableCode(firstPending);
    }
    return null;
  }

  String _resolveShareableCode(Map<String, dynamic> result) {
    final shareableCode = result['shareable_code'] as String?;
    if (shareableCode != null && isHelixInviteCode(shareableCode)) {
      return shareableCode;
    }
    final inviteCode = result['invite_code'] as String? ?? result['invite_id'] as String? ?? '';
    if (isHelixInviteCode(inviteCode)) {
      return inviteCode;
    }
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

  void _shareInvite(String code) {
    // ignore: deprecated_member_use
    Share.share(
      'Join my personal server using invite code: $code',
      subject: 'Helix Personal Server Invite',
    );
  }

  String _truncateCodeDisplay(String code) {
    if (code.length <= 22) return code;
    return '${code.substring(0, 18)}...';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCode = _effectiveCode;

    return RefreshIndicator(
      onRefresh: () => _loadInvites(offset: 0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Page Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Invitation System',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  onPressed: _generating ? null : _generateInvite,
                  icon: _generating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add, size: 20),
                  tooltip: 'Create Invite',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Latest Generated Invite Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Latest Generated Invite',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: effectiveCode != null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _truncateCodeDisplay(effectiveCode),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF2563EB),
                                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                                      padding: const EdgeInsets.all(8),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => _copyToClipboard(effectiveCode),
                                    child: const Icon(Icons.copy, size: 16),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF334155),
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      padding: const EdgeInsets.all(8),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => _shareInvite(effectiveCode),
                                    child: const Icon(Icons.share, size: 16),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const Text(
                            'Tap "+" to generate a fresh secure onboarding token.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ),
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
          const SizedBox(height: 20),

          // Invites List Area
          const Text(
            'Active & Recent Invites',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

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
  );
}

  Widget _buildInviteCard(Map<String, dynamic> invite) {
    final inviteId = invite['invite_id'] as String? ?? '';
    final status = (invite['status'] as String? ?? 'PENDING').toUpperCase();
    final isPending = status == 'PENDING';
    final isBusy = _busyInviteId == inviteId;
    final isRedeemed = status == 'REDEEMED';
    final isCancelled = status == 'CANCELLED';
    final redeemedBy = invite['redeemed_by_account_id'] as String?;
    final issuer = invite['issuer_type'] as String? ?? 'Master Admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Icon Avatar Circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isRedeemed
                  ? const Color(0xFFECFDF5)
                  : (isPending
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFFEF2F2)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRedeemed
                  ? Icons.check
                  : (isPending ? Icons.local_activity_outlined : Icons.close),
              size: 20,
              color: isRedeemed
                  ? const Color(0xFF059669)
                  : (isPending ? const Color(0xFF2563EB) : const Color(0xFFDC2626)),
            ),
          ),
          const SizedBox(width: 12),

          // Info Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inviteId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isRedeemed && redeemedBy != null
                      ? 'Redeemed by $redeemedBy'
                      : (isCancelled
                          ? 'Cancelled by Admin'
                          : 'Issued by $issuer • Expires in 6 days'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isRedeemed
                      ? 'Redeemed ${_formatTimestamp(invite['redeemed_at'] ?? invite['created_at'])}'
                      : 'Created ${_formatTimestamp(invite['created_at'])}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Status Badge & Action
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statusChip(status),
              if (isBusy) ...[
                const SizedBox(height: 6),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ] else if (isPending) ...[
                const SizedBox(height: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _cancelInvite(inviteId),
                  child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final Color bg;
    final Color fg;
    final Color border;
    switch (status) {
      case 'REDEEMED':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        border = const Color(0xFFA7F3D0);
      case 'EXPIRED':
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFD97706);
        border = const Color(0xFFFDE68A);
      case 'CANCELLED':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        border = const Color(0xFFFCA5A5);
      default: // PENDING
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFD97706);
        border = const Color(0xFFFDE68A);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
