# REVIEW_0 — where the console prototype stands, and three ways forward

Written 2026-10-22 before any further building. Nothing in the console
prototype changes after this point until the direction is chosen.

Screenshots are in `shots/`, taken with `python tools/shoot.py --jobs 1`
(see §4 for the exact commands).

---

## 1. Audit of the current prototype against the Orbit bar

The current prototype (`index.html`, `css/`, `js/screens/`) already uses the
Orbit tokens, the floating dock, the inverse pill and the card radius. The
problems are not "it isn't Orbit-coloured" — they are hierarchy, density,
states and copy. Each point names the shot that shows it.

### Layout

- **The desktop column is 1100 px inside a 1280 px window.** Both
  `overview.window-l.png` and `users.window-l.png` waste ~180 px of margin on
  each side while the content itself is starved: an operator console on a
  Windows desktop should use the width it is given. Orbit's own pages put the
  list and the detail side by side at this size.
- **Overview is a 3×2 grid of identical cards.** Six equal boxes, each with a
  mono label, a number, a soft-blue icon tile and a caption. Nothing is first.
  The most important fact on the page (is this node healthy?) and the least
  (crash reports, 12) are the same size and the same shape.
- **The database "Ready" tile is the odd one out and it shouts.** A 34 px
  green display word in a slot the others use for a number, so it reads as the
  loudest signal on the page while carrying one bit.
- **Users is a stack of cards, not a table.** `users.window-l.png` shows seven
  88 px rows that each carry name, status pill, phone, Helix name, device count,
  join date and a report flag in three lines of text. There are no columns, so
  nothing can be sorted or scanned vertically; with the real 50-per-page that
  is 4,400 px of scrolling.
- **The detail pane repeats itself.** The header card shows Tanvir Ahmed,
  Active, +8801712345678, @tanvir, "Joined 12 Mar 2025", `acc_7N2K90`; the card
  directly under it is titled "User identity & state" and lists Phone, Helix
  name, State, Joined, Account ID — the same six facts again, ~200 px apart.
- **Dead bands.** `ops_logs.window-m.png` has a full empty band between the
  standfirst and the tab bar; `overview.window-l.png` leaves the bottom third
  of the "This server" card empty.

### Density

- Orbit's messenger screens and the real Flutter console both run at
  32–40 px rows; this prototype is 52–88 px rows with 20–24 px card padding.
  For a tool an operator watches for hours, that is the wrong trade.
- Log lines (`ops_logs.window-m.png`) are the one dense list, and they look
  right — which is the evidence that the rest can be tightened.

### Hierarchy & type

- **Eyebrow + title + nav pill say the same thing three times**: "OVERVIEW /
  Dashboard" under a pill that already says Overview; "USERS / Users &
  Devices"; "OPS & LOGS / Live Server Console".
- **Titles drift away from the nav names.** "Live Server Console" is not a
  place in the shell (`admin_shell.dart` calls it Ops & Logs → Logs). Product
  rule: plain English, sentence case, one name per thing.
- **The same status appears twice on one screen**: "Online · 42 ms" is in the
  page header *and* in the Service health card header on Overview.
- Mono uppercase with wide tracking is used for every card label, so it has
  stopped meaning anything. Orbit uses mono for values that are machine
  strings: ids, addresses, timestamps, log lines.

### Colour

- Six identical `--accent-soft` icon tiles on Overview are decoration, not
  information, and they are the only place the accent appears on the page — so
  the accent reads as "card ornament" instead of "action".
- Status colour is otherwise correct (dot + word, green/amber/red, danger kept
  for destructive). No new colour tokens are needed for the console beyond
  what `themes.py` already emits.

### States

Better than the first pass gave it credit for — and still short of the Orbit
bar. What exists: loading skeletons on every list screen, empty and error per
screen, Overview's degraded and offline variants, a typed `BAN` confirmation
plus a reason field for suspend and revoke, and a paused state for Logs.

What is missing:

- **No session-ended / no-permission state.** The real API answers 401 on any
  call after a sign-out or a password change (`tokens_valid_after`); the
  prototype can only show the generic error card, which tells the operator the
  wrong thing.
- **No long-data states at all.** `data.js` has 8 accounts and the longest
  name is "Sabrina Chowdhury". There is no 10,000-row list, no 2× text, no
  overflowing display name, Helix name or reason string anywhere in the
  prototype — and those are exactly the cases that break a dense table.
- **No bulk selection.** Nothing in `js/screens/` selects rows, so there is no
  bulk bar, no partial-failure result and no bulk confirmation. (The real API
  has no bulk route either — see §2's wishes — so it must be drawn as N calls.)
- **Logs has no level filter as a control** (it is folded into one text box
  with `q: 'warn'`), **no explicit follow toggle**, and **no saved views**.
- **No relative time.** Every timestamp is absolute (`11:41:02.332`,
  "Last seen 22 Oct 2026"); nothing says "4 min ago" with the exact value on
  hover, and there is no refresh stamp next to the Refresh button.
- **Keyboard is Escape only** (`app.js:354`). No `/` to search, no `j`/`k` to
  move, no `?` for the shortcut sheet.

### Copy

- "Live Server Console", "User identity & state", "Worldwide mode & peer
  network" — invented section names rather than plain English.
- The standfirsts explain the screen to nobody ("The server's state, health and
  counts for this node."). An operator needs the *scope caveat* — node-lifetime
  counters, this node only — which is present but demoted to a footnote with an
  ⓘ.
- The Logs screen claims "full phone numbers never reach this stream" while the
  lines print `ip=37.111.22.8`; either drop the claim or drop the value.

### Accessibility & phone

- Tap targets on the phone shots are 34–40 px in places (`overview.phone.png`
  Refresh pill, filter chips in `users.phone.png`) — under the 48 px rule.
- **Phone metric labels wrap.** "ACTIVE DEVICE CONNECTIONS" and "FAILED
  BACKGROUND JOBS" break onto two lines in a two-column card grid, so cards
  come to different heights and the grid looks broken.
- **The dock covers content.** In `overview.phone.png` the "FCM push" row sits
  under the floating dock; the scroll container does not reserve the dock's
  height plus a margin.
- The dock's inactive tabs are icon-only and ambiguous (people vs gear):
  Overview's active pill pushes them apart and there is no label until tapped.
- Every icon button in the prototype has a `title`/`aria-label`; keep that.

---

## 2. Feature inventory — taken from the code, not guessed

Sources read: `helix_remote/admin/lib/src/features/*` (21 files, 4,505 lines),
the 26 `admin*` routes plus `metrics` in
`packages/helix_remote_protocol/lib/src/routes.dart`, and
`server/lib/src/modules/admin/MODULE.md`.

### The console's real places

`admin_shell.dart` defines exactly four: **Overview**, **Users & Devices**
(short title "Users"), **Invites** (only when the node registers by invite
code), **Ops & Logs** — and `ops_screen.dart` puts Reports, Audit, Logs and
Config behind one segmented bar. Sign-in, the lock screen and Settings exist
outside the bar. So the shell has 4 + 2 surfaces, and any design must keep
those names.

### Every feature, and where it lives in the new design

| # | Feature (real) | Code | Route | Home in the new console |
|---|---|---|---|---|
| 1 | First-run setup (once, creates the operator) | `auth/sign_in_screen.dart` | `GET`/`POST /v1/admin/setup` | Sign-in screen, setup variant |
| 2 | Sign in (email-less: admin id + password) | `auth/sign_in_screen.dart` | `POST /v1/admin/sessions` | Sign-in |
| 3 | Lockout feedback (10/min/IP; 5 fails → 15 min doubling to 24 h; global 100 cap) | `sign_in_screen.dart` | same, `Retry-After` | Sign-in, failed state |
| 4 | App lock (biometric/PIN on the console device) | `auth/lock_screen.dart` | none (local) | Locked screen |
| 5 | Sign out (ends *every* admin session) | `settings_screen.dart` | `DELETE /v1/admin/sessions` | Account menu, typed confirm |
| 6 | Change admin password (ends other sessions; 12–256, Argon2id) | `settings_screen.dart` | `PUT /v1/admin/password` | Settings |
| 7 | Node facts: public address, node id, version, sign-up mode, attachment limit, signed-in-until | `dashboard_screen.dart`, `settings_screen.dart` | `GET /v1/admin/config` | Overview "This node" + Settings |
| 8 | Server name (editable) | `settings_screen.dart` | `PATCH /v1/admin/config` `server_name` | Settings |
| 9 | Maintenance mode on/off | `settings_screen.dart` | `PATCH` `maintenance` | Overview status strip + Settings, typed confirm |
| 10 | Federation on/off + domain | `settings_screen.dart` | `PATCH` `federation_enabled` | Overview node card + Settings |
| 11 | Integrations readiness: push, SMS, TURN (yes/no + provider name or relay count) | `dashboard_screen.dart` | `GET /v1/admin/config` `integrations` | Overview service-health list |
| 12 | Feature flags (allow-listed: `minimal_analytics`, `group_calls`) | `settings_screen.dart`, `common/feature_controller.dart` | `GET /v1/admin/feature-flags`, `PUT /{name}` | Settings flags card |
| 13 | Purge dead jobs and expired identity rows (counts by kind) | `settings_screen.dart` | `POST /v1/admin/purge` | Ops actions, typed confirm |
| 14 | Metrics: requests, server/client error share, open websockets, mailbox backlog, dead jobs, crash reports, jobs ok/retry/dead | `dashboard/metrics_summary.dart` | `GET /v1/ops/metrics` | Overview signal strip |
| 15 | Account list, cursor-paged, filter `status`, search `q` (Helix-name prefix or last 4 digits) | `accounts/accounts_screen.dart` | `GET /v1/admin/accounts` | Users list |
| 16 | Account row fields: status, created_at, active_devices, helix name, phone, display name, last_seen_on | `AdminAccount` DTO | same | Users table columns |
| 17 | Account detail: devices, has_password, open_reports | `account_detail_screen.dart` | `GET /v1/admin/accounts/{account}` | Users detail pane |
| 18 | Device list per account + revoke (full revoke purges keys and mailbox, closes the socket) | `account_detail_screen.dart` | `DELETE …/devices/{device_id}` | Detail pane, typed confirm |
| 19 | Suspend / unsuspend (account keeps its devices) | `account_detail_screen.dart` | `PUT`/`DELETE …/suspension` | Detail + bulk bar, typed confirm |
| 20 | Ban (bans the phone hash, then deletes) | `account_detail_screen.dart` | `POST …/ban` | Detail only, typed confirm |
| 21 | Delete account (devices, keys, undelivered messages, backups; does not ban the phone) | `account_detail_screen.dart` | `DELETE …/{account}` | Detail danger zone, typed confirm |
| 22 | Issue a recovery code (48 h, single use, shown once) | `account_detail_screen.dart` | `POST …/recovery-codes` | Detail, one-time reveal dialog |
| 23 | Invites: list, create (code shown once), cancel; stored hashed | `invites/*` | `GET`/`POST /v1/admin/invites`, `DELETE /{id}` | Invites |
| 24 | Reports: list by status, resolve or dismiss (only while open); no phone, no message content | `reports/*` | `GET /v1/admin/reports`, `PUT /{report_id}` | Ops → Reports |
| 25 | Open-report badge kept across filter changes | `ops_screen.dart` | `GET …/reports?status=open` | Reports tab + Overview queue |
| 26 | Audit trail, newest first, 365-day retention | `audit/*` | `GET /v1/admin/audit` | Ops → Audit |
| 27 | Recent log lines (this node, redacted) | `logs/*` | `GET /v1/admin/logs` | Ops → Logs |
| 28 | Live log stream over WS, token rechecked every 60 s, 4001 when the token dies | `logs_controller.dart` | `GET /v1/admin/logs/stream` | Ops → Logs, live state |
| 29 | Reason string on every action (≤500 chars, redacted, audited) | `AdminActionRequest` | all mutating routes | Every confirmation dialog |
| 30 | Session expiry visible; 12 h tokens, no refresh | `settings_screen.dart` | `GET /v1/admin/config` | Header account menu |

Nothing in the real console is left without a home, and nothing above is
invented.

### Wishes — marked "needs backend", not to be designed as if they worked

- **Request/error time series and day-over-day deltas.** `GET /v1/ops/metrics`
  returns node-lifetime counters that reset on restart; there is no windowed
  series. A sparkline or a "+2.1%" would be a lie. *(needs backend)*
- **Total account / report / audit counts.** `Page<T>` carries only
  `next_cursor`. "10,000 results" cannot be shown; "N loaded · end of list"
  can. *(needs backend)*
- **Crash reports broken down by platform/version.** The count exists; the
  breakdown does not. *(needs backend)*
- **Bulk endpoints.** Suspend, ban, delete, revoke and recovery codes are all
  per-account routes. A bulk action in the UI must fan out into N calls with a
  per-item result — the design may show it, but must show it as N calls.
  *(needs backend for an atomic bulk route)*
- **Saved views / column chooser persisted for the operator.** No admin
  preferences API exists. Local to the browser/device only, like the Orbit
  theme setting. *(needs backend for cross-device)*
- **Report search, report paging beyond `status`, per-account report list
  inside the detail pane.** Detail returns only `open_reports` (a count).
  *(needs backend)*
- **Audit filter by actor/action/date.** `GET /v1/admin/audit` is list-newest-
  first with a cursor only. Client-side filtering of loaded rows is honest;
  presenting it as a server query is not. *(needs backend)*
- **Multiple nodes / a fleet view.** One console session is one node
  (`session.serverAddress`). Everything shown is "this node". *(needs backend)*

### One correction to the brief: ADR-030 and phone numbers

The brief said "full number in reports, last four elsewhere". The code is the
other way round. `AdminAccount` gives the console the **full phone number and
display name** for accounts whose app has reported them (opened from
`phone_sealed` with `HELIX_PHONE_KEY`) — see `accountPhone()` in
`admin/lib/src/features/common/format.dart` — while **reports carry no phone at
all**. So:

- Users list/detail may show the full number (that is what the operator is
  allowed to see), with the last-4 fallback for accounts that never reported.
- Reports must never show a number.
- Search is by Helix-name prefix or last 4 digits — you cannot search a full
  number that isn't there.

The three boards below show masked numbers (`•••• 4568`) so the *comparison* is
about layout, not about who can see what. Say the word and the built screens
will show the full number on accounts, as the real console does.

---

## 3. Three directions — Overview and Users only

All three are built from the same generated token file
(`directions/themes.css`, copied from `orbit/prototype/directions/themes.css`),
the same real DTO-shaped data, and the same set of interactions. No colour is
hard-coded in any of them. Contrast for `orbit` and `night` is 0 failures
(§4). Each has a desktop and a phone board.

### A — "Control room"
**Idea: the node is an instrument; a permanent dark rail and a one-line status
strip mean you always know where you are and how the box is doing.**
A 68 px inverse navigation rail (labels always visible, so no ambiguous
icon-only tabs), a 54 px status strip that carries node name, version,
readiness, maintenance and the last refresh in one line, a 4-cell signal strip
instead of six equal cards, flat hairline panels rather than shadowed cards,
and on Users a dense 34 px table with a bulk bar and a 368 px detail pane.

- `shots/a-overview.window-l.png` · `shots/a-users.window-l.png`
- `shots/a-overview-phone.phone.png` · `shots/a-users-phone.phone.png`

### B — "Editorial ledger"
**Idea: rules and type do the hierarchy, so nothing needs to be a card.**
A masthead with a 2 px ink rule and text tabs, a 42 px sentence-case title with
a standfirst, a facts strip bordered top by a single hairline and split by
vertical rules, a 1.55fr/1fr main split where the right column is separated by
a border rather than a box, a 54 px lead number with a 9 px outcome bar, and on
Users an underline search, text filters, a borderless table and an inverse
(dark) selection bar.
- `shots/b-overview.window-l.png` · `shots/b-users.window-l.png`
- `shots/b-overview-phone.phone.png` · `shots/b-users-phone.phone.png`

### C — "Quiet cards"
**Idea: the calm version of a real console — a grouped sidebar, one facts card,
and soft cards only where a group of decisions lives.**
A 236 px sidebar with grouped destinations (Console / Operations) and a
warning pill on the open-report count, a 52 px top bar with the date and a
success-soft status pill, one 4-column facts card, a 2×2 grid of soft 14 px
cards with the real `jobsFinished` breakdown inside the Requests card, and on
Users a segmented status control, a 54 px table, an accent-soft bulk bar and a
detail card whose destructive actions sit in a tinted danger zone.
- `shots/c-overview.window-l.png` · `shots/c-users.window-l.png`
- `shots/c-overview-phone.phone.png` · `shots/c-users-phone.phone.png`

### How they differ where it matters

| | A Control room | B Editorial ledger | C Quiet cards |
|---|---|---|---|
| Desktop width used | full, rail + panels | 1240 px, rules | 1120 px, cards |
| Rows per screenful (Users) | ~20 at 34 px | ~16 at 40 px | ~12 at 54 px |
| Navigation | dark rail, always labelled | masthead text tabs | grouped sidebar |
| Card usage | none (flat panels) | none (hairlines) | soft cards, one per decision group |
| Bulk bar | accent-soft | inverse | accent-soft |
| Feels like | an ops console | a newspaper of record | the messenger's own settings |
| Risk | cold if the rail is too dark | type-heavy; needs care at 2× text | drifts back toward the current prototype |

---

## 4. Reproducing this review

```
cd console/prototype
python serve.py                      # http://127.0.0.1:5318 (leave running)
python tools/shoot.py --device window-l --page "directions/control.html?screen=overview"  a-overview
python tools/shoot.py --device window-l --page "directions/control.html?screen=users"      a-users
python tools/shoot.py --device phone    --page "directions/control.html?screen=overview"  a-overview-phone
python tools/shoot.py --device phone    --page "directions/control.html?screen=users"     a-users-phone
# same three lines with editorial.html -> b-*, quiet.html -> c-*
```

`--jobs 1` is the default and must stay: higher job counts have captured
unstyled pages. Phone shots are captured in a 640×866 window, so the white
strip at the right of every `*.phone.png` is the capture window, not the app.

Contrast (Orbit and Orbit Night, token pairs from
`orbit/prototype/tools/themes.py`, checked without running its `main()`
because that writes into `helix_remote/`): `orbit OK`, `night OK`,
**0 failures**.

---

## 5. What happens after you choose

1. Shell, tokens and the state kit for the chosen direction (no screens yet).
2. Batches in this order: Overview; Users and devices; Reports; Audit; Logs;
   Ops and config; Invites; Sign-in and settings. Each batch: every state
   (loading, empty, failed, offline, no permission, long data, 2× text) on
   phone, window-m, window-l and bare mode; a `SCREENS.md` update with the
   feature checklist and "Design changes you approved"; screenshots; then I
   stop for your review and commit once, marked "(pending review)".
3. Only after the last batch is approved: `console/PORT_PLAN.md` and
   `console/contracts/`. No Flutter or Dart work before that.

**Stopped here: pick A, B or C** (or a mix, e.g. "A's rail with C's table").
Nothing else gets built until you answer.
