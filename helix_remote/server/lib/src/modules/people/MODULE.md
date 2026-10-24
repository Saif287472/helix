# people module

Profiles, privacy, blocks, contacts, discovery, presence and reports.
Schema `people`. Facade: `api.dart` (`PeopleApi`).

- **Profiles:** ciphertext only (`profiles`), sealed with the owner's
  profile key (CRYPTO_V2.md §9). `version` must increase, and the limit
  is 16 KiB. Any signed-in device may read a profile: it is useless
  without the key.
- **Display names:** `display_names` (migration 4), the name each account
  gives itself **in the clear**, from `PUT /v1/profile/name` (≤ 80
  characters, empty deletes it). Apps send it with every profile save and
  once after signing in. Only the admin console reads it
  (`PeopleApi.displayNames`, ADR-030); it is in the account's export and is
  purged with the account.
- **Privacy:** `privacy`, defaults `everyone`. The `contacts` audience
  means the account's uploaded `contacts` list (phone-book matches, at most
  5,000 entries). `PUT /v1/people/contacts` stores only the difference, so an
  unchanged phone book writes no row at all; `people.contacts` (12 an hour,
  per device) bounds what is left, which is a list that really did change
  (AUD-4a-3).
- **Blocks:** `blocks`. Installed as messaging's `BlockPolicy`, so sends
  and calls from a blocked account reach nobody. Blocks are not secret:
  blocking and unblocking tell the blocked account's **online** devices with
  a live-only `block_change` frame (only when the row changed; accounts on
  other servers and devices that are away are not told - an away device
  learns the state from its next send's `blocked_by`), sends name the
  blockers in `blocked_by`, and calls refuse the offer with `blocked`. The
  notice stores no row, so one person flapping a block cannot fill another
  account's mailbox and make it lose its unread mail (AUD-4a-1).
  `people.block` (burst 60, 2 a second, per device) bounds how fast those
  frames can be pushed into other people's sockets. Blocked
  accounts also cannot discover you, find your `~name`, see your presence
  or add you to groups.
- **Discovery:** `POST /v1/people/discover` takes client-computed
  `hex(HMAC(salt, E.164))` hashes (the salt is public). Identity maps each
  to a pepper-keyed index and matches on that, so the database never holds
  a hash anyone can test numbers against (see identity's MODULE.md).
  Budget: 1,000 per call and 5,000 per account per day
  (`discovery_budget`; a call over the budget consumes nothing). The day is
  the UTC one, not the session time zone's `current_date`, so the row the
  server counts and the `retry_after` it promises end at the same instant:
  the refusal names the next UTC midnight, and `people.purge_discovery`
  (daily) keeps today's row plus `discoveryHistory`, which until AUD-4a-4
  only account deletion ever removed. Discovery honours
  `discoverable_by_phone` and blocks. This remains the accepted
  T-5 oracle: an authenticated client can ask the live server about
  numbers within the budget.
- **Discovery opt-out:** turning `discoverable_by_phone` off deletes the
  account's discovery index (`IdentityApi.setPhoneDiscoverable`, in the same
  transaction as the privacy row). Turning it back on needs
  `PrivacySettings.phone_number`, the account's own number, which identity
  checks against the verified phone hash before rebuilding the index
  (`invalid_field` on `phone_number` otherwise). Saving other settings while
  discovery is already on needs no number.
- **`~Helix name` lookup:** exact, case-insensitive match, honours
  `discoverable_by_name`, 30 per minute per account.
- **Presence:** online means any device holds a socket (kernel
  `Presence`). Last seen comes from the realtime gateway's record,
  truncated to the minute. Both are filtered by the target's audiences.
- **Read limits:** reading another account's presence or profile costs the
  reader one token of `people.reads` (120 a minute) and, the first time that
  day, one of `people.read_targets` (2,000 distinct accounts a day; the
  `people:seen:<reader>:<target>` marker in the ephemeral store, one day, is
  removed again when the read is refused). Reading yourself is free.
- **Reports:** `reports` stores no message content. The admin console
  lists and resolves them through `PeopleApi.reports` / `resolveReport`.
  They survive account deletion as the moderation record (ids only) while
  open. Resolving or dismissing sets `resolved_at` (migration 3), and
  `people.purge_reports` (daily) deletes them 180 days later
  (`reportRetention`).
- **Export:** profile version, privacy, blocked accounts, contact count,
  reports filed.
- **Remote accounts:** blocks accept `uuid@domain` (stored qualified;
  `blocked` is `text` since migration 2). Messages and calls relayed from
  that account are then dropped like local ones.
- **Account deletion** purges every row about the account, including
  blocks and contacts on other accounts that name it.
