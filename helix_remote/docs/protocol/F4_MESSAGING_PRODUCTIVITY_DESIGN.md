# F4 Messaging Productivity Design

Status: completed locally on 2026-06-25.

Phase F4 adds local-first chat organization and contact workflows without
uploading decrypted indexes or search terms.

## Local State

Local storage schema v17 adds:

- `conversation_read_state` for device-scoped last-read server sequence and
  mention count.
- `is_favorite` on conversations, plus `conversation_lists` and
  `conversation_list_members` for user-defined custom lists.
- `search_index` for decrypted message text, filenames, MIME types, link text,
  and conversation metadata. This table is local only and excluded from server
  sync contracts.
- `link_previews` for opt-in safe preview cache metadata.
- `contact_links` for expiring, replay-protected Helix contact links.

Unread state is derived from `messages.server_sequence >
conversation_read_state.last_read_sequence`. Opening a conversation records the
latest visible sequence and enqueues a synchronized mark-read operation.

## Search And Storage

`RemoteMessagingService.unifiedLocalSearch` hydrates decrypted history into the
local index and returns sectioned results for conversations, messages, media,
links, and documents. Locked hidden conversations stay excluded by the existing
privacy repository checks.

Per-chat storage summaries report attachment count, total bytes, downloaded
bytes, and large-file count. Clearing media replaces local attachment paths and
cache paths with a `MEDIA_CLEARED` state while preserving message rows and
tombstone history.

## Message Actions

Edits now enforce a 15-minute local window. Delete-for-everyone enforces a
two-day local window before writing tombstones and enqueueing deletion. Reaction
events use a stable per-message/per-account revision id so a sender replaces
their previous reaction instead of creating duplicates.

## Contact Links

The old `helix://add/...` string is replaced by
`helix://contact/add?v=1&id=...&a=...&n=...&e=...&s=...`.

Links include account id, nonce, expiry, and a service-generated signature.
The local database records issued link ids and rejects expired or replayed
links. The app shows the signed link as QR, supports camera scanning via
`mobile_scanner`, supports paste validation, and always asks for confirmation
before sending a contact request.

Display-name search remains privacy controlled by the backend, with minimum
query length, result caps, rate limits, discoverability opt-out, and no username
or phone exposure.

## Compatibility

Clients advertise:

- `helix.remote.messaging-productivity.v1`
- `helix.remote.local-search-index.v1`
- `helix.remote.contact-links.v1`
- `helix.remote.local-storage-schema.v17`

Older clients continue to render conversations and messages, but ignore local
favorites, custom lists, unread summaries, contact-link replay state, and local
search sections.
