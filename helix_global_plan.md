# Helix Global Server — Implementation Plan

## Decisions Locked In

| Question | Decision |
|----------|----------|
| Accounts per phone | **1 account per number.** Recover previous account if already registered. |
| Storage quotas | **Same as personal** (100 MB attachments, 5 GB quota, 30-day retention) |
| Server info / branding | Server name = `"Helix Global"`. No code change — just config. |
| Terms of Service | **Show ToS** and require acceptance at registration. |

---

## What Needs to Be Implemented

### 1. One Account Per Phone — Recovery Guidance

**Implemented:** The backend now returns HTTP 409 with `code: "phone_already_registered"` for a new account using an existing phone hash. The app parses the code and shows a recovery prompt. The prompt routes the user to the existing recovery-code flow; it does not claim that a phone number alone can restore an account.

The backend check remains in [`registration.dart`](file:///j:/Projects/helix/helix_remote/backend/lib/src/modules/auth/registration.dart), backed by the unique `accounts.phone_hash` index.

The implemented dialog is:
> *This phone number already has a Helix account. Would you like to enter a recovery code and restore that account?*
>
> **[Enter recovery code]** · **[Cancel]**

### 2. Server Name = "Helix Global"

**Deployment configuration remains.** The admin API/database already supports setting and serving `server_name`; no application code change is needed. The local backend database was configured to `Helix Global` and migrated to schema version 43; production deployments should set the same value from the admin console or `POST /api/v1/ops/config/server-name`.

### 3. Terms of Service at Registration

**Implemented:** The Global registration contract now includes `tos_accepted` and `tos_version`. Migration 43 adds nullable `tos_accepted_at` and `tos_version` columns to `accounts`. Global registrations require explicit acceptance of the current version; personal-server registrations remain backward-compatible.

The versioned Terms of Service and Privacy Policy live in [`packages/helix_remote_domain/lib/domain/legal_documents.dart`](file:///j:/Projects/helix/helix_remote/packages/helix_remote_domain/lib/domain/legal_documents.dart), with reviewable Markdown copies in [`docs/legal`](file:///j:/Projects/helix/helix_remote/docs/legal/). The app presents them in a scrollable legal-documents sheet and requires the checkbox before the final Global registration step.

A public `GET /api/v1/server/tos` endpoint returns the current text, effective date, and versions.

### 4. Enable Global Mode

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

### Client (App)
- [x] Handle `phone_already_registered` error → show recovery prompt dialog
- [x] Add ToS screen/bottom sheet before final registration (Global flow only)
- [x] Add "I agree to the Terms of Service and Privacy Policy" checkbox
- [x] Pass `tos_accepted` and `tos_version` in registration requests
- [x] Link to embedded ToS/Privacy Policy content
- [x] Add CLI/API support for explicit Global ToS acceptance

### Not Needed (Deferred)
- ~~Storage quota changes~~ (same as personal)
- ~~Expose globalInstanceMode in /server/info~~ (different UI flow already handles this)
- ~~Automated abuse detection~~ (defer)
- ~~Federation changes~~ (defer)
