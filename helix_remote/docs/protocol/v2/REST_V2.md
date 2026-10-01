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
  with a different body: `idempotency_conflict`). Stored results are
  encrypted at rest (some carry a secret once, such as an invite link).
  Message sends are also idempotent by their `id`, per sending device.
- **Bodies:** credentials (and, for S2S, the signature headers' shape and
  clock skew) are checked before the body is read. Each route has a size
  limit (`payload_too_large`); a node that is already buffering its limit of
  request bodies answers `unavailable` (503, `Retry-After`). JSON bodies
  nested deeper than 64 levels are `bad_request` before decoding. Values a
  column cannot hold (an `int4` past 2^31 − 1) are `invalid_field`, never
  500.
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
| `POST /v1/auth/phone/verify` | `PhoneVerifyRequest` → `PhoneVerifyResponse` | Consumes the code; returns a single-use 15-minute `verification_token`, and the existing `account_id` when the number has an account (needed to certify a device for `replace_existing`). |
| `POST /v1/auth/invites/lookup` | `InviteLookupRequest` → `InviteLookupResponse` | Rate-limited per IP. |
| `POST /v1/auth/invites/self-issue` | — → `InviteSelfIssueResponse` | Helix Global only; 3/hour per IP. |
| `POST /v1/auth/register` | `RegisterRequest` → `RegisterResponse` | Verifies the device certificate (AIK) and proof (DSK). Global: needs `verification_token`; existing account → `account_exists` unless `replace_existing`. Personal: needs `invite_code`, redeemed last. |
| `POST /v1/auth/password/params` | `PasswordParamsRequest` → `PasswordParamsResponse` | Decoy parameters for numbers without a password. |
| `POST /v1/auth/password/sign-in` | `PasswordSignInRequest` → `PasswordSignInResponse` | Lockout: 5 failures → 15 min, doubling to 24 h (`password_locked`, `details.locked_until`), shared with `PUT /v1/account/password`. Wrong password and unknown number both give `invalid_credentials`. |
| `POST /v1/auth/links` | `LinkCreateRequest` → `LinkCreateResponse` | New device; 10-minute link. |
| `GET /v1/auth/links/{link_id}` | bearer `poll_token`, `?wait_s=` ≤ 30 → `LinkPollResponse` | Long-poll. |
| `POST /v1/auth/devices` | `AddDeviceRequest` → `Session` | Exactly one of `sign_in_token` / `link_token`. Certificate must verify under the account's AIK. Other devices get `account_signal`/`new_sign_in` and `device_list_change` is sent to everyone with a session. |
| `POST /v1/auth/challenges` | `DeviceChallengeRequest` → `DeviceChallengeResponse` | Challenge kept 5 minutes in the ephemeral store under a random `challenge_id` (never the public device id, so nobody else can replace or spend it). |
| `POST /v1/auth/sessions` | `DeviceSignInRequest` → `Session` | `challenge_id` and `challenge` from the response, for the device it was issued to (single use); DSK signature over `signInSignatureBody(challenge)`. |
| `POST /v1/auth/sessions/refresh` | `RefreshRequest` → `Session` | Rotation; reuse of a used token revokes all of the device's tokens and closes its socket (4001). |
| `POST /v1/auth/recovery/lookup` | `RecoveryLookupRequest` → `RecoveryLookupResponse` | Rate-limited per IP. |
| `POST /v1/auth/recovery/redeem` | `RecoveryRedeemRequest` → `Session` | New AIK; other devices revoked; history backup deleted; `key_change` to contacts. |
| `DELETE /v1/auth/sessions/current` | — → 204 | Sign out this device's tokens (device stays registered); its socket closes (4001) on whichever node holds it. Other devices get `account_signal`/`signed_out`. |
| `GET /v1/account` | — → `AccountInfo` | |
| `PUT /v1/account/password` | `SetPasswordRequest` → 204 | Needs the current auth key or a fresh verification token. A wrong current auth key counts towards password sign-in's lockout (`password_locked`). 10 per hour per account. Other devices get `password_changed`. |
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
| `POST /v1/messages` | `SendMessageRequest` → `SendMessageResponse` | Each recipient account must be addressed on **all** its active devices (the sender's own: all except the sending device) or the request fails with `device_list_stale` (`StaleDevices` details) and nothing is sent. Blocked-by-recipient: accepted and silently dropped. Payload ≤ 256 KiB. Mailbox quota per device: 10,000 undelivered envelopes (`quota_exceeded`). `ephemeral`: online devices only, never stored. Rate-limited per device (200 burst, 5/s) and per account (400 burst, 10/s). |
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
| `POST /v1/calls/{call_id}/signals` | `CallSignalRequest` → `CallSignalResponse` | Online devices get a `call_signal` envelope now; for `offer`, offline devices get a pending call (TTL ≤ 120 s) and a high-priority push. A pending offer is refreshed only by the same caller device; anyone else's offer under that call id is not stored. `end` clears only pending offers the sender is in (as caller or callee). Blocked: dropped silently. |
| `PUT /v1/calls/{call_id}/state` | `CallStateRequest` → 204 | Clears pending offers the account is in (as caller or callee); other devices of the same account stop ringing. |
| `GET /v1/calls/pending` | — → `PendingCallList` | |
| `POST /v1/calls/metrics` | `CallMetricsRequest` → 204 | 100 per day per account. |

## media

| Route | Body → response | Rules |
|---|---|---|
| `POST /v1/media` | `CreateUploadRequest` → `UploadTarget` | Size ≤ the kind's max; per-kind account quota. `url` is a server path for local storage, an absolute presigned URL for S3. The S3 URL signs `content-length` = `size`: upload exactly `size` bytes in one `PUT`. |
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
| `PUT /v1/backups/full` | `FullBackup` → 204 | Refuses envelopes containing `backup_key`, `passphrase`, `recovery_phrase`. ≤ 64 MiB envelope, at most 32 levels deep and 100,000 JSON values (`bad_request`). |
| `GET /v1/backups/full` | — → `FullBackup` | |
| `DELETE /v1/backups/full` | — → 204 | |

## ops

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/health/live` | — → `LiveResponse` | |
| `GET /v1/health/ready` | — → `ReadyResponse` | 503 when not ready. |
| `GET /v1/server` | — → `ServerInfo` | `features`: allow-listed flags. |
| `GET /v1/server/legal` | — → `LegalDocuments` | |
| `POST /v1/telemetry/crash` | `CrashReport` → 204 | Opt-in, and only while the `crash_reporting_upload` flag is on (`forbidden` otherwise). 10 per hour per device. Logged redacted, never stored. |
| `GET /v1/ops/metrics` | — → Prometheus text | Admin token, or the server's `HELIX_METRICS_TOKEN` (opens this route only). |
| `GET /.well-known/assetlinks.json` | — → Android asset links | |
| `GET /open` | — → HTML landing page for `#HLX-…` links | |

## compliance

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/account/export` | — → `AccountExport` | One section per module; metadata only (encrypted things appear as versions, sizes, counts). 5 per day. Also while suspended. |
| `DELETE /v1/account` | `DeleteAccountRequest` → 204 | Runs identity's deletion in one transaction: every module's hook purges its rows. Not a ban. Also while suspended. |

## federation

Accounts on other servers are `<uuid>@<domain>` (`AccountAddress`); the
domain is the authority of the home server's public base URL. Clients use
qualified addresses anywhere an account id goes (`POST /v1/messages`
recipients, `GET /v1/keys/{account}`, blocks, call signals). Their own
server relays.

Every S2S request is signed. The headers are `x-helix-s2s-server` (the
caller's domain), `x-helix-s2s-timestamp` (ms) and `x-helix-s2s-signature`:
base64url Ed25519 over `helix-s2s-v1|<server>|<timestamp>|<METHOD>|<path?query>|<base64url(sha256(body))>`
(`s2sSigningInput`). The receiving server rejects a skew of more than
±5 minutes and any reused signature. The caller's key comes from
`https://<domain>/.well-known/helix-server`. S2S clients never follow
redirects.

| Route | Body → response | Rules |
|---|---|---|
| `GET /.well-known/helix-server` | — → `ServerIdentityDocument` | `server_id` = domain; `api_base` on the same authority. |
| `POST /v1/s2s/messages` | `S2SMessageBatch` → `SendMessageResponse` | `sender` qualified with the caller's domain (`forbidden` otherwise); recipients are the receiver's bare ids. The rules of `POST /v1/messages` apply (exact device lists, blocks, quotas, idempotent ids). |
| `GET /v1/s2s/keys/{account}` | `?device=` repeatable → `AccountKeys` | Consumes one-time prekeys. Per-server and per-(server, account) limits, plus the account's per-target limit shared with local fetches. |
| `POST /v1/s2s/groups/{group_id}/messages` | `S2SGroupMessage` → 204 | Home → member server: a group message and its distributions for the receiver's member devices. Only the group's home may send. The sender must be a member in the receiver's snapshot and not one of the receiver's own accounts (`forbidden`): the home does not fan a message back to its sender's server, which delivers to its own members once the home accepts the send. |
| `GET /v1/s2s/groups/{group_id}` | → `Group` | Home server only, in the caller's frame, if the caller has members. |
| `POST /v1/s2s/groups/{group_id}/actions` | `S2SGroupAction` → `S2SGroupActionResult` | Member server → home: runs the client route named by `action` for `actor`, whose domain must be the caller's. The result carries that route's status and body. `devices` reports a member's devices (ids of the home's own devices or of another account: `invalid_field`). |
| `POST /v1/s2s/groups/{group_id}/sync` | `S2SGroupSync` → `S2SGroupSyncResponse` | Home → member server: the snapshot (null when deleted) and the change to deliver. The response lists members' devices and the accounts refused. A local account new in the snapshot is refused unless it exists and either asked to join through the receiver or was added (`created`/`added`) by a snapshot member allowed to add people whom its privacy and blocks allow. Older `roster_version`s are ignored. |
| `POST /v1/s2s/calls/{call_id}/signals` | `S2SCallSignal` → `CallSignalResponse` | Live only; offers to offline devices become pending calls there. |

## admin

DTOs in `modules/admin.dart`. Lists are cursor-paged `Page<T>` (`cursor`,
`limit`). Every mutating route writes an audit row. Admin tokens and device
tokens never open each other's routes.

| Route | Body → response | Rules |
|---|---|---|
| `GET /v1/admin/setup` | — → `AdminSetupStatus` | Public. |
| `POST /v1/admin/setup` | `AdminPasswordRequest` → 201 `AdminSession` | Public, only before setup (`already_exists` after). 5 per hour per IP. |
| `POST /v1/admin/sessions` | `AdminPasswordRequest` → `AdminSession` | Public, 10 per minute per IP. Per IP, 5 failures lock that address (15 min, doubling to 24 h); 100 failures from anywhere since the last success lock sign-in for 15 min. Attempts are counted before the password is checked (`password_locked`). 12-hour token. |
| `PUT /v1/admin/password` | `ChangeAdminPasswordRequest` → `AdminSession` | Ends every other admin session. |
| `GET /v1/admin/accounts` | — → `Page<AdminAccount>` | `status`, `q` (name prefix or last 4 digits). Last 4 digits only. |
| `GET /v1/admin/accounts/{account}` | — → `AdminAccountDetail` | |
| `PUT /v1/admin/accounts/{account}/suspension` | optional `AdminActionRequest` → 204 | |
| `DELETE /v1/admin/accounts/{account}/suspension` | — → 204 | |
| `POST /v1/admin/accounts/{account}/ban` | optional `AdminActionRequest` → 204 | Bans the phone hash and deletes the account. |
| `DELETE /v1/admin/accounts/{account}` | — → 204 | Full deletion through identity's hooks. |
| `DELETE /v1/admin/accounts/{account}/devices/{device_id}` | — → 204 | Full revoke and purge (unlike v1). |
| `POST /v1/admin/accounts/{account}/recovery-codes` | — → 201 `AdminRecoveryCode` | 48 hours, single use, shown once. |
| `GET /v1/admin/invites` | — → `Page<AdminInvite>` | Codes are never listed. |
| `POST /v1/admin/invites` | — → 201 `CreatedInvite` | Code shown once. |
| `DELETE /v1/admin/invites/{invite_id}` | — → 204 | Open invites only. |
| `GET /v1/admin/reports` | — → `Page<AdminReport>` | `status`. |
| `PUT /v1/admin/reports/{report_id}` | `ResolveReportRequest` → 204 | `resolved` or `dismissed`; open reports only. |
| `GET /v1/admin/audit` | — → `Page<AuditEntry>` | Newest first. |
| `GET /v1/admin/config` | — → `AdminConfig` | No secrets. |
| `PATCH /v1/admin/config` | `AdminConfigPatch` → `AdminConfig` | Server name, maintenance mode, federation switch. |
| `GET /v1/admin/feature-flags` | — → `FeatureFlags` | |
| `PUT /v1/admin/feature-flags/{name}` | `SetFeatureFlagRequest` → 204 | Allow-listed names only (`not_found`). |
| `GET /v1/admin/logs` | — → `AdminLogLines` | `limit` 1–500. This node, redacted. |
| `GET /v1/admin/logs/stream` | WebSocket of redacted JSON lines | |
| `POST /v1/admin/purge` | — → `PurgeResult` | Dead jobs and expired identity rows. |
