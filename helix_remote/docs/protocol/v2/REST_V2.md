# Helix Remote v2 — REST API

Status: **specified 2026-10-01 (Phase P1), pending user review.** The route
catalog in `packages/helix_remote_protocol/lib/src/routes.dart` is the source
of truth; every route there is listed below (a test checks this), and the
DTO named for each route is in `packages/helix_remote_protocol/lib/src/modules/`.
Replaces v1's hand-written OpenAPI file for v2 (plan change log 2026-10-01).

## Conventions

- **Base:** `https://<server>/v1/…`, JSON bodies (`content-type:
  application/json`) except media content (octet-stream).
- **Auth:** `Authorization: Bearer <access token>` (device, 15-minute JWT)
  or an admin token. Public routes are listed in `routes_test.dart`'s
  snapshot and each has a server-side rate limit.
- **Ids** are canonical lowercase UUIDs. Ids the client creates (accounts,
  devices, messages, groups) are UUIDv7. A federated account is
  `<uuid>@<domain>`.
- **Bytes** are unpadded base64url. **Times** are epoch milliseconds (UTC).
- **Errors:** `{"error": {"code", "message"?, "details"?, "retry_after_s"?}}`
  with the HTTP status of the code (`errors.dart`). Clients branch on `code`.
- **Idempotency:** every mutating request may carry `Idempotency-Key`; the
  server stores the result for 24 hours per principal and replays it (same key
  with a different body: `idempotency_conflict`). Message sends are also
  idempotent by their `id`.
- **Paging:** `?cursor=&limit=` (max 200), responses `{items, next_cursor?}`.
  No offsets.
- **Unknown fields** are ignored by both sides; new optional fields are
  additive and never change the meaning of existing ones
  (`remote_compatibility_policy.md`).
- **Suspended accounts** get `account_suspended` from every route except
  reading their own data, sign-out, export and deletion.

## identity

| Route | Body → response | Rules |
|---|---|---|
| `POST /v1/auth/phone/challenges` | `PhoneChallengeRequest` → `PhoneChallengeResponse` | Helix Global only. 6-digit code, 10 min, 5 attempts; per number 5/hour, per IP limits. The number is hashed; only the last 4 digits are kept. |
| `POST /v1/auth/phone/verify` | `PhoneVerifyRequest` → `PhoneVerifyResponse` | Consumes the code; returns a single-use 15-minute `verification_token`. |
| `POST /v1/auth/invites/lookup` | `InviteLookupRequest` → `InviteLookupResponse` | Rate-limited per IP. |
| `POST /v1/auth/invites/self-issue` | — → `InviteSelfIssueResponse` | Helix Global only; 3/hour per IP. |
| `POST /v1/auth/register` | `RegisterRequest` → `RegisterResponse` | Verifies the device certificate (AIK) and proof (DSK). Global: needs `verification_token`; existing account → `account_exists` unless `replace_existing`. Personal: needs `invite_code`, redeemed last. |
| `POST /v1/auth/password/params` | `PasswordParamsRequest` → `PasswordParamsResponse` | Decoy parameters for numbers without a password. |
| `POST /v1/auth/password/sign-in` | `PasswordSignInRequest` → `PasswordSignInResponse` | Lockout: 5 failures → 15 min, doubling to 24 h (`password_locked`, `details.locked_until`). Wrong password and unknown number both give `invalid_credentials`. |
| `POST /v1/auth/links` | `LinkCreateRequest` → `LinkCreateResponse` | New device; 10-minute link. |
| `GET /v1/auth/links/{link_id}` | bearer `poll_token`, `?wait_s=` ≤ 30 → `LinkPollResponse` | Long-poll. |
| `POST /v1/auth/devices` | `AddDeviceRequest` → `Session` | Exactly one of `sign_in_token` / `link_token`. Certificate must verify under the account's AIK. Other devices get `account_signal`/`new_sign_in` and `device_list_change` is sent to everyone with a session. |
| `POST /v1/auth/challenges` | `DeviceChallengeRequest` → `DeviceChallengeResponse` | Challenge kept 5 minutes in the ephemeral store. |
| `POST /v1/auth/sessions` | `DeviceSignInRequest` → `Session` | DSK signature over `signInSignatureBody(challenge)`. |
| `POST /v1/auth/sessions/refresh` | `RefreshRequest` → `Session` | Rotation; reuse of a used token revokes all of the device's tokens. |
| `POST /v1/auth/recovery/lookup` | `RecoveryLookupRequest` → `RecoveryLookupResponse` | Rate-limited per IP. |
| `POST /v1/auth/recovery/redeem` | `RecoveryRedeemRequest` → `Session` | New AIK; other devices revoked; history backup deleted; `key_change` to contacts. |
| `DELETE /v1/auth/sessions/current` | — → 204 | Sign out this device's tokens (device stays registered). |
| `GET /v1/account` | — → `AccountInfo` | |
| `PUT /v1/account/password` | `SetPasswordRequest` → 204 | Needs the current auth key or a fresh verification token. Other devices get `password_changed`. |
| `PUT /v1/account/helix-name` | `SetHelixNameRequest` → 204 | `name_taken` on conflict. |
| `DELETE /v1/account/helix-name` | — → 204 | |
| `GET /v1/account/security-events` | paged → `Page<SecurityEvent>` | |
| `GET /v1/devices` | — → `DeviceList` | No push tokens. |
| `PATCH /v1/devices/{device_id}` | `RenameDeviceRequest` → 204 | |
| `DELETE /v1/devices/{device_id}` | `?reason=lost` optional → 204 | Revokes the device: tokens, prekeys, push token and mailbox purged; `device_list_change` sent; sessions with that device end on peers. Revoking yourself signs you out. |
| `POST /v1/devices/revoke-others` | — → `RevokeOthersResponse` | |
| `POST /v1/devices/links/{link_id}/approve` | `LinkApproveRequest` → 204 | |
| `PUT /v1/devices/self/push-token` | `PushTokenRequest` → 204 | |
| `DELETE /v1/devices/self/push-token` | — → 204 | |

## keys

| Route | Body → response | Rules |
|---|---|---|
| `PUT /v1/keys/signed-prekey` | `SignedPrekey` → 204 | Signature checked against the device's DSK. |
| `POST /v1/keys/one-time-prekeys` | `AddOneTimePrekeysRequest` → `KeyStatus` | ≤ 200 per call, ≤ 1,000 stored per device. |
| `GET /v1/keys/status` | — → `KeyStatus` | |
| `GET /v1/keys/{account}` | `?device=` repeatable → `AccountKeys` | Consumes one OTK per returned device; per-account and per-requester rate limits (prekey exhaustion protection). Federated accounts are fetched from their home server. |

## messaging

| Route | Body → response | Rules |
|---|---|---|
| `POST /v1/messages` | `SendMessageRequest` → `SendMessageResponse` | Each recipient account must be addressed on **all** its active devices (the sender's own: all except the sending device) or the request fails with `device_list_stale` (`StaleDevices` details) and nothing is sent. Blocked-by-recipient: accepted and silently dropped. Payload ≤ 256 KiB. Mailbox quota per device: 10,000 undelivered envelopes (`quota_exceeded`). `ephemeral`: online devices only, never stored. |
| `GET /v1/mailbox` | `?after=&limit=` → `MailboxPage` | Oldest first. |
| `POST /v1/mailbox/ack` | `AckRequest` → `AckResponse` | Cumulative; deletes acked envelopes. Undelivered envelopes expire after 30 days. |

## realtime

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/ws` | WebSocket upgrade, `Sec-WebSocket-Protocol: helix.v1+json` | See REALTIME_V2.md. |

## people

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/people/discovery-salt` | — → `DiscoverySalt` | Authenticated in v2 (v1 was public). |
| `POST /v1/people/discover` | `DiscoverRequest` → `DiscoverResponse` | ≤ 1,000 per call, 5,000 per day; only accounts with `discoverable_by_phone`. |
| `GET /v1/people/by-name/{name}` | — → `FindByNameResponse` | Exact match only; only `discoverable_by_name`; rate-limited. |
| `GET /v1/people/{account}/profile` | — → `EncryptedProfile` | Ciphertext only; readable by anyone with the profile key. |
| `GET /v1/people/{account}/presence` | — → `PresenceResponse` | Filtered by the owner's `online`/`last_seen` audience. |
| `PUT /v1/profile` | `EncryptedProfile` → 204 | `version` must increase. ≤ 16 KiB. |
| `GET /v1/people/blocks` | — → `BlockList` | |
| `PUT /v1/people/blocks/{account}` | — → 204 | Blocked accounts' messages and calls are dropped silently; they cannot add you to groups. |
| `DELETE /v1/people/blocks/{account}` | — → 204 | |
| `GET /v1/people/privacy` | — → `PrivacySettings` | |
| `PUT /v1/people/privacy` | `PrivacySettings` → 204 | |
| `PUT /v1/people/contacts` | `SetContactsRequest` → 204 | Replace-all; used only for "contacts" audiences. |
| `POST /v1/people/reports` | `ReportRequest` → `ReportResponse` | No message content. |

## groups

| Route | Body → response | Rules |
|---|---|---|
| `POST /v1/groups` | `CreateGroupRequest` → `Group` | Creator is owner. Members whose `group_add` audience excludes the creator are left out (invite link instead). 1,024 members max. |
| `GET /v1/groups` | — → `GroupList` | |
| `GET /v1/groups/{group_id}` | — → `Group` | Members only. |
| `DELETE /v1/groups/{group_id}` | — → 204 | Owner only. `roster_change`/`deleted` to members. |
| `PUT /v1/groups/{group_id}/state` | `SetGroupStateRequest` → `GroupVersionResponse` | `edit_info` permission; optimistic version. |
| `PUT /v1/groups/{group_id}/settings` | `GroupSettings` → 204 | Admins. |
| `POST /v1/groups/{group_id}/members` | `AddMembersRequest` → `AddMembersResponse` | `add_members` permission + each target's `group_add` audience. |
| `DELETE /v1/groups/{group_id}/members/{account}` | — → `GroupVersionResponse` | Self = leave; otherwise admins. Bumps the epoch. |
| `PUT /v1/groups/{group_id}/members/{account}/role` | `SetRoleRequest` → 204 | Admins set admin/member; only the owner sets owner (transfer). |
| `PUT /v1/groups/{group_id}/bans/{account}` | — → 204 | Admins; removes and blocks rejoin. |
| `DELETE /v1/groups/{group_id}/bans/{account}` | — → 204 | |
| `POST /v1/groups/{group_id}/invite-links` | `CreateInviteLinkRequest` → `InviteLink` | Admins. |
| `DELETE /v1/groups/{group_id}/invite-links/{link_id}` | — → 204 | |
| `POST /v1/groups/invite-links/preview` | `InviteTokenRequest` → `InvitePreview` | Rate-limited. |
| `POST /v1/groups/join` | `InviteTokenRequest` → `JoinGroupResponse` | Banned accounts refused. |
| `GET /v1/groups/{group_id}/join-requests` | — → `JoinRequestList` | Admins. |
| `POST /v1/groups/{group_id}/join-requests/{request_id}` | `ResolveJoinRequest` → 204 | Admins. |
| `POST /v1/groups/{group_id}/messages` | `GroupMessageRequest` → `SendMessageResponse` | Members with `send_messages` permission. `devices_digest` must match the server's member devices (`device_list_stale` otherwise, with every member's devices in details). Fan-out to all member devices except the sender. |

Every roster or settings change emits a `roster_change` envelope to every
member device (and to removed members, so they know).

## calls

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/calls/turn` | — → `TurnCredentials` | 1-hour credentials; 10/hour per device. |
| `POST /v1/calls/{call_id}/signals` | `CallSignalRequest` → `CallSignalResponse` | Online devices get a `call_signal` envelope now; for `offer`, offline devices get a pending call (TTL ≤ 120 s) and a high-priority push. Blocked: dropped silently. |
| `PUT /v1/calls/{call_id}/state` | `CallStateRequest` → 204 | Clears pending offers; other devices of the same account stop ringing. |
| `GET /v1/calls/pending` | — → `PendingCallList` | |
| `POST /v1/calls/metrics` | `CallMetricsRequest` → 204 | |

## media

| Route | Body → response | Rules |
|---|---|---|
| `POST /v1/media` | `CreateUploadRequest` → `UploadTarget` | Size ≤ server max; account quota. |
| `PUT /v1/media/{media_id}/content` | octet-stream, `Upload-Offset` → 204 | Owner only; resumable; completes when `size` bytes are stored. |
| `HEAD /v1/media/{media_id}/content` | → `Upload-Offset`, `Upload-Length` | |
| `GET /v1/media/{media_id}/content` | → bytes (`Range` supported) or `302` to a presigned URL | Any signed-in device: ids are random and content is encrypted, so knowing the id is the capability. |
| `DELETE /v1/media/{media_id}` | — → 204 | Owner. |

## backup

| Route | Body → response | Rules |
|---|---|---|
| `PUT /v1/backups/history` | `HistoryBackup` → 204 | `version` must increase; ≤ 16 MiB. |
| `GET /v1/backups/history` | — → `HistoryBackup` | |
| `DELETE /v1/backups/history` | — → 204 | |
| `PUT /v1/backups/full` | `FullBackup` → 204 | Refuses envelopes containing `backup_key`, `passphrase`, `recovery_phrase`. |
| `GET /v1/backups/full` | — → `FullBackup` | |
| `DELETE /v1/backups/full` | — → 204 | |

## ops

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/health/live` | — → `LiveResponse` | |
| `GET /v1/health/ready` | — → `ReadyResponse` | 503 when not ready. |
| `GET /v1/server` | — → `ServerInfo` | |
| `GET /v1/server/legal` | — → `LegalDocuments` | |
| `POST /v1/telemetry/crash` | `CrashReport` → 204 | Opt-in; per-device limit. |
| `GET /v1/ops/metrics` | — → Prometheus text | Admin token. |
| `GET /.well-known/assetlinks.json` | — → Android asset links | |
| `GET /open` | — → HTML landing page for `#HLX-…` links | |

## compliance

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/account/export` | — → JSON export of everything the server holds about the account | |
| `DELETE /v1/account` | `DeleteAccountRequest` → 204 | Emits `identity.account_deleted`; every module purges its rows. |

## federation

| Route | Body → response | Rules |
|---|---|---|
| `GET /.well-known/helix-server` | — → `ServerIdentityDocument` | |
| `POST /v1/s2s/messages` | batch of envelopes for local devices | Signed S2S headers (Ed25519 over `server|timestamp|method|path|sha256(body)`), ±5 min skew, replay cache. Specified in detail in Phase S6. |
| `GET /v1/s2s/keys/{account}` | → `AccountKeys` | |
| `POST /v1/s2s/groups/{group_id}/messages` | group fan-out to local members | |
| `GET /v1/s2s/groups/{group_id}` | → `Group` | Home server only. |
| `POST /v1/s2s/groups/{group_id}/actions` | proxied member actions | Acting account's domain must match the caller. |
| `POST /v1/s2s/groups/{group_id}/sync` | roster push from the home server | |
| `POST /v1/s2s/calls/{call_id}/signals` | call signal relay | |

## admin

DTOs are defined in Phase S6/AD (`modules/admin.dart`).

| Route | Purpose |
|---|---|
| `GET /v1/admin/setup` | First-run check (public). |
| `POST /v1/admin/setup` | Set the first admin password (public, only before setup). |
| `POST /v1/admin/sessions` | Admin sign-in → 12-hour admin token (public, rate-limited, lockout). |
| `PUT /v1/admin/password` | Change the admin password. |
| `GET /v1/admin/accounts` | List accounts (paged; no phone numbers, last 4 digits only). |
| `GET /v1/admin/accounts/{account}` | One account with its devices. |
| `PUT /v1/admin/accounts/{account}/suspension` | Suspend. |
| `DELETE /v1/admin/accounts/{account}/suspension` | Unsuspend. |
| `POST /v1/admin/accounts/{account}/ban` | Ban the phone hash and delete the account. |
| `DELETE /v1/admin/accounts/{account}` | Delete the account. |
| `DELETE /v1/admin/accounts/{account}/devices/{device_id}` | Revoke a device (full purge, unlike v1). |
| `POST /v1/admin/accounts/{account}/recovery-codes` | Issue a 48-hour single-use recovery code. |
| `GET /v1/admin/invites` | List invites. |
| `POST /v1/admin/invites` | Create an invite. |
| `DELETE /v1/admin/invites/{invite_id}` | Cancel an invite. |
| `GET /v1/admin/reports` | List reports. |
| `PUT /v1/admin/reports/{report_id}` | Resolve or dismiss. |
| `GET /v1/admin/audit` | Audit log (paged). |
| `GET /v1/admin/config` | Server configuration (no secrets). |
| `PATCH /v1/admin/config` | Change server name, federation, maintenance mode. |
| `GET /v1/admin/feature-flags` | Flags. |
| `PUT /v1/admin/feature-flags/{name}` | Set a flag. |
| `GET /v1/admin/logs` | Recent redacted log lines. |
| `GET /v1/admin/logs/stream` | WebSocket of live redacted log lines. |
| `POST /v1/admin/purge` | Purge dead letters and expired rows. |
