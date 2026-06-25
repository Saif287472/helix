# F6 — Groups, Administration, and Communities: Design

**Phase:** F6  
**Schema bump:** local storage v19, backend schema v22  
**Capability token:** `helix.remote.groups-admin.v1`  
**Status:** Implemented 2026-06-25

---

## Goals

Complete secure group lifecycle and moderation. Basic group creation, invitations, roles, leave/remove, and server events were implemented in prior phases (P16). This phase closes the remaining gaps:

1. **Authenticated group-key distribution** — pairwise E2EE wrapping of epoch keys for each active member device.
2. **Group-add privacy** — per-group policy controlling who may add members directly vs. who receives a private invite.
3. **Join links with admin approval queue** — high-entropy expiring links; incoming requests enter an admin-approved queue.
4. **Creator protection and ownership transfer** — original creator cannot be demoted or removed until ownership is explicitly transferred.
5. **Admin moderation deletion** — admins may delete abusive messages; a visible moderator tombstone is left in place.
6. **Blocked/re-add policy** — members who block or leave may not be repeatedly re-added without their consent.
7. **Silent leave** — leave events notify admins only; non-admin members see a generic membership change.
8. **Recent history for new members** — admin-controlled, sender-authorized, encrypted message range delivered to new joiners with a disclosure banner.
9. **Participant search, role tags, mention index** — paginated participant search, role display beside messages, @-mention parsing with catch-up navigation.
10. **Online member count** — presence-aware summary count that honours per-account visibility settings.
11. **Highlight-only notification policy** — per-group mode that only alerts on mentions, replies, and admin events.
12. **Community containers** — intentionally deferred; groups must pass scale and encryption tests first.

---

## Architecture decisions

### Group key distribution (epoch keys)

The prior implementation calls `encryptionKeyProvider(groupId, epoch)` which returns a raw key string stored in `group_epoch_keys`. What was missing: delivery of those epoch keys to each member device in a form only that device can read (pairwise E2EE wrapping).

**Chosen approach:** When the service rotates or creates an epoch key, it records a `group_epoch_key_delivery` row per member device. Each row contains:
- `device_id` (recipient device)
- `key_id` (which epoch key)
- `wrapped_key` (epoch key material encrypted with the recipient device's agreement public key, HKDF-derived AES-GCM)
- `delivered_at` (NULL until the server confirms delivery)

The backend relays these wrapped deliveries when the `membership_changed` event is processed. Old clients that do not understand the delivery payload fall back to requesting the key via the existing `/info` endpoint plus a local decryption call. This is capability-gated with `helix.remote.groups-admin.v1`.

**Server blindness:** Raw epoch key material never appears in server-visible payloads. The backend only routes `wrapped_key` ciphertext blobs; it cannot decrypt them.

### Group-add privacy

Four tiers, stored per group:
- `EVERYONE` — any member can add someone directly.
- `CONTACTS` — only contacts of the inviter may be directly added.
- `CONTACTS_EXCEPT` — contacts minus a stored exclusion list.
- `NOBODY` — all direct additions are rejected; a private expiring invite is created instead.

When a direct add is blocked by policy, the backend returns HTTP 409 with `code: group_add_not_allowed` and automatically creates a private invite for the target account rather than silently failing. The client displays the invite sent confirmation.

### Join links

- Token: 32 bytes cryptographically random, base64url-encoded.
- Expiry: configurable, default 7 days, stored in `group_join_links`.
- `requires_approval` flag: when true, incoming join requests enter an admin-visible queue in `group_join_requests`; when false, the requester is added immediately (subject to group-add privacy).
- Revocation: admins call `/groups/revoke-join-link`; revoked links return HTTP 410.
- Rate limits: 10 pending requests per link per hour to prevent abuse.

### Creator protection

The `groups` table gains a `creator_protected INTEGER NOT NULL DEFAULT 1` flag. While set:
- The backend blocks `/member-role` demotions targeting the creator to `MEMBER`.
- The backend blocks `/remove` operations targeting the creator.
- Only the creator themselves can clear this flag via `/groups/transfer-ownership` (transfers to a named ADMIN member).

After transfer the new owner can be treated normally; the former owner retains ADMIN unless demoted.

### Silent leave

The existing `/leave` endpoint broadcasts `membership_changed` to all members. In F6 the payload is split:
- All remaining members receive a `membership_changed` with `action: left_silently` (no name, no identity).
- Admins receive a separate `membership_changed_admin` event containing the full leaver account ID for audit/key-rotation purposes.

### Admin message deletion

New endpoint `POST /groups/admin-delete-message`. The message row is soft-deleted; the client replaces the bubble with a moderator tombstone badge. A `group_admin_event` of type `message_moderated` is relayed to all members containing the `message_id` but no content. An audit log entry is written.

### Recent history sharing

New flag `history_sharing_enabled` on the group record. When enabled and a new member joins:
- The admin client calls `POST /groups/history-package` with an encrypted message range (sender-encrypted ciphertext blobs) and explicit `from_sequence`/`to_sequence`.
- The server stores the package temporarily (72-hour TTL) and delivers it only to the joining member's devices.
- The UI shows a disclosure banner: "Admin shared recent messages with you."
- Members can disable future sharing for themselves; admins can disable globally.

### Blocked/re-add policy

New table `group_blocked_members (group_id, account_id, blocker_id, created_at)`. A member who uses "Block and Leave" or who is recorded here cannot be re-added directly. Attempting to invite them returns 409. They may still submit a join request via a link if they choose.

---

## Storage schema changes (local, v19)

```sql
-- Group add policy per group
CREATE TABLE group_add_policy (
  group_id TEXT PRIMARY KEY,
  policy TEXT NOT NULL DEFAULT 'EVERYONE',
  contacts_except_json TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL
);

-- Join links created by this device
CREATE TABLE group_join_links (
  link_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  token TEXT NOT NULL,
  requires_approval INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Join requests seen by this device (inbound from server)
CREATE TABLE group_join_requests (
  request_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  link_id TEXT NOT NULL,
  status TEXT NOT NULL,  -- PENDING / APPROVED / REJECTED
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Blocked members (won't be re-added directly)
CREATE TABLE group_blocked_members (
  group_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, account_id)
);

-- Epoch key wrapped deliveries per device
CREATE TABLE group_epoch_key_deliveries (
  delivery_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  epoch INTEGER NOT NULL,
  key_id TEXT NOT NULL,
  recipient_device_id TEXT NOT NULL,
  wrapped_key TEXT NOT NULL,
  delivered_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Mention index (local only)
CREATE TABLE group_mention_index (
  mention_id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  mentioned_account_id TEXT NOT NULL,
  server_sequence INTEGER NOT NULL,
  read_at INTEGER NOT NULL DEFAULT 0
);

-- Per-group notification policy
CREATE TABLE group_notification_policy (
  group_id TEXT PRIMARY KEY,
  policy TEXT NOT NULL DEFAULT 'ALL',  -- ALL / MENTIONS_ONLY / ADMIN_ONLY / MUTED
  updated_at INTEGER NOT NULL
);

-- Moderated messages (local tombstones from admin deletion)
CREATE TABLE group_moderated_messages (
  message_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  moderated_by TEXT NOT NULL,
  moderated_at INTEGER NOT NULL
);
```

---

## Backend schema changes (v22)

```sql
-- Group add policy
ALTER TABLE groups ADD COLUMN add_policy TEXT NOT NULL DEFAULT 'EVERYONE';
ALTER TABLE groups ADD COLUMN creator_protected INTEGER NOT NULL DEFAULT 1;
ALTER TABLE groups ADD COLUMN history_sharing_enabled INTEGER NOT NULL DEFAULT 0;

-- Join links
CREATE TABLE group_join_links (
  link_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  creator_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  requires_approval INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Join requests
CREATE TABLE group_join_requests (
  request_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  link_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Blocked members
CREATE TABLE group_blocked_members (
  group_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, account_id)
);

-- Moderated message log
CREATE TABLE group_moderated_messages (
  message_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  moderated_by TEXT NOT NULL,
  moderated_at INTEGER NOT NULL
);

-- History package (72-hour TTL, new-member-only)
CREATE TABLE group_history_packages (
  package_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  for_account_id TEXT NOT NULL,
  from_sequence INTEGER NOT NULL,
  to_sequence INTEGER NOT NULL,
  encrypted_package TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

---

## New REST endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/groups/set-add-policy | ADMIN | Set group-add privacy policy |
| POST | /api/v1/groups/create-join-link | ADMIN | Create expiring join link |
| POST | /api/v1/groups/revoke-join-link | ADMIN | Revoke a join link |
| POST | /api/v1/groups/join-via-link | Any | Submit join request via link token |
| GET | /api/v1/groups/join-requests | ADMIN | List pending join requests |
| POST | /api/v1/groups/approve-join-request | ADMIN | Approve or reject a request |
| POST | /api/v1/groups/transfer-ownership | Creator | Transfer creator status |
| POST | /api/v1/groups/admin-delete-message | ADMIN | Moderate/delete abusive message |
| POST | /api/v1/groups/block-member | ADMIN | Block member from being re-added |
| POST | /api/v1/groups/history-package | ADMIN | Upload history package for new member |

---

## Key rotation triggers

| Event | Rotation |
|-------|----------|
| Member removed (admin or self-leave) | Yes — epoch++ |
| Member added via invite | Yes — epoch++ (new member gets new key material) |
| Join request approved | Yes — epoch++ |
| Device revoked | Yes — epoch++ (handled by F1 revocation flow) |
| Ownership transfer | No (admin set is unchanged) |
| Role change | No |

---

## Security properties

- **Post-removal secrecy:** Epoch increment on every removal/leave ensures removed members cannot decrypt future messages with the epoch key they previously held.
- **Pre-join secrecy:** New members receive only the epoch key valid from their join onwards; they cannot decrypt earlier epochs unless history sharing is explicitly enabled by an admin.
- **Server blindness:** Epoch key material is wrapped per-device with the recipient's public agreement key. The server only transports opaque wrapped blobs.
- **Mention index:** Local only; never uploaded. The index is rebuilt from local decrypted message history.
- **Creator protection:** Enforced at the backend; client UI reflects the server's authoritative state.

---

## Testing plan

- 2-500 member groups (pagination, batch operations)
- Simultaneous admin actions (role change + remove — last-write-wins per server order)
- Offline members receive key rotation via next sync cycle
- Old clients (no `helix.remote.groups-admin.v1`) fall back gracefully
- Blocked user re-add attempt returns 409
- Creator demotion attempt blocked while `creator_protected=1`
- Expired join link returns 410
- Admin-deleted message shows moderator tombstone on all devices
- History package expires after 72h, is not accessible to non-recipients
- Mention catch-up navigation: tapping catches up to the correct message
