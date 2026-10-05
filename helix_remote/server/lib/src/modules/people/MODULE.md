# people module

Profiles, privacy, blocks, contacts, discovery, presence and reports.
Schema `people`. Facade: `api.dart` (`PeopleApi`).

- **Profiles:** ciphertext only (`profiles`), sealed with the owner's
  profile key (CRYPTO_V2.md §9). `version` must increase, and the limit
  is 16 KiB. Any signed-in device may read a profile: it is useless
  without the key.
- **Privacy:** `privacy`, defaults `everyone`. The `contacts` audience
  means the account's uploaded `contacts` list (phone-book matches,
  replace-all, at most 5,000 entries).
- **Blocks:** `blocks`. Installed as messaging's `BlockPolicy`, so sends
  and calls from a blocked account are dropped silently. Blocked
  accounts also cannot discover you, find your `~name`, see your presence
  or add you to groups.
- **Discovery:** `POST /v1/people/discover` takes client-computed
  `hex(HMAC(salt, E.164))` hashes (the salt is public). Identity maps each
  to a pepper-keyed index and matches on that, so the database never holds
  a hash anyone can test numbers against (see identity's MODULE.md).
  Budget: 1,000 per call and 5,000 per account per day
  (`discovery_budget`; a call over the budget consumes nothing). It
  honours `discoverable_by_phone` and blocks. This remains the accepted
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
- **Reports:** `reports` stores no message content. The admin console
  lists and resolves them through `PeopleApi.reports` / `resolveReport`.
  They survive account deletion as the moderation record (ids only).
- **Export:** profile version, privacy, blocked accounts, contact count,
  reports filed.
- **Remote accounts:** blocks accept `uuid@domain` (stored qualified;
  `blocked` is `text` since migration 2). Messages and calls relayed from
  that account are then dropped like local ones.
- **Account deletion** purges every row about the account, including
  blocks and contacts on other accounts that name it.
