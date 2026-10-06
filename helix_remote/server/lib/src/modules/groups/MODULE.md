# groups module

Group roster authority. Schema `groups` (`groups`, `members`, `bans`,
`invite_links`, `join_requests`). The server enforces membership and roles.
Names, pictures and descriptions are an encrypted state blob (group master
key, CRYPTO_V2.md §9), and messages are sender-key ciphertext (§7).

## Rules

- **Roles:** `owner` (one per group), `admin`, `member`.
  - `GroupSettings` decide whether `everyone` or only `admins` may add
    members, edit the state blob, or send.
  - Admins change settings, remove members, ban, manage links and join
    requests.
  - Only the owner may make someone else owner, and doing so makes the
    old owner an admin.
  - Nobody may remove or demote the owner.
- **Adding people** honours each target's `group_add` audience and blocks
  (`PeopleApi.mayAddToGroup`). People who don't allow it are listed in
  `rejected` as `privacy`; invite them with a link instead.
  1,024 members at most.
- **Removal, leaving and bans** bump the `epoch` (members rotate their
  sender keys and the group master key). When the owner leaves, the
  oldest admin (or else the oldest member) becomes owner. An empty group
  is deleted.
- **Invite links:** the token goes in the link, and only its SHA-256 is
  stored. Previews return the member count and an encrypted preview
  (sealed with a key carried in the link fragment). Banned accounts
  cannot join. Approval links create join requests that only admins hear
  about (`join_requested`).
- **State updates** are optimistic (`expected_version`, else
  `version_conflict`).
- **Non-members** get 404 for every group route, so a group's existence
  does not leak.

## Messages (`POST /v1/groups/{id}/messages`)

- **Members only**, and the `send_messages` permission applies.
- **Digest check:** `devices_digest` must equal `membersDigest` of every
  member device except the sending one. Otherwise `device_list_stale`
  lists *all* current member devices in `missing`, so the client can
  distribute its sender key and retry.
- **Delivery:** `distributions` (pairwise sender-key distribution
  messages, member devices only) are stored before the single
  `group_message` ciphertext, which goes to every member device. Group
  messages are not filtered by personal blocks (WhatsApp behaviour).
- **Retries:** use `Idempotency-Key`.

Every roster or settings change sends a `roster_change` envelope to every
member device; removed members are told too.

## Federation (`federation.dart`)

A group lives on its **home server**, where it was created. The home
server keeps the roster. Members on other servers are stored as
`uuid@domain` (members, bans and join requests are `text` since
migration 2). Every S2S payload and every action answer is rendered in the
receiving server's frame (`Frame`): bare ids for that server's accounts,
`uuid@home` for the home server's, unchanged for third servers.

### On the home server

- **Remote members' actions:** S2S `actions` run the same operation code
  as the client routes, with the remote member as the actor.
  - The actor must belong to the calling server.
  - `devices` is the member server reporting a member's devices. Ids that
    are this server's own devices, or already reported for another
    account, are refused (`invalid_field`); in a sync answer they are
    dropped. Otherwise a member's server could have someone else's copy of
    each group message routed to it.
- **Roster changes:** each `_announce` bumps `roster_version`. It queues
  one `groups.sync` per other server with members (or a removed member).
  - The job sends the current snapshot, rendered for that server, and the
    change event. A server that is down is retried.
  - The answer carries that server's members' devices, saved in
    `remote_devices`, and the accounts it refused, which the home removes.
- **Adding remote accounts:** they are added optimistically. Their own
  server checks that they exist, and checks their group-add privacy and
  blocks against the adder.
- **Group messages:** the digest is checked with ids in the sender's frame,
  over local devices plus `remote_devices`. Remote member devices get the
  message and their distributions through one queued `groups.fanout` per
  server (deduped per message). Ephemeral sends go out once, best effort.
  A message from a member on another server is not fanned back to that
  server: it delivers to its own members itself.
- **Invite tokens:** `grp_<secret>.<group id>@<home>`, so people elsewhere
  can join through their own server.

### On a member's server

- **Cached groups:** `remote_groups` holds the latest snapshot per remote
  group. Older `roster_version`s are ignored. `remote_members` lists the
  local accounts in it.
- **Routes:** group routes for a remote group are proxied to its home as
  actions. `GET` fetches the group from the home and falls back to the
  snapshot when the home is down. Preview and join use the home named in
  the token. `myGroups` includes remote groups.
- **Syncs:** only the group's home may push it, and an id that clashes
  with a local group is refused. Roster events go only to local accounts
  that are, or just were, members.
- **Who may be added here:** every local account that is new in a
  snapshot (whatever the event) must exist and either have asked to join
  that group through this server (a `remote_joins` marker, recorded before
  the join is proxied and kept for 30 days or until used), or have been
  added by the event's actor: a member of the snapshot whose role may add
  people (`created` or `added` events only), who is not the account itself,
  and whom the account's group-add privacy and blocks allow. Anyone else is
  listed in `rejected`, and the home removes them.
- **Fan-outs:** only the group's home may send them. The sender must be a
  member of the cached snapshot and never an account of this server
  (`forbidden`): local members' messages go through this server, which
  delivers them to its own member devices once the home accepts the send.
  Distributions carry the checked sender. Devices revoked meanwhile are
  skipped.
- **Device changes:** a local member's device-list change queues
  `groups.devices` to each home.
- **Account deletion:** it queues `groups.leave`.
