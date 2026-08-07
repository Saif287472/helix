part of '../calls_tab_screen.dart';

class _NewCallSheet extends StatefulWidget {
  const _NewCallSheet({required this.contacts, required this.onCall});

  final List<RemoteContact> contacts;
  final void Function(
    String peerId, {
    required bool isVideo,
    String? peerDisplayName,
  })
  onCall;

  @override
  State<_NewCallSheet> createState() => _NewCallSheetState();
}

class _NewCallSheetState extends State<_NewCallSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _query.isEmpty
        ? widget.contacts
        : widget.contacts.where((c) {
            final nick = c.nickname.toLowerCase();
            final id = c.peerAccountId.toLowerCase();
            return nick.contains(_query) || id.contains(_query);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            Padding(
              padding: HelixInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: HelixInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    HelixLocalizations.of(context).newCall,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: HelixInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: HelixInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(height: 4),
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
                          leading: _InitialAvatar(name: name, size: 44),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: contact.nickname.isNotEmpty
                              ? Text(
                                  contact.peerAccountId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.videocam_outlined),
                            tooltip: 'Video call',
                            onPressed: () => widget.onCall(
                              contact.peerAccountId,
                              isVideo: true,
                              peerDisplayName: name,
                            ),
                          ),
                          onTap: () => widget.onCall(
                            contact.peerAccountId,
                            isVideo: false,
                            peerDisplayName: name,
                          ),
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

class _CallHistoryRow {
  const _CallHistoryRow({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.identifier,
    required this.direction,
    required this.outcome,
    required this.isVideo,
    required this.timestamp,
    required this.dateTime,
    required this.timeLabel,
    required this.durationSeconds,
    required this.durationLabel,
    required this.mediaLabel,
    this.repeatCount = 1,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String identifier;
  final String direction;
  final String outcome;
  final bool isVideo;
  final int timestamp;
  final DateTime dateTime;
  final String timeLabel;
  final int durationSeconds;
  final String durationLabel;
  final String mediaLabel;
  final int repeatCount;

  bool get isMissed =>
      direction.toUpperCase() == kCallDirectionMissed ||
      outcome.toLowerCase().contains('missed');

  bool get isNotAnswered =>
      durationSeconds == 0 &&
      (direction.toUpperCase() == kCallDirectionOutgoing ||
          outcome.toLowerCase() == 'declined' ||
          outcome.toLowerCase() == 'failed' ||
          outcome.toLowerCase() == 'busy' ||
          outcome.toLowerCase() == 'ended');

  String get displayTitle =>
      repeatCount > 1 ? '$peerName ($repeatCount)' : peerName;

  _CallHistoryRow copyWith({int? repeatCount}) {
    return _CallHistoryRow(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      identifier: identifier,
      direction: direction,
      outcome: outcome,
      isVideo: isVideo,
      timestamp: timestamp,
      dateTime: dateTime,
      timeLabel: timeLabel,
      durationSeconds: durationSeconds,
      durationLabel: durationLabel,
      mediaLabel: mediaLabel,
      repeatCount: repeatCount ?? this.repeatCount,
    );
  }

  String get directionLabel {
    if (isMissed) return 'Missed';
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => 'Outgoing',
      _ => 'Incoming',
    };
  }

  String get infoTitle {
    if (isMissed || isNotAnswered) return directionLabel;
    return directionLabel;
  }

  IconData get directionIcon {
    if (isMissed) return Icons.call_missed;
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => Icons.call_made,
      _ => Icons.call_received,
    };
  }
}

Color _avatarColor(String name, ColorScheme cs) {
  final colors = [
    cs.primaryContainer,
    cs.secondaryContainer,
    cs.tertiaryContainer,
    HelixColorTokens.cFFD7ECFF,
    HelixColorTokens.cFFFFE0CC,
    HelixColorTokens.cFFDFF6DE,
  ];
  return colors[name.hashCode.abs() % colors.length];
}

String _initials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
}
