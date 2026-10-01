# Helix Remote v2 — Encrypted Content

Status: **specified 2026-10-01 (Phase P1), pending user review.** Code:
`packages/helix_remote_protocol/lib/src/content/`.

Everything users exchange is a **content message**: a JSON object that is
padded and encrypted (CRYPTO_V2.md §5–7) before it leaves the device. The
server never sees any of it. This fixes the v1 split where reactions,
receipts, typing, edits and deletes were server routes, and where edits, poll
votes, RSVPs and live-location updates used a sender-local key nobody else
could read (2026-10-01 survey).

## 1. Common shape

```json
{
  "v": 1,
  "id": "0192a4f0-…",          // message id, UUIDv7, chosen by the sender
  "ts": 1767225600000,          // sender clock, epoch ms (display order only)
  "conv": {"kind": "direct", "to": "<account id>"}
       | {"kind": "group",  "group": "<group id>"},
  "type": "text",
  "body": { … },                // shape depends on type
  "reply": {"id": "…", "author": "<account id>"},          // optional
  "exp": 86400,                 // optional disappearing timer, seconds
  "profile_key": "<b64url 32 bytes>",                      // optional
  "flags": {"view_once": true}                             // optional
}
```

- `conv.to` names the **recipient** of a direct message, so the sender's own
  other devices know which chat it belongs to; a receiver resolves the chat
  as "the sender, unless the sender is me, then `to`".
- `ts` orders messages for display only; the local sort key is
  `(ts, id)`. There is no server sequence per conversation in v2, so unread
  counts and "read up to" are local (F4 change).
- **Forward compatibility.** Unknown fields are ignored. An unknown `type` is
  stored and shown as "This message needs a newer version of Helix", never as
  raw JSON (v1 showed raw JSON). A content `v` above the client's supported
  version is treated the same way. Bodies evolve only additively; a breaking
  change is a new `type` name.

## 2. Message types (shown in the chat)

| type | body | notes |
|---|---|---|
| `text` | `text`, `mentions?: [{account, start, length}]`, `link_preview?: {url, title?, description?, image?: MediaPointer}` | |
| `media` | `items: [MediaItem]` (1–30), `caption?` | images, videos, documents, voice notes, video notes; an album is several items |
| `sticker` | `pack_id`, `sticker_id`, `emoji?`, `media: MediaPointer` | |
| `location` | `lat_e7`, `lng_e7`, `accuracy_m`, `label?`, `address?` | static |
| `live_location` | `session_id`, `state: start\|update\|stop`, `lat_e7`, `lng_e7`, `accuracy_m`, `expires_at` | one session: one `start`, many `update`, one `stop`; v1 never sent updates or stop |
| `contact` | `name`, `numbers?: [string]`, `account?` | shared contact card |
| `poll` | `question`, `options: [{id, text}]` (2–12), `multiple: bool`, `closes_at?` | |
| `event` | `title`, `starts_at`, `ends_at?`, `time_zone`, `location_text?`, `plus_one_allowed: bool` | |
| `system` | `kind: timer_changed\|group_created\|member_added\|member_removed\|member_left\|group_renamed\|…`, plus fields per kind | local rendering of group or chat changes the sender announces |
| `call_log` | `call_id`, `media: audio\|video`, `outcome: answered\|missed\|declined\|failed`, `duration_s?` | posted by the caller's device after a call, so both sides' devices agree |

`MediaItem`:

```json
{
  "kind": "image|video|document|voice_note|video_note|gif",
  "media": MediaPointer,
  "caption": "…",                 // optional, per item
  "duration_ms": 12000,           // audio/video
  "waveform": "<b64url bytes>",   // voice notes, 0..255 per sample
  "width": 1280, "height": 720    // images/video
}
```

`MediaPointer` (CRYPTO_V2.md §12):

```json
{
  "id": "<media id>",             // server object id (random UUID)
  "key": "<b64url 32 bytes>",
  "digest": "<b64url sha256 of ciphertext>",
  "size": 482113,                 // plaintext bytes
  "mime": "image/jpeg",
  "name": "holiday.jpg",          // optional, documents mostly
  "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",   // optional
  "thumbnail": MediaPointer        // optional, without its own thumbnail
}
```

## 3. Actions on other messages (not shown as bubbles)

Each names its target as `target: {id, author}`. The receiver applies it to
the target if it has it, or keeps it until the target arrives (out-of-order
delivery), for up to 7 days.

| type | body | rules |
|---|---|---|
| `reaction` | `target`, `emoji`, `remove?: bool` | one reaction per account per message; a new one replaces the old |
| `edit` | `target`, `text` (or `caption` for media) | only the author; within 15 minutes of the target's `ts` (checked by receivers) |
| `delete` | `target` | delete for everyone; only the author (or a group admin, for groups); within 2 days |
| `poll_vote` | `target` (the poll), `option_ids: [string]` | empty list withdraws the vote |
| `rsvp` | `target` (the event), `state: going\|maybe\|declined`, `plus_one: bool` | |
| `receipt` | `kind: delivered\|read\|viewed`, `ids: [message id]` | sent to the author's devices; also to the reader's own devices to sync "read" across devices; never sent when the user turned read receipts off (except to own devices) |

## 4. Control messages (never shown)

| type | body | sent to |
|---|---|---|
| `typing` | `state: started\|stopped` | the chat's members; sent with `ephemeral: true` (delivered only to online devices, never stored — MESSAGING_API_V2.md) |
| `sender_key_distribution` | `group_id`, `dist_id`, `iteration`, `chain_key`, `signing_key` | pairwise, member devices lacking the key (CRYPTO_V2.md §7) |
| `group_key` | `group_id`, `epoch`, `key` | pairwise, on join and after each epoch change (CRYPTO_V2.md §9) |
| `profile_key_update` | `key`, `version` | everyone with a chat, after rotation |
| `decryption_error` | `message_id`, `sender_device` | pairwise to the sender, over a fresh session (CRYPTO_V2.md §13a) |
| `resend_request` | `ids: [message id]` | asks the author's device to re-send (after a restore) |
| `device_transfer_offer` | `transfer_id`, `relay_media?: MediaPointer` | own devices only (history transfer, F2) |
| `contact_sync` | `entries: [{account, nickname?}]` | own devices only (renames made on another device) |

## 5. Privacy flags

`flags.view_once` (media only) and `exp` are inside the encryption, so the
server cannot see them (v1 sent `view_once` and the retention deadline in the
clear). Receivers enforce them locally: view-once media is shown once, then
deleted; messages with `exp` are deleted `exp` seconds after the receiver
first displays them (WhatsApp/Signal semantics).
