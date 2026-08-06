part of '../conversation_list_screen.dart';

class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
    this.request,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onRemove,
  });

  final RemoteContact contact;
  final RemoteContactRequest? request;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = contact.nickname.isNotEmpty
        ? contact.nickname
        : contact.peerAccountId;

    Widget trailing = const SizedBox.shrink();
    if (contact.status == 'PendingReceived' &&
        onAccept != null &&
        onReject != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Accept request',
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: onAccept,
          ),
          IconButton(
            tooltip: 'Reject request',
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            onPressed: onReject,
          ),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    } else if (contact.status == 'PendingSent' && onCancel != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    } else if (contact.status == 'Accepted') {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Avatar(name: name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onRemove});
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.person_remove_outlined, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove contact', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared avatar widget with color-coded initials
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 48});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFF00BCD4),
    Color(0xFF795548),
  ];

  Color _color() => _palette[name.hashCode.abs() % _palette.length];

  String _initials() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _color(),
      child: Text(
        _initials(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact picker bottom sheet for "New chat"
// ---------------------------------------------------------------------------

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});
  final List<RemoteContact> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteContact> get _filtered {
    if (_query.isEmpty) return widget.contacts;
    final q = _query.toLowerCase();
    return widget.contacts.where((c) {
      return c.nickname.toLowerCase().contains(q) ||
          c.peerAccountId.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'New chat',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search contacts…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 4),
            // Contact list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.contacts.isEmpty
                            ? 'No contacts yet.\nAdd contacts from the Contacts tab.'
                            : 'No contacts match "$_query"',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final contact = filtered[i];
                        final name = contact.nickname.isNotEmpty
                            ? contact.nickname
                            : contact.peerAccountId;
                        return ListTile(
                          leading: _Avatar(name: name, size: 44),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: contact.nickname.isNotEmpty
                              ? Text(
                                  contact.peerAccountId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () =>
                              Navigator.of(context).pop(contact.peerAccountId),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Connection status banner (reused across screens)
// ---------------------------------------------------------------------------
