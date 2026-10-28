# Key compromise runbook (Helix Global)

What to do when a secret may have leaked, in the order to do it. The routine
rotations (nothing leaked) are in `V2_SERVER_HANDOFF.md`, "Rotating secrets";
this page is for the bad day. Agents never touch the live server, `.env` or the
production database: every step below is yours.

First, in every case: **note the time**, keep the old values until the new ones
work, change `.env` in the production folder (the one next to `bin\`, not the
development checkout), restart with the scheduled task, and look at the
Application event log (source `Helix`) and the console's audit log for what
happened since.

## The secrets, where they live, what a leak costs

| Secret | Lives in | Who has a copy | A leak lets an attacker | Rotate |
|---|---|---|---|---|
| `HELIX_JWT_KEYS` (the ring) | `.env` | you, a password manager | mint device tokens for any account whose id they know, and operator tokens (those are signed with a key derived from the ring key) | section 1 |
| `HELIX_PHONE_PEPPER` | `.env` | you, **a paper copy** | with a database dump, test which phone numbers are Helix users | section 2 |
| `HELIX_PHONE_KEY` | `.env` | you, **a paper copy** | with a database dump, read the full phone numbers apps reported | section 3 |
| Federation signing key | `federation.settings` in the database (so in every dump) | the backups | sign server-to-server requests as this server | section 4 |
| `HELIX_TURN_SECRET`, `HELIX_TURN_VOICE_SECRET` | `.env` and coturn (rendered in WSL `/run`) | you | use the relay for free, uncapped (the main secret) | section 5 |
| BulkSMSBD key | `.env` | you, the provider's panel | send texts on your balance | section 6 |
| Firebase service account | `.env` / a JSON file | you, the Firebase console | send push wake-ups to your users' phones (data-only; they carry nothing) | section 6 |
| PostgreSQL password (role `helix`) | `.env` and `pgpass.conf` | you | read and change everything | section 7 |
| Operator password | the database (Argon2id hash) | you | everything in the console | section 8 |
| `HELIX_METRICS_TOKEN` | `.env`, the health check | you | read the metrics only | change it, restart |
| Android release keystore and its passwords | the checkout (`app\android\helix_remote.keystore`), environment variables | **two encrypted copies off the PC** | publish an app update that phones accept | section 9 |

**Keep off the PC and out of every database backup:** the pepper, the phone
key and the keystore. Copy `.env` once into an `age`-encrypted file stored with
the offsite backup (a separate file from any dump, encrypted to the key you keep
on paper), and rehearse decrypting it. Losing the pepper orphans every account.

## 1. The JWT ring leaked

The routine procedure keeps the old key for 7 days. When the key leaked, that
is the opposite of what you want.

1. Generate a new key: 32 random bytes, base64url.
2. Replace the **whole ring** in `HELIX_JWT_KEYS` with just the new key and set
   `HELIX_JWT_ACTIVE_KID` to its id. Do not keep the old one.
3. Restart. Everyone is signed out once (the apps refresh with their refresh
   tokens, which are not JWTs, so people mostly notice nothing; operator
   sessions end, sign in again).
4. In the console, check the audit log from the time of the leak for actions you
   did not do (recovery codes, grants, price or number changes, bans).
5. If you cannot rule out that someone used an operator token: change the
   operator password (section 8) and re-check the pay-to numbers in
   Settings > Payments.

## 2. The pepper leaked (with, or without, a dump)

The pepper cannot be rotated today: it keys every stored phone hash and the
discovery index, and changing it orphans all of them.

- If **only the pepper** leaked: it is harmless without a dump. Keep it, keep
  the dump private, and treat it as a warning about where `.env` was readable.
- If **the pepper and a dump** leaked: phone numbers can be tested against the
  dump (T-5, T-9 of `THREAT_MODEL.md`). The honest options are to tell people,
  and to plan a versioned pepper with lazy re-hash at next sign-in (not built).
  Until then, prefer to shorten what a dump can hold: delete inactive accounts,
  and leave `HELIX_PHONE_KEY` unset if you do not need numbers in the console.

## 3. The phone key leaked

With a dump, the stored full numbers can be read. Set a new
`HELIX_PHONE_KEY`; the console shows last-four-digits only for an account until
its app reports the number again (the old ciphertext is unreadable, which is
what you want). Ask the person who held the dump to delete it.

## 4. The federation signing key leaked

There is no rotation tool yet (known, `THREAT_MODEL.md` T-9). While
federation is **off** (the default) the key signs nothing: nothing to do but
keep dumps private. If federation is on, turn the switch off in the console
(Settings), then plan a rotation: generate a new key and publish it through the
peers' key fetch (they log `peer_key_changed`, and the console's dashboard
counts it), after telling each peer's operator out of band that the change is
yours.

## 5. A TURN secret leaked

Change it in `.env` **and** the rendered coturn config together: set the new
value in `.env`, run `start-turn.ps1` (it restarts both relays), restart the
server. Credentials in flight stop working: a call that is running loses its
relay at the next nonce refresh (within about half a minute) and ends. The
voice and the main secret must differ.

## 6. The SMS or Firebase key leaked

- BulkSMSBD: regenerate the key in the provider's panel, put the new one in
  `.env`, restart. Check the balance and the day's count (`helix_sms_*`); the
  server's own daily cap (`HELIX_SMS_DAILY_LIMIT`) limits what a stolen key
  could not already do from the provider's side.
- Firebase: in the Firebase console, delete the leaked service-account key and
  create a new one; replace the file or the value; restart. A leaked sender
  can only send data-only wake-ups, which carry nothing.

## 7. The PostgreSQL password leaked

`ALTER ROLE helix PASSWORD '...'` in `psql` as the superuser, update `.env` and
`pgpass.conf`, restart. Check that PostgreSQL does not listen beyond this PC
(`listen_addresses = 'localhost'`, and the health check says so).

## 8. The operator password leaked

`helix-admin-tool.exe reset-password` from the production folder (it ends every
operator session and clears the lockouts), or change it in the console. Then
check the audit log for anything you did not do.

## 9. The Android keystore leaked or lost

- **Leaked:** anyone with it and its passwords can sign an update that phones
  accept as yours. Phones that have the app installed cannot be moved to a new
  key without uninstalling (the app id and the signature are tied), so plan the
  move: new keystore, new release, tell people to reinstall and sign in again
  (their history comes back from their backup).
- **Lost:** you can no longer update installed copies. Same move as above.
- Prevent both: two encrypted copies off the PC; the keystore's path and
  passwords only in the release session's environment; the operator console has
  its own keystore (`admin\android\helix_admin.keystore`), never shared.

## After any of these

Write what happened and when, in your own notes: which secret, how you found
out, what you rotated, when. If people's data could have been read, say so to
them plainly; `PRIVACY_POLICY.md` and `THREAT_MODEL.md` say what a dump holds.
