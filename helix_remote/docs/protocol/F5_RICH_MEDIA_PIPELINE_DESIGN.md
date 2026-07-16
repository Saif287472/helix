# F5 Rich Media Pipeline Design

Status: completed locally on 2026-06-25.

F5 reuses the encrypted attachment pipeline and adds typed message content for
voice notes, instant video notes, captioned media, scanned documents, camera
captures, Live Photo style packages, and media collections.

## Content Envelopes

All rich media is sent inside the authenticated
`helix.remote.content-envelope.v1` wrapper. New content types are:

- `helix.remote.content.voice-note.v1`
- `helix.remote.content.instant-video.v1`
- `helix.remote.content.media-with-caption.v1`
- `helix.remote.content.media-collection.v1`

Each payload carries an encrypted attachment manifest, key-delivery secret,
optional encrypted thumbnail manifest, optional caption, local waveform
samples, duration, media kind, view-once policy, and collection item metadata.
The server continues to see opaque ciphertext and attachment object references,
not captions, waveform data, or draft content.

## Drafts And Cleanup

Local storage schema v18 adds:

- `media_drafts` for interrupted voice/video/camera/scanner composition.
- `media_playback_state` for shared playback position and 1x/1.5x/2x speed.
- `media_transfer_policy` for background, retry, expiry, and integrity UX.

Cancelling a draft removes the draft row and deletes the local temporary media
file when present. View-once voice notes use the same F3 view-once metadata and
tombstone consumption flow as other ephemeral content.

## Composer And Playback

The existing attachment composer now sends through the rich-media envelope and
collects media kind, caption, and view-once intent before enqueueing. Message
bubbles render media type, duration, and local waveform metadata while preserving
reply, reaction, download, and export actions.

Playback state is centralized in `RemoteMessagingService` so in-chat and
out-of-chat surfaces can share the same persisted position and speed contract.

## Compatibility

Clients advertise:

- `helix.remote.rich-media-pipeline.v1`
- `helix.remote.content.voice-note.v1`
- `helix.remote.content.instant-video.v1`
- `helix.remote.content.media-with-caption.v1`
- `helix.remote.content.media-collection.v1`
- `helix.remote.local-storage-schema.v18`

Older clients that understand only attachments can still ignore unknown content
types without server-side plaintext exposure. New clients continue to parse
legacy `helix.remote.attachment.v1` and `helix.remote.content.attachment.v1`
messages.
