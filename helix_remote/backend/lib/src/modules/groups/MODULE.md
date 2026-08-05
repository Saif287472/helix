# Module: groups

Status: current. Follows the template in `../messaging.module.md`; see the
[structural upgrade plan](../../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
for why these docs exist.

## Purpose

Everything about a group's existence and its roster: creating and deleting
it, who is in it, what role they hold, how they got in (invite or join
link), and how the group's Sender Key epoch reaches every member device.

Federation is a first-class concern here rather than an add-on. Whichever
server processed `/create` is the group's **home server** and is
authoritative for membership and roles. Every other server hosting a member
is a **participant**: it proxies its local admins' mutating actions to home
over `POST /api/v1/s2s/groups/action`, and receives roster pushes back over
`POST /api/v1/s2s/groups/sync`.

## Owned files

Split from a single 2005-line file (plan item A3) into `part` files holding
mixins, the same mechanism `../auth/` uses.

| File | Lines | Holds |
|---|---|---|
| `../groups.dart` | ~200 | Routes, collaborators, and the remote-action dispatch table |
| `federation.dart` | ~170 | `_proxyToHome`, `_requireHomeOnly`, roster sync push |
| `lifecycle.dart` | ~330 | create / info / members / update / delete |
| `membership.dart` | ~640 | invite, respond, role, leave, remove, transfer |
| `join_links.dart` | ~395 | add policy, join links, approval queue |
| `moderation.dart` | ~150 | admin message deletion, member blocking |
| `epoch_keys.dart` | ~150 | Sender Key epoch distribution |
| `relay.dart` | ~80 | fan-out helpers, last-admin promotion, `_unauthorized` |

`GroupsModuleBase` in `../groups.dart` lists exactly the helpers that cross
a part boundary — Dart mixins can only see members declared on their `on`
type, so that declaration list doubles as the module's internal contract.

## Route table

Mounted at `/api/v1/groups` by `server_impl.dart`. Every route requires a
valid session; none is in `_authMiddleware`'s public-path list.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/create` | `_handleCreate` | Creator becomes ADMIN. This server becomes the group's home server. Max 5 groups/account/day. |
| GET | `/info` | `_handleGetInfo` | Group metadata plus a paginated member list. Members only. |
| GET | `/members` | `_handleGetMembers` | Paginated roster on its own. Members only. |
| POST | `/invite` | `_handleInvite` | Admin only. 20/hour/account. Invites expire after 7 days. |
| POST | `/invite/respond` | `_handleInviteRespond` | Invitee only. Accept or reject. |
| POST | `/update` | `_handleUpdate` | Admin only. Rename / change avatar. |
| POST | `/member-role` | `_handleMemberRole` | Admin only. Refuses to demote the final admin. |
| POST | `/leave` | `_handleLeave` | Self-service. May trigger last-admin promotion. |
| POST | `/remove` | `_handleRemove` | Admin only. |
| POST | `/delete` | `_handleDelete` | Admin only. |
| POST | `/set-add-policy` | `_handleSetAddPolicy` | Admin only. Gates who may use a join link. |
| POST | `/create-join-link` | `_handleCreateJoinLink` | Admin only. 10/group/day, 7-day expiry. |
| POST | `/revoke-join-link` | `_handleRevokeJoinLink` | Admin only. |
| POST | `/join-via-link` | `_handleJoinViaLink` | 10 requests/link/hour. May enqueue for approval instead of joining. |
| GET | `/join-requests` | `_handleGetJoinRequests` | Admin only. |
| POST | `/approve-join-request` | `_handleApproveJoinRequest` | Admin only. |
| POST | `/transfer-ownership` | `_handleTransferOwnership` | New owner must already be a member. |
| POST | `/admin-delete-message` | `_handleAdminDeleteMessage` | Admin only. |
| POST | `/block-member` | `_handleBlockMember` | Admin only. Blocked accounts cannot be re-invited. |
| POST | `/epoch-key/deliver` | `_handleDeliverEpochKey` | Admin only. Fans wrapped keys out to every member device, local and federated. |

`applyRemoteAction` in `../groups.dart` is not a route. It is the entry
point `S2SModule` calls for a proxied action, and it dispatches into the
same handlers above through a synthetic local `Request` — so authorization
lives in exactly one place for both the direct-REST and the S2S path.

## Error codes this module throws

The [`AppError`](../../app_error.dart) shape, like every other module.
`_unauthorized()` in `relay.dart` is the shared 401 for a request with no
session; it returns the error rather than throwing so the 20 call sites read
`throw _unauthorized();`. Also in use: `.forbidden` (not an admin, not a
member, blocked), `.notFound` (unknown group or invite), `.conflict`
(already a member, invite no longer pending, cannot demote the final admin),
`.tooManyRequests` (the rate limits above), `.serviceUnavailable`
(federation not configured), and `.federationError` (502, home server
unreachable). Expired invites and revoked/expired join links use a bare
`AppError` with status 410, since Gone has no named factory.

## Dependencies

- `BackendDatabase` (`../../database.dart`) — all persistence.
- `MessageRelay` (`../messaging.dart`) — WebSocket fan-out to online member
  devices. Injected as `wsRelay`.
- `FederationClient?` (`../../federation.dart`) — optional. When null, any
  operation involving an external member fails closed with
  `serviceUnavailable` rather than silently applying locally and diverging
  from the other servers.

## Gotchas

- **`_isAdmin` is not `db.isGroupAdmin`.** It goes through
  `getGroupMemberRoleIncludingFederated`, because an action proxied from a
  participant server carries a qualified account id that only ever appears
  in the federated members table. Using the local-only check would silently
  deny every federated admin.
- **`_broadcastGroupSync` must be given the union of participating domains
  from before *and* after the mutation.** Passing only the "after" set means
  a server whose last member just left never learns they left.
- That broadcast is awaited, so a caller's response arrives only once every
  reachable participant has the update. An unreachable participant does not
  fail the request — its push falls back to the outbox for retry.
- **`_requireHomeOnly` exists because join-link management was scoped out of
  federation in Milestone 4.1 v1.** Those handlers reject rather than
  proxy. That is a deliberate scope cut, not an oversight.
- **Last-admin promotion prefers a local member**, and only falls back to
  the alphabetically-first federated member when no local members remain.
  Alphabetical is arbitrary but has to be deterministic: every server runs
  this independently and must reach the same answer.
- **`docs/ai/AI_GUARDRAILS.md` flags group admin and trust rules as
  non-negotiable.** Treat any change to an authorization check in
  `membership.dart` or `moderation.dart` as security-relevant.
