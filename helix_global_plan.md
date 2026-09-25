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

**What already exists:** The backend already enforces this in [`registration.dart#L97-98`](file:///j:/Projects/helix/helix_remote/backend/lib/src/modules/auth/registration.dart#L97-L98):
```dart
if (phoneOwner != null) {
  throw AppError.conflict('Phone number is already registered');
}
```

**What needs to change:**

- **Backend**: Return a distinct error code (e.g. `phone_already_registered`) so the client can differentiate this from a generic conflict and show a recovery prompt instead of a dead-end error.
- **Client (onboarding)**: Catch this specific error code and show a dialog like:
  > *"This phone number is already registered. Would you like to recover your existing account?"*
  >
  > **[Recover Account]** · **[Cancel]**
  
  Tapping "Recover Account" navigates to the existing recovery flow (which already exists via recovery codes).

### 2. Server Name = "Helix Global"

**No code change.** Just set in the admin console or directly in the database via the admin API. The app already reads `server_name` from `/api/v1/server/info` and displays it.

Alternatively, add to `.env` or set once the server starts.

### 3. Terms of Service at Registration

**Backend changes:**
- Add a `tos_accepted_at` column to the `accounts` table (migration).
- Add a `tos_version` field so future ToS revisions can be tracked.
- Require `tos_accepted: true` in the registration request body. Reject registration without it.
- Store the acceptance timestamp alongside the account row.

**Client changes:**
- Add a ToS screen/sheet shown before the final registration step.
- Include a checkbox: *"I agree to the Terms of Service and Privacy Policy"*
- Link to the actual ToS/Privacy Policy text (can be a URL or embedded markdown).
- Pass `tos_accepted: true` in the registration payload.
- Only applicable when connecting to a Global server (personal servers don't need it).

**Backend endpoint:**
- Optional: `GET /api/v1/server/tos` returns the current ToS text and version, so the client can show it dynamically.

### 4. Enable Global Mode

Add to [`helix_remote/backend/.env`](file:///j:/Projects/helix/helix_remote/backend/.env):
```env
HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true
```

---

## Implementation Checklist

### Backend
- [ ] Add error code `phone_already_registered` to the existing phone-hash conflict check
- [ ] Add DB migration: `tos_accepted_at INTEGER`, `tos_version TEXT` columns on `accounts`
- [ ] Registration handler: require `tos_accepted: true` when `globalInstanceMode` is on
- [ ] Store `tos_accepted_at` and `tos_version` on account creation
- [ ] Optional: `GET /server/tos` endpoint returning ToS text + version
- [ ] Set `HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true` in `.env`
- [ ] Set server name to `"Helix Global"` via admin console or config

### Client (App)
- [ ] Handle `phone_already_registered` error → show recovery prompt dialog
- [ ] Add ToS screen/bottom sheet before final registration (Global flow only)
- [ ] Add "I agree to Terms of Service" checkbox
- [ ] Pass `tos_accepted: true` in registration request
- [ ] Link to ToS/Privacy Policy content

### Not Needed (Deferred)
- ~~Storage quota changes~~ (same as personal)
- ~~Expose globalInstanceMode in /server/info~~ (different UI flow already handles this)
- ~~Automated abuse detection~~ (defer)
- ~~Federation changes~~ (defer)
