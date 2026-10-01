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
  `hex(HMAC(salt, E.164))` hashes. Matching happens through identity's
  discovery hashes. Budget: 1,000 per call and 5,000 per account per day
  (`discovery_budget`; a call over the budget consumes nothing). It
  honours `discoverable_by_phone` and blocks. This remains the accepted
  T-5 oracle.
- **`~Helix name` lookup:** exact, case-insensitive match, honours
  `discoverable_by_name`, 30 per minute per account.
- **Presence:** online means any device holds a socket (kernel
  `Presence`). Last seen comes from the realtime gateway's record,
  truncated to the minute. Both are filtered by the target's audiences.
- **Reports:** `reports` stores no message content. The admin console
  (S6) reads it.
- **Account deletion** purges every row about the account, including
  blocks and contacts on other accounts that name it.
