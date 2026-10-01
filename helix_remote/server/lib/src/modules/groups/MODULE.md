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
