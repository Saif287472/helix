import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/forward_targets.dart';
import 'package:helix_remote/features/conversation/application/message_actions.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Pick the chats (and people) to forward messages to, then send. The
/// messages are the database ids in [rowids], from the conversation
/// [conversationId].
class ForwardScreen extends ConsumerStatefulWidget {
  const ForwardScreen({
    super.key,
    required this.conversationId,
    required this.rowids,
  });

  final String conversationId;
  final List<int> rowids;

  @override
  ConsumerState<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends ConsumerState<ForwardScreen> {
  final TextEditingController _query = TextEditingController();
  final Set<String> _picked = {};
  bool _sending = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _send(List<ForwardTarget> all) async {
    setState(() => _sending = true);
    final chosen = [
      for (final t in all)
        if (_picked.contains(t.id)) t,
    ];
    final failed = await ref
        .read(conversationActionsProvider(widget.conversationId))
        .forward(
          widget.rowids,
          [
            for (final t in chosen)
              if (t.newPeer == null) t.id,
          ],
          peersToOpen: [
            for (final t in chosen)
              if (t.newPeer != null) t.newPeer!,
          ],
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0 ? 'Forwarded' : 'Some messages could not be forwarded',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(forwardTargetsProvider);
    final all = targets.value ?? const <ForwardTarget>[];
    final needle = _query.text.trim().toLowerCase();
    final shown = needle.isEmpty
        ? all
        : [
            for (final t in all)
              if (t.title.toLowerCase().contains(needle)) t,
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rowids.length == 1
              ? 'Forward message'
              : 'Forward ${widget.rowids.length} messages',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(HelixSpace.sm),
            child: HelixSearchField(
              controller: _query,
              hint: 'Search chats and people',
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: targets.value == null
                ? (targets.hasError
                      ? const HelixErrorState(
                          message: 'Your chats could not be loaded.',
                        )
                      : const Center(child: CircularProgressIndicator()))
                : shown.isEmpty
                ? HelixNoResults(query: _query.text)
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final target = shown[index];
                      final picked = _picked.contains(target.id);
                      return CheckboxListTile(
                        key: ValueKey(target.id),
                        value: picked,
                        onChanged: (_) => setState(() {
                          if (!_picked.remove(target.id)) {
                            _picked.add(target.id);
                          }
                        }),
                        secondary: HelixAvatar(
                          model: target.avatar,
                          size: HelixAvatarSize.md,
                        ),
                        title: Text(
                          target.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(HelixSpace.sm),
                child: FilledButton.icon(
                  onPressed: _sending ? null : () => _send(all),
                  icon: const Icon(Icons.send),
                  label: Text(
                    _picked.length == 1
                        ? 'Send to 1 chat'
                        : 'Send to ${_picked.length} chats',
                  ),
                ),
              ),
            ),
    );
  }
}
