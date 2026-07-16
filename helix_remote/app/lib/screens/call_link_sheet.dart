import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_domain/models.dart';

/// Bottom sheet for creating and sharing a call link.
class CallLinkSheet extends StatelessWidget {
  const CallLinkSheet({
    super.key,
    required this.link,
    this.onRevoke,
  });

  final CallLink link;
  final VoidCallback? onRevoke;

  static Future<void> show(
    BuildContext context, {
    required CallLink link,
    VoidCallback? onRevoke,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CallLinkSheet(link: link, onRevoke: onRevoke),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = link.linkToken;
    final expiresIn = link.expiresAt.difference(DateTime.now());
    final daysLeft = expiresIn.inDays;
    final expired = expiresIn.isNegative;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Call link',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (expired)
            const _Badge(label: 'Expired', color: Colors.red)
          else
            _Badge(
              label: daysLeft == 0 ? 'Expires today' : 'Expires in $daysLeft d',
              color: daysLeft <= 1 ? Colors.orange : Colors.green,
            ),
          if (link.requiresApproval) ...[
            const SizedBox(height: 4),
            const _Badge(label: 'Requires approval', color: Colors.blueGrey),
          ],
          if (link.maxUses > 0) ...[
            const SizedBox(height: 4),
            _Badge(
              label: '${link.useCount}/${link.maxUses} uses',
              color: link.isExhausted ? Colors.red : Colors.teal,
            ),
          ],
          const SizedBox(height: 20),
          // Token display + copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    token,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: token));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link token copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (onRevoke != null && !expired)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('Revoke link'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.of(context).pop();
                  onRevoke!();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
