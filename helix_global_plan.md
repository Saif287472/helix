# Helix Global Server — Implementation Plan

## Decisions Locked In

| Question | Decision |
|----------|----------|
| Accounts per phone | **1 account per number.** A verified SMS OTP signs that account in on this device. |
| Invitations on Global | **None.** The SMS OTP is the only credential; the invite system is bypassed entirely. |
| Existing-account login | **Passwordless.** A valid OTP alone authorizes a new device — no approval from an already-linked device. |
| Storage quotas | **Same as personal** (100 MB attachments, 5 GB quota, 30-day retention) |
| Server info / branding | Server name = `"Helix Global"`. No code change — just config. |
| Terms of Service | **Show ToS** and require acceptance at registration. |

---

## What Needs to Be Implemented

### 1. One Account Per Phone — Passwordless Phone Login

**Implemented.** Helix Global no longer uses invitations and no longer refuses a
phone number that already owns an account. The server decides entirely from the
phone hash, and the client never learns an account id from a phone number before
the OTP has proven control of that number:

1. The app submits the phone number. No invite is requested, issued, or shown.
2. The server sends a six-digit OTP through BulkSMSBD.
3. `POST /api/v1/accounts/phone/otp/verify` checks the code against the exact
   challenge. A wrong code never reaches registration.
4. `POST /api/v1/accounts/register` re-verifies the same challenge atomically and
   then branches server-side:
   - **New number** → creates the account and this device, exactly as before.
   - **Known number** → does **not** create anything. It signs the existing
     account in on this device and answers with the real `account_id` and
     `existing_account: true`.
5. The client uses the returned `account_id` for the challenge/login calls, then
   publishes prekeys and syncs normally.

**Why an existing-account login revokes the previous device.** An account has a
single Ed25519 identity key that signs its signed prekeys, and every peer's
prekey bundle is verified against the one server-side `identity_public_key`. A
newly linked device holds a *new* identity key pair, so it can only send and
receive messages if the account key rotates to it — and that rotation breaks any
previously-linked device's ability to send. The server therefore rotates the
account key to the new device and revokes the old ones, mirroring the existing
account-recovery flow exactly. This is safe in the Global model because a phone
number maps to one SIM and therefore one physical device: this is a
takeover-by-the-phone, not a silent second-device attach. The unique
`accounts.phone_hash` index still guarantees one account per number.

Guards on that path: a blocked phone hash is rejected before anything else, a
`BLOCKED` account cannot be signed in to, a wrong OTP creates and changes
nothing, and every link is audit-logged as `DEVICE_LINKED_VIA_OTP`.

Personal/self-hosted servers are unchanged: they still require a real,
unexpired invite code and still return `409 phone_already_registered` for a
duplicate number, which routes to the existing recovery-code dialog.

### 2. Server Name = "Helix Global"

**Deployment configuration remains.** The admin API/database already supports setting and serving `server_name`; no application code change is needed. The local backend database was configured to `Helix Global` and migrated to schema version 43; production deployments should set the same value from the admin console or `POST /api/v1/ops/config/server-name`.

### 3. Terms of Service at Registration

**Implemented:** The Global registration contract now includes `tos_accepted` and `tos_version`. Migration 43 adds nullable `tos_accepted_at` and `tos_version` columns to `accounts`. Global registrations require explicit acceptance of the current version; personal-server registrations remain backward-compatible.

The versioned Terms of Service and Privacy Policy live in [`packages/helix_remote_domain/lib/domain/legal_documents.dart`](file:///j:/Projects/helix/helix_remote/packages/helix_remote_domain/lib/domain/legal_documents.dart), with reviewable Markdown copies in [`docs/legal`](file:///j:/Projects/helix/helix_remote/docs/legal/). The app presents them in a scrollable legal-documents sheet and requires the checkbox before the final Global registration step.

A public `GET /api/v1/server/tos` endpoint returns the current text, effective date, and versions.

### 4. SMS Delivery (BulkSMSBD)

Global phone login depends entirely on real SMS delivery. The server refuses to
issue an OTP when no provider is configured — it never returns the code in the
API response. Add to [`helix_remote/backend/.env`](file:///j:/Projects/helix/helix_remote/backend/.env):

```env
HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true
HELIX_REMOTE_SMS_API_KEY=<bulksmsbd api key>
HELIX_REMOTE_SMS_SENDER_ID=<approved sender id>
```

Without the SMS pair, `POST /accounts/phone/otp/request` fails with
`503 sms_delivery_failed` ("SMS delivery is not configured on this server").
The sender ID must be approved by BulkSMSBD first.

### 5. Enable Global Mode

Add to [`helix_remote/backend/.env`](file:///j:/Projects/helix/helix_remote/backend/.env):
```env
HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true
```

---

## Implementation Checklist

### Backend
- [x] Add error code `phone_already_registered` to the existing phone-hash conflict check
- [x] Add DB migration: `tos_accepted_at INTEGER`, `tos_version TEXT` columns on `accounts`
- [x] Registration handler: require `tos_accepted: true` when `globalInstanceMode` is on
- [x] Store `tos_accepted_at` and `tos_version` on account creation
- [x] Add public `GET /server/tos` endpoint returning ToS/Privacy text + version
- [x] Set `HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true` in the local backend `.env` and document it in `.env.example`
- [x] Set the local Global server name to `"Helix Global"` via the server configuration database; repeat through the admin console/API for production
- [x] Add public `POST /accounts/phone/otp/verify` for challenge-bound pre-registration verification
- [x] Registration: make `invite_code` optional and invite-less when `globalInstanceMode` is on
- [x] Registration: on Global, an existing phone hash becomes a phone-authenticated device login — rotate the account identity key, revoke prior devices, return the real `account_id` with `existing_account: true`
- [x] Registration: reject blocked phone hashes and `BLOCKED` accounts on the device-link path
- [x] Audit the device link as `DEVICE_LINKED_VIA_OTP`

### Client (App)
- [x] Handle `phone_already_registered` error → show recovery prompt dialog (personal servers)
- [x] Add ToS screen/bottom sheet before final registration (Global flow only)
- [x] Add "I agree to the Terms of Service and Privacy Policy" checkbox
- [x] Pass `tos_accepted` and `tos_version` in registration requests
- [x] Link to embedded ToS/Privacy Policy content
- [x] Add CLI/API support for explicit Global ToS acceptance
- [x] Stop requesting/issuing a Global invite and stop showing the invite-code notification
- [x] Omit `invite_code` entirely from Global registration requests
- [x] `registerAndLogin`: use the server-resolved `account_id` and keep the existing account's display name on a phone login

### Contract / API
- [x] `invite_code` no longer required in the `RegisterRequest` schema; documented as Global-optional
- [x] Document the `existing_account` / `display_name` / resolved-`account_id` response on `POST /accounts/register`
- [x] Relax `inviteCode` to optional across the app client, CLI client, and shared `HelixRemoteRestClient` interface

### Not Needed (Deferred)
- ~~Storage quota changes~~ (same as personal)
- ~~Expose globalInstanceMode in /server/info~~ (different UI flow already handles this)
- ~~Automated abuse detection~~ (defer)
- ~~Federation changes~~ (defer)
