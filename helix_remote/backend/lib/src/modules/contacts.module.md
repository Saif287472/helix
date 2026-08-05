# Module: contacts

Status: second module migrated to the [error-format upgrade](../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A1). See `messaging.module.md` for the template this follows.

## Purpose

Contact relationships (add/remove/block/unblock), the contact-request
lifecycle (create/accept/reject/cancel), phone-hash contact discovery,
account search, presence, per-account privacy settings, and abuse reporting
(reports + admin safety actions).

## Owned files

- `contacts.dart` - `ContactsModule`, its Shelf router, and every handler.
  Not split into routes/service/validation layers yet (see plan item A3).

## Route table

Mounted at `/api/v1/contacts` by `server_impl.dart`. `GET /discovery-salt` is
the one route exempted from session auth globally (`_authMiddleware` in
`server_impl.dart` lists it explicitly) - every other route below requires a
session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/discovery-salt` | `_discoverySaltHandler` | Unauthenticated - needed before an account exists. |
| GET | `/` | `_listHandler` | Caller's contact list. |
| GET | `/requests` | `_requestsHandler` | Caller's open contact requests. |
| POST | `/requests` | `_createRequestHandler` | Rate-limited (`contactRequestDailyLimit`, 20/day). |
| POST | `/requests/accept` \| `/reject` \| `/cancel` | `_closeRequest` (shared) | Actor must be the request's target (accept/reject) or requester (cancel). |
| POST | `/add`, `/remove`, `/block`, `/unblock` | respective handlers | All take `peer_account_id`. |
| GET | `/search` | `_searchHandler` | Rate-limited (`accountSearchMinuteLimit`, 30/min); min 3-char query. |
| POST | `/match` | `_matchPhoneHashesHandler` | Rate-limited (`contactsMatchDailyLimit`, 5/day) and batch-capped (`contactsMatchBatchLimit`, 500). |
| GET / POST | `/privacy` | `_getPrivacyHandler` / `_setPrivacyHandler` | Presence/last-seen visibility + discoverability flags. |
| POST | `/presence` | `_presenceHeartbeatHandler` | Updates the caller device's last-seen timestamp. |
| GET | `/presence/<accountId>` | `_presenceHandler` | Presence of another account, filtered by that account's privacy settings. |
| POST | `/report` | `_reportHandler` | Abuse report; rejects payloads carrying plaintext. |
| POST | `/reports/action` | `_safetyActionHandler` | Admin-only (`adminAccountIds`). |

## Error codes this module throws

Same [`AppError`](../app_error.dart) shape as `messaging.dart`. Notable
choices here: `Contact request already pending` and `Admin privileges
required` both keep their original HTTP status (403) even though the
`conflict` code is used for the former - **the `code` field and the HTTP
status are independent**; don't assume one implies the other. The two
`_json(429, ...)` quota responses (`_createRequestHandler`,
`_searchHandler`, `_matchPhoneHashesHandler`) use `AppError.tooManyRequests`
with `RemoteErrorCode.quotaExceeded`.

## Dependencies

- `BackendDatabase` (`../database.dart`) - all persistence.
- `phone_hash.dart` - phone-number hashing for discovery/matching; this
  module never sees a raw phone number, only pre-hashed values from the
  client plus the server-issued discovery salt.
- `notifyDevice` callback - wired to `WebSocketRelay.sendToDevice` in
  `server_impl.dart`, used for live contact-update/removal fan-out.

## Gotchas

- **`router` is wrapped in `withAppErrorHandling` itself**, not just relying
  on the server-wide middleware. Several existing unit tests
  (`contacts_match_test.dart`, `contacts_phase13_test.dart`,
  `admin_pairing_test.dart`) call `module.router.call(request)` directly,
  bypassing `BackendServer`'s pipeline entirely - a module that throws
  `AppError` must handle that itself or those tests see a raw exception
  instead of a Response. Any future module migrated to `AppError` needs the
  same `return withAppErrorHandling(router.call);` at the end of its router
  getter - see `messaging.dart` for the same pattern.
- **Blocked-status checks are symmetric on purpose**: `_createRequestHandler`
  checks `isBlocked(peer, me) || isBlocked(me, peer)` - either direction of
  block prevents a new contact request.
- **`_matchPhoneHashesHandler` never logs the hashes themselves**, only the
  request volume - it's an oracle for "is this phone number a Helix user"
  by design, and the mitigations (auth + daily cap + batch cap) are load
  bearing, not optional hardening (see the handler's doc comment).
- **`_visibility()` can still throw a raw `FormatException`** (not
  `AppError`) for an invalid `presence_visibility`/`last_seen_visibility`
  value - caught by the shared catch-all as a generic 500, same as before
  this migration. Worth an explicit `AppError.badRequest` in a follow-up,
  but out of scope for a pure error-format migration that preserves existing
  status codes exactly.
- **`/discovery-salt` self-heals but never rotates** - see the handler's own
  doc comment for why (rotating would silently invalidate every existing
  phone-hash match).
