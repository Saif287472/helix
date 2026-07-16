# F9 Collaboration And Location Design

Status: completed locally on 2026-06-25.

F9 adds server-opaque collaboration content for polls, events, reminders, and
location sharing. All user-readable content remains inside the encrypted message
content envelope or local encrypted reminder/update rows.

## Content Types

New encrypted content envelope types:

- `helix.remote.content.poll.v1`
- `helix.remote.content.event.v1`
- `helix.remote.content.location.v1`

Poll payloads include question, options, creator, creation time, close state,
and single/multiple-vote policy. Event payloads include title, start/end,
timezone, location text, plus-one policy, pinning, cancellation state, and
attendee-list privacy. Location payloads support static location and live
location session bootstrap with explicit expiry.

## Local State

Local storage schema v21 adds:

- `poll_votes`: one idempotent vote row per poll/account, replacing older votes.
- `event_rsvps`: one idempotent RSVP row per event/account.
- `event_reminders`: encrypted local reminder notes and due scheduling.
- `live_location_sessions`: explicit active/stopped/expired lifecycle.
- `live_location_updates`: encrypted periodic live-location updates.

Poll results and RSVP summaries aggregate locally from encrypted event state, so
the server does not need plaintext questions, options, attendee notes, or
location details.

## Live Location

Live location sessions have duration and update interval controls. Updates are
rate-limited by `update_interval_ms`, can be stopped immediately, and expire
automatically. Expired sessions can be excluded from search/backup by checking
session lifecycle state before indexing/export.

Map provider behavior is intentionally local-policy driven: Helix stores only
coordinates and labels in encrypted content, and no participant/chat context is
sent to a map provider by the collaboration layer.

## Compatibility

Clients advertise:

- `helix.remote.collaboration-content.v1`
- `helix.remote.content.poll.v1`
- `helix.remote.content.event.v1`
- `helix.remote.content.location.v1`
- `helix.remote.local-storage-schema.v21`

Older clients ignore unknown collaboration content types and continue to process
ordinary messages without server-side plaintext exposure.
