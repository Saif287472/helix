part of '../message_tile.dart';

/// Structured renderers for the non-text message content types.
///
/// These four arrive as an encoded [RemoteMessageContentEnvelope] in
/// [RemoteDecryptedMessage.text]. Before this existed they fell through to the
/// plain `Text` branch, so a poll rendered as its own JSON - the question,
/// every option and the payload keys, as one run of base64-ish text. Nothing
/// was lost, because the envelope is what the sender wrote; it just was not
/// readable.
///
/// Every card here is read-only. Voting, RSVP-ing, sending a location and
/// picking a sticker all need a send path and a server route, and those are
/// deferred along with the rest of the rich-content work. A card that looked
/// tappable but did nothing would be worse than one that plainly does not
/// offer the action, so nothing here implies interactivity it does not have.

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

/// Picks the card for [message], or null when it is ordinary plain text.
///
/// Reads the typed fields [RemoteDecryptedMessage] already carries rather than
/// re-decoding `text`. The service populates all four while reading history -
/// `remote_messaging_service_test.dart` asserts it - so the envelope has
/// already been parsed once by the time a tile is built, and parsing it again
/// per build would both duplicate that work and mean the tile and the service
/// could disagree about what a message is.
class _RichContent {
  const _RichContent.poll(this.poll)
    : event = null,
      location = null,
      sticker = null;
  const _RichContent.event(this.event)
    : poll = null,
      location = null,
      sticker = null;
  const _RichContent.location(this.location)
    : poll = null,
      event = null,
      sticker = null;
  const _RichContent.sticker(this.sticker)
    : poll = null,
      event = null,
      location = null;

  final RemotePollContent? poll;
  final RemoteEventContent? event;
  final RemoteLocationContent? location;
  final RemoteStickerContent? sticker;

  static _RichContent? resolve(RemoteDecryptedMessage message) {
    if (message.poll case final poll?) return _RichContent.poll(poll);
    if (message.event case final event?) return _RichContent.event(event);
    if (message.location case final location?) {
      return _RichContent.location(location);
    }
    if (message.sticker case final sticker?) return _RichContent.sticker(sticker);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

/// The card frame every rich body sits in.
///
/// A tinted surface with an accent stripe, so a poll is distinguishable from
/// a text bubble at a glance without relying on the icon alone.
class _RichCard extends StatelessWidget {
  const _RichCard({
    required this.accent,
    required this.icon,
    required this.label,
    required this.child,
    this.dimmed = false,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final Widget child;

  /// Rendered greyed out - used for a cancelled event, so the state is visible
  /// rather than the card simply disappearing from history.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effective = dimmed ? cs.onSurfaceVariant : accent;

    return Container(
      width: double.maxFinite,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: effective.withAlpha(60)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: effective),
            Expanded(
              child: Padding(
                padding: HelixInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: effective),
                        const SizedBox(width: HelixSpace.xs),
                        Text(
                          label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: effective,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Poll
// ---------------------------------------------------------------------------

class _PollCard extends StatelessWidget {
  const _PollCard({required this.poll});

  final RemotePollContent poll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = HelixLocalizations.of(context);
    final closed = poll.isClosed;

    return _RichCard(
      accent: HelixColorTokens.cFF7C3AED,
      icon: Icons.poll_outlined,
      label: closed
          ? l10n.pollClosedLabel
          : l10n.pollLabel,
      dimmed: closed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            poll.question,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          // Options are listed, not shown with bars. There is no vote data on
          // this message - results are a separate concept the server does not
          // attach - so any bar chart here would be invented numbers.
          ...poll.options.map(
            (option) => Padding(
              padding: HelixInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: HelixInsets.only(top: 6, right: 8),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      option.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (poll.options.isEmpty)
            Text(
              l10n.pollNoOptions,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (poll.allowMultipleVotes)
            Padding(
              padding: HelixInsets.only(top: 4),
              child: Text(
                l10n.pollMultipleChoices,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event
// ---------------------------------------------------------------------------

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final RemoteEventContent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = HelixLocalizations.of(context);

    return _RichCard(
      accent: HelixColorTokens.cFF0EA5E9,
      icon: Icons.event_outlined,
      label: event.isCancelled
          ? l10n.eventCancelledLabel
          : l10n.eventLabel,
      dimmed: event.isCancelled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _EventRow(
            icon: Icons.schedule,
            // The sender's own timezone is carried in the payload. Rendering it
            // is the point of the field: an event time converted to the
            // reader's zone would be a different time from the one the sender
            // agreed to.
            text: '${_formatEventTime(event.startsAt)}'
                '${event.timeZone.isEmpty ? '' : ' ${event.timeZone}'}',
          ),
          if (event.locationText.isNotEmpty)
            _EventRow(icon: Icons.place_outlined, text: event.locationText),
          if (event.plusOneAllowed)
            _EventRow(
              icon: Icons.group_add_outlined,
              text: l10n.eventPlusOnes,
            ),
        ],
      ),
    );
  }

  static String _formatEventTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.hour >= 12 ? 'PM' : 'AM';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year} $h:$m $s';
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: HelixInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location});

  final RemoteLocationContent location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = HelixLocalizations.of(context);
    final lat = location.latitudeE7 / 1e7;
    final lon = location.longitudeE7 / 1e7;
    final stopped = location.stoppedAt != null && location.stoppedAt! > 0;

    return _RichCard(
      accent: HelixColorTokens.cFF14B8A6,
      icon: location.live && !stopped
          ? Icons.location_searching
          : Icons.place_outlined,
      label: location.live && !stopped
          ? l10n.liveLocationLabel
          : l10n.locationLabel,
      dimmed: location.live && stopped,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (location.label.isNotEmpty)
            Text(
              location.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          // Coordinates to seven decimals is the wire format; four is what a
          // person can read, and the extra digits are noise in a chat bubble.
          _EventRow(icon: Icons.my_location, text: '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}'),
          _EventRow(
            icon: Icons.straighten,
            text: location.accuracyMeters > 0
                ? 'Accurate to ${location.accuracyMeters} m'
                : l10n.locationAccuracyUnknown,
          ),
          if (location.live && stopped)
            _EventRow(icon: Icons.history, text: l10n.locationSharingStopped),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticker
// ---------------------------------------------------------------------------

class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker, this.onDownload});

  final RemoteStickerContent sticker;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = HelixLocalizations.of(context);

    // A sticker is an attachment, so the download action is the same one the
    // attachment card already offers. It is wired here rather than left inert
    // because the transport exists and is identical.
    final mime = sticker.attachment.mimeType;
    final isImage = mime.startsWith('image/');
    final isVideo = mime.startsWith('video/');

    return _RichCard(
      accent: HelixColorTokens.cFFE91E63,
      icon: Icons.emoji_emotions_outlined,
      label: l10n.stickerLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // No preview widget: fetching and decoding the bytes needs an
          // attachment cache, and rendering a broken box would be worse than
          // naming the sticker. The alt text is the sender's own description,
          // so it is the honest thing to show in its place.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sticker.emoji.isNotEmpty) ...[
                Text(sticker.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sticker.altText.isNotEmpty
                          ? sticker.altText
                          : 'Sticker from ${sticker.packId}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontStyle: sticker.altText.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isImage
                          ? l10n.stickerImage
                          : isVideo
                          ? l10n.stickerVideo
                          : mime.isEmpty
                          ? l10n.stickerLabel
                          : mime,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onDownload != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onDownload!(),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(l10n.saveSticker),
                style: TextButton.styleFrom(
                  padding: HelixInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 36),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
