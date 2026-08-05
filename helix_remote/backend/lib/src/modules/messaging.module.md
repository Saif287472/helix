# Module: messaging

Status: the template the other module docs follow, from the
[structural upgrade plan](../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(items A1 and A4). Every backend module now has one of these.

## Purpose

Direct (non-group) conversation lifecycle and per-device encrypted message
delivery: create a DIRECT conversation, send/sync ciphertext envelopes,
delete/edit messages, reactions, receipts, typing indicators, and the
device-scoped event feed those all fan out through.

GROUP conversations are explicitly out of scope here - see Gotchas.

## Owned files

- `messaging.dart` - `MessagingModule`, its Shelf router, and every handler.
  Still one file: at ~850 lines it is well under the threshold that made
  splitting `groups` and `calls` worthwhile (plan item A3).

## Route table

Mounted at `/api/v1/messages` by `server_impl.dart`. All routes require a
valid session (`_authMiddleware` does not exempt any `/messages/*` path).

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/conversations/create` | `_createConversationHandler` | DIRECT only - rejects `type: 'GROUP'`. |
| POST | `/send` | `_sendMessageHandler` | Per-device ciphertext envelopes; idempotent on `message_id`. |
| GET | `/sync` | `_syncMessagesHandler` | With `conversation_id`: history for that conversation. Without: offline catch-up across all conversations. |
| POST | `/cursor` | `_updateCursorHandler` | Advances the caller's per-conversation read cursor. |
| POST | `/delete` | `_deleteMessageHandler` | Sender-only; writes a tombstone and triggers attachment refcount cleanup. |
| POST | `/edit` | `_editMessageHandler` | Sender-only; fans out `message_edited`. |
| POST | `/reactions` | `_reactionHandler` | Fans out `reaction_added`. |
| POST | `/receipts` | `_receiptHandler` | `receipt_type` must be `DELIVERY` or `READ`. |
| POST | `/typing` | `_typingHandler` | Fans out `typing`; not persisted (`persist: false`). |
| GET | `/device-events` | `_deviceEventsHandler` | Cursor-based catch-up feed for the caller's own device. |

## Error codes this module throws

Since the [A1 migration](../app_error.dart), every handler throws `AppError`
instead of building its own `Response`. Codes in use here:
`RemoteErrorCode.unauthorized` (missing auth context - defensive; the global
auth middleware should already have rejected the request), `.notAMember`,
`.badRequest` (missing/invalid fields), `.notFound` (unknown message),
`.forbidden` (not the message owner; envelope targets a non-member;
`.quotaExceeded` mailbox full), `.serviceUnavailable` (federation not
configured but the message has federated recipients).

## Dependencies

- `BackendDatabase` (`../database.dart`) - all persistence; this module owns
  no SQL of its own outside what `BackendDatabase` exposes.
- `MessageRelay` (this file) - abstract interface implemented by
  `WebSocketRelay`, for immediate delivery to online devices. Injected, not
  constructed here.
- `FederationClient?` (`../federation.dart`) - optional; when null, sends to
  federated recipients fail closed with `serviceUnavailable` rather than
  silently dropping the envelope.
- `onMessageDeleted` callback - wired to `AttachmentsModule.cleanAttachmentReferences`
  in `server_impl.dart` so deleting a message can drop attachment references
  without this module importing the attachments module directly.

## Gotchas

- **GROUP conversations must go through `POST /api/v1/groups/create`**, not
  this module's `/conversations/create`. That endpoint also creates the
  federation-relevant `groups` bookkeeping row that this generic path
  doesn't know about. Sending `type: 'GROUP'` here is rejected with a
  `badRequest` pointing at the right endpoint.
- **Envelopes must be ciphertext-only.** A body containing `plaintext`,
  `message_text`, or `body` keys is rejected outright - this is a server-side
  enforcement of E2EE, not just a client convention.
- **Blocked-sender envelopes are silently dropped, not rejected.** If the
  recipient has blocked the sender, `_sendMessageHandler` skips that
  recipient's envelope with no error, by design (revealing the block would
  leak it to the blocked sender).
- **Mailbox quota is a hardcoded 5000** outstanding messages per device
  (`P10-021`), enforced per-recipient inside the send loop, not upfront -
  a large fan-out can partially succeed before hitting a quota-exceeded
  recipient.
- **Federated sends batch by destination domain**, not by recipient device -
  one signed HTTP round-trip per remote domain even if a group message fans
  out to many devices on that domain (Milestone 4.3).
- Unrecognized/removed devices in `_sendMessageHandler`'s per-device loop are
  silently skipped (`ownerRows.isEmpty -> continue`), not reported as an
  error to the sender.
