# ADR 030: Visible blocks, and the operator sees names and numbers

Status: accepted (2026-10-14).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§12, change log).

## Context

Two v2 privacy defaults turned out not to be what the product owner wants
for Helix Global:

- **Blocks were silent.** A blocked person's messages were accepted and
  dropped, and their calls rang until they timed out, so they could not tell
  a block from someone who never answers (the WhatsApp and Signal model).
- **The operator saw almost nothing about an account.** The server keeps a
  keyed hash of the phone number and its last four digits, never the number
  (identity `MODULE.md`), and profiles are end-to-end encrypted, so the
  admin console could show only the last four digits and the `~Helix name`.

The product owner decided both on 2026-10-14, knowing the trade-offs:
telling someone they are blocked can provoke them (a new account, another
channel), and a server that holds names and numbers is a richer target.

## Decision

### Blocks are visible

- Blocking or unblocking sends the blocked account's devices a
  server-generated `block_change` envelope (`BlockChangeEvent`: `account`,
  `blocked`), in the same transaction as the change and only when the row
  changed. Accounts on other servers are not told (federation has no such
  signal).
- `POST /v1/messages` still drops the deliveries to accounts that blocked the
  sender, and names them in `SendMessageResponse.blocked_by`; the rest of the
  send (the sender's own devices, other recipients) goes out as before.
- A call `offer` to a callee who blocked the caller is refused with `blocked`
  (403); the call's other signals are still dropped silently.
- The engine keeps "this person blocked me" per account
  (`PersonState.blocksMe`, a setting, so no schema change), set and cleared
  by those three signals. A message that reached nobody because everyone it
  was for blocked the sender fails (`blocked`); a refused offer fails as
  `CallFailure.blockedByPeer`. The app replaces the composer with "<Name>
  has blocked you. You can't message or call them." and hides the call
  buttons.

### The operator sees names and numbers

- `PUT /v1/account/phone-number` (identity): an app reports its account's
  own number once after signing in. The server accepts only the number that
  hashes to the account's verified phone hash, and keeps it sealed with
  AES-256-GCM under `HELIX_PHONE_KEY` (a new, optional, 32-byte secret kept
  outside the database), with the account id as associated data
  (`identity/domain/phone_seal.dart`, migration 3, `accounts.phone_sealed`).
  Without the key nothing is kept.
- `PUT /v1/profile/name` (people): the name the person gives themselves, in
  the clear, sent with every profile save and once after signing in
  (`people.display_names`, migration 4). Contacts still read the encrypted
  profile; this copy is for the operator only.
- `AdminAccount` carries `display_name` and the full `phone_number`; the
  console shows them, falling back to the `~Helix name` and the last four
  digits. Both are in the account's own export and are deleted with the
  account.
- `AdminReport` carries the same for both people - `reporter_name`,
  `reporter_phone`, `subject_name`, `subject_phone` - added 2026-10-25 so a
  report row names who filed it and who it is about, and each name opens that
  account's console page. Nothing new is stored: the record keeps its two
  account ids and the row is joined at read time from the tables above.

## Consequences

- Privacy claims change: a blocked person learns that, and when, they were
  blocked; the operator (and anyone with a database dump **and**
  `HELIX_PHONE_KEY`) can read every reported number; anyone with a database
  dump can read every reported name. `METADATA_INVENTORY.md`,
  `PRIVACY_CLAIM_MATRIX.md` and `THREAT_MODEL.md` say so.
- Existing accounts fill in as their apps start with this version; until
  then the console shows what it did before.
- Server logs still never contain a full number or a name (the redacting
  logger, and the routes log nothing about their bodies).
- Rotating `HELIX_PHONE_KEY` makes the stored numbers unreadable until apps
  report them again (they report once per sign-in); there is no re-sealing
  job.

## Alternatives considered

- Keep blocks silent: rejected by the product owner.
- Tell blocked people only on their next send: rejected in favour of telling
  them at once.
- Store numbers in plain text: rejected; a dump alone would reveal them.
- Derive the number key from `HELIX_PHONE_PEPPER`: rejected so the two
  secrets can be held and rotated apart.
