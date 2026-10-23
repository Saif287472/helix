# ADR 032: Sign-in asks what a number is before it texts a code

Status: accepted (2026-10-23).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§6 client rules,
§12 change log). Wire contract: `docs/protocol/v2/REST_V2.md`,
`packages/helix_remote_protocol`.

## Context

A person who opened Orbit was asked for a password for an account that did not
exist. Sign-in asked the server nothing: `POST /v1/auth/password/params`
answers a number with no account with decoy parameters (threat T-7), so the
app could not tell "you have an account" from "you do not", and the one route
that does answer - the phone verification, with `account_exists` and
`has_password` - came last, after a code the person had already waited for and
whose message their operator may have charged for. The owner's rule of
2026-10-21 ("an account with a password signs in with the number and the
password, never a code") is right for the person who has a password and wrong
for everyone else, and `submitPhone` applied it to everyone.

To choose the next screen before the code, the app needs an unauthenticated
answer to "is this number one of yours, and does it have a password?" Nothing
in v2 gave one, and every existing route that knows the answer either costs an
SMS (the verification) or hides it on purpose (the password decoy). So this ADR
is a decision to make registration status learnable, which the privacy docs
until now said it was not.

## Decision

- **`POST /v1/auth/account-status`** (identity, public): in, a number as typed;
  out, exactly `account_exists` and `has_password`. It reads
  `identity.accounts` by the peppered phone hash and writes nothing.
  `packages/helix_remote_protocol/lib/src/routes.dart`,
  `docs/protocol/v2/REST_V2.md`.
- **It answers nothing else.** No account id, no `~Helix name`, no last four
  digits, no salt, no lockout state, no hint at when the account was made.
  `false, false` for an unknown number is the whole reply.
- **It is limited per address**: 30 checks an hour
  (`identity.account_status`, the same shape as the phone-challenge and verify
  limits), in the Postgres bucket table, so it holds across nodes. A per-address
  budget of 30 an hour is 720 a day, against the 5,000 a day an authenticated
  account gets from the discovery oracle (threat T-5).
- **It grants nothing.** `register`, the recovery routes, `add_device` and
  password sign-in still demand a verified code, a recovery code or a device
  key. The answer is a hint for the UI, and `phoneVerify` remains the only
  thing the server trusts about a number; the app re-reads it there.
- **The app branches on it** (`app/lib/features/sign_in/`): a number with an
  account *and* a password goes to the password, as before; any other answer
  stays on the number and asks "Send a code to …?" first, then the code, then
  the page that sets a password - so an account with no password cannot get one
  set by somebody who never proved the number. `signInAccountStatusProvider` is
  the seam (`autoDispose`: the answer describes a moment). A server that cannot
  answer - an older build, no network, a limit - keeps the page order the app
  has always had, with "Use a code instead" under the password.
- **No sessionless password reset comes with it, and none can.** The account
  identity private key exists on the server only inside
  `identity.passwords.wrapped_identity_key`, sealed under a key derived from the
  *old* password (`PasswordKeys.unwrapIdentityKey` checks the pair against the
  account's AIK); `identity.accounts.identity_key` is the public half. So a
  phone-verified reset could not produce a valid wrap: it would either brick the
  account at the next sign-in or require keeping AIK seeds in the clear. The
  only way in that a code buys is `register` with `replace_existing`, which
  replaces the AIK, revokes every device and deletes the password and the
  recovery codes - which is why the page after the code says so and offers
  "Link from another device instead", and why that offer is the better answer
  for a forgotten password.

## Consequences

- **Registration status is now learnable by anyone who can type a number**, at
  30 checks an hour per address. That is the cost of this decision, taken with
  the product owner, and it is written down where the old claim was made:
  `docs/product/THREAT_MODEL.md` (new T-12, cross-referenced from T-7),
  `docs/product/PRIVACY_CLAIM_MATRIX.md` (the number's route through the
  server), `docs/protocol/v2/METADATA_V2.md`, and
  `server/lib/src/modules/identity/MODULE.md`.
- **No number travels further than it already did.** `passwordParams` takes the
  number from an unauthenticated caller today; the change is that a reply comes
  back, not that a request goes out. What is new is one request on the number
  page, before the person has chosen how to sign in.
- **The phone page does work now**: pressing Next opens a runtime and makes a
  request. Sign-in was already doing that one step later, so this moves the
  cost, it does not add one.
- **Deploying it means restarting Helix Global** (no migration, no new `.env`
  line) and a new app build; an app that is newer than its server falls back to
  the old page order, and an app older than its server simply never asks.
- The public-route snapshot and the route-parity table carry the new route;
  `docs/test` (`REST_V2.md` names every route) is satisfied by the row written
  with it.

## Alternatives considered

- **Ask nothing, as until today**: rejected - it is the fault being fixed, and
  decoys cannot tell a new number from a wrong password by design.
- **A non-destructive, phone-verified password reset** (owner's first choice):
  rejected as unbuildable against the current key hierarchy, as above. It would
  need the AIK seed on the server, which the threat model forbids.
- **Let the app infer it from the decoy's timing or the lockout**: rejected -
  that is a side channel, not a contract, and the review batch that evened the
  decoy's salt, transaction and lockout (A-06) was done precisely to close it.
- **Answer with the account id or the last four digits too**: rejected. They
  would make the oracle useful for targeting; two booleans are the minimum that
  picks a screen.
- **Put the check behind the hidden advanced mode**: rejected - the person it
  hurts is on the Global page.
