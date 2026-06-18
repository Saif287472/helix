part of 'chat_screen.dart';

class _TimestampDivider extends StatelessWidget {
  const _TimestampDivider({required this.timestamp});
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final label = _formatDayLabel(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Semantics(
        label: 'Message date $label',
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  String _formatDayLabel(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final suffix = switch (local.day) {
      11 || 12 || 13 => 'th',
      _ when local.day % 10 == 1 => 'st',
      _ when local.day % 10 == 2 => 'nd',
      _ when local.day % 10 == 3 => 'rd',
      _ => 'th',
    };
    final base = '${local.day}$suffix ${months[local.month - 1]}';
    return local.year == now.year ? base : '$base ${local.year}';
  }
}

class _MessageSendAnimation extends StatefulWidget {
  const _MessageSendAnimation({required this.messageId, required this.child});

  final String messageId;
  final Widget child;

  @override
  State<_MessageSendAnimation> createState() => _MessageSendAnimationState();
}

class _MessageSendAnimationState extends State<_MessageSendAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = Tween<double>(
      begin: 0.92,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

// ---------------------------------------------------------------------------
// Typing bubble
// ---------------------------------------------------------------------------

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.peerInitial});
  final String peerInitial;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _dots;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _dots = List.generate(3, (i) {
      final start = i * 0.2;
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, start + 0.4, curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 28,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                widget.peerInitial,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: HelixTheme.remoteBubbleColor(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _dots[i],
                  builder: (ctx, child) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 7,
                      height: 7 + _dots[i].value * 3,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withAlpha(
                          (80 + (_dots[i].value * 120).round()).clamp(0, 255),
                        ),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reply bar
// ---------------------------------------------------------------------------

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onDismiss});
  final ChatMessage message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.origin == MessageOrigin.local ? 'You' : 'Peer',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  message.isDeleted
                      ? '(deleted)'
                      : (message.isFile
                            ? '📎 ${message.fileName ?? message.text}'
                            : message.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text composer
// ---------------------------------------------------------------------------

class _SendComposerIntent extends Intent {
  const _SendComposerIntent();
}

enum _AttachChoice { file, privateMedia }

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.disabled,
    required this.bytesRemaining,
    required this.sending,
    required this.canSend,
    required this.onSend,
    required this.onChanged,
    this.onAttach,
    this.onAttachPrivateMedia,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool disabled;
  final int bytesRemaining;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onAttachPrivateMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nearLimit = bytesRemaining < 280;
    final overLimit = bytesRemaining < 0;

    final composer = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onAttach != null || onAttachPrivateMedia != null)
            PopupMenuButton<_AttachChoice>(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Share',
              onSelected: (choice) {
                if (choice == _AttachChoice.file) onAttach?.call();
                if (choice == _AttachChoice.privateMedia) {
                  onAttachPrivateMedia?.call();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _AttachChoice.file,
                  child: const ListTile(
                    leading: Icon(Icons.attach_file),
                    title: Text('Send File'),
                    subtitle: Text('Saved to recipient\'s device'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: _AttachChoice.privateMedia,
                  child: const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('Send Private Media'),
                    subtitle: Text('RAM-only · never written to disk'),
                    dense: true,
                  ),
                ),
              ],
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !disabled,
                  maxLines: 6,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: disabled
                        ? 'Disconnected — cannot send messages.'
                        : 'Message',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  onChanged: onChanged,
                ),
                if (nearLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Text(
                      overLimit
                          ? '${-bytesRemaining} bytes over limit'
                          : '$bytesRemaining bytes remaining',
                      style: TextStyle(
                        fontSize: 10,
                        color: overLimit
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: canSend ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: IconButton.filled(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(44, 44),
              ),
              onPressed: canSend ? onSend : null,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );

    if (!isDesktop) return composer;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): _SendComposerIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _SendComposerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SendComposerIntent: CallbackAction<_SendComposerIntent>(
            onInvoke: (_) {
              if (canSend) onSend();
              return null;
            },
          ),
        },
        child: composer,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Warning banner
// ---------------------------------------------------------------------------

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
