part of '../contact_info_screen.dart';

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.name, required this.initial});

  final String name;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.initial,
    required this.onAvatarTap,
    required this.onAudio,
    required this.onVideo,
    required this.onSearch,
  });

  final String name;
  final String subtitle;
  final String initial;
  final VoidCallback onAvatarTap;
  final VoidCallback onAudio;
  final VoidCallback onVideo;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(30, 72, 30, 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 72,
              backgroundColor: cs.primaryContainer,
              child: Text(
                initial,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeaderAction(
                  icon: Icons.call_outlined,
                  label: 'Audio',
                  onTap: onAudio,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderAction(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: onVideo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderAction(
                  icon: Icons.search,
                  label: 'Search',
                  onTap: onSearch,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cs.primary, size: 29),
              const SizedBox(height: 7),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 260),
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'share', child: Text('Share profile')),
        PopupMenuItem(value: 'edit', child: Text('Edit nickname')),
        PopupMenuItem(value: 'verify', child: Text('Verify security code')),
      ],
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.color,
    required this.messages,
    required this.onOpen,
  });

  final Color color;
  final List<RemoteDecryptedMessage> messages;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      padding: const EdgeInsets.fromLTRB(30, 18, 0, 16),
      child: Column(
        children: [
          InkWell(
            onTap: messages.isEmpty ? null : onOpen,
            child: Padding(
              padding: const EdgeInsets.only(right: 22),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Media, links, and docs',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${messages.length}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 98,
            child: messages.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No shared media yet',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 22),
                    itemCount: messages.take(18).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) =>
                        _MediaThumb(message: messages[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.message, this.large = false});

  final RemoteDecryptedMessage message;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final attachment = message.media?.attachment ?? message.attachment;
    final path = attachment?.localPath;
    final isImage =
        attachment?.mimeType.startsWith('image/') == true &&
        path != null &&
        File(path).existsSync();
    final icon = switch (message.media?.kind) {
      RemoteMediaContent.videoKind => Icons.play_arrow_rounded,
      RemoteMediaContent.voiceNoteKind => Icons.mic,
      _ when attachment?.mimeType.startsWith('video/') == true =>
        Icons.play_arrow_rounded,
      _ when attachment?.mimeType.startsWith('image/') == true =>
        Icons.image_outlined,
      _ => Icons.description_outlined,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: large ? null : 116,
        height: large ? null : 98,
        color: cs.surfaceContainerHighest,
        child: isImage
            ? Image.file(File(path), fit: BoxFit.cover)
            : Center(child: Icon(icon, color: cs.onSurfaceVariant, size: 32)),
      ),
    );
  }
}
