# Orbit plans and sponsored placements: plan

Status: **proposal, nothing built** (2026-10-27). Planning only. The numbers (prices, limits) are
placeholders to decide; every other section is a recommendation grounded in the code as it is.
Scope: Helix Remote (Orbit) on Helix Global. Never `helix_local/`.

## 1. Goals and non-goals

Goals
- Let Orbit earn money without breaking what the product promises: end-to-end encryption, small
  metadata, no tracking.
- Plans with different limits and extras; an ad system for the free plan.
- Server-authoritative: the server decides what an account may do. The app only shows it.
- Ship in small steps, each safe to deploy with the feature flag off.

Non-goals
- No ad network or third-party SDK (see 3.1; this is the main decision).
- No targeting by behaviour, contacts, content or location. No ad ID.
- Never paywall: sending and receiving messages, 1:1 calls, E2EE, backup and restore, linking devices,
  safety numbers, app lock, account export and deletion. Free stays a complete messenger.
- Personal servers (hidden advanced mode) get everything unlocked and no ads.

## 2. What the repo already says (constraints)

| Source | Constraint |
|---|---|
| `PRIVACY_POLICY.md`, `PRIVACY_CLAIM_MATRIX.md`, `APP_STORE_PRIVACY.md` | "No behavioural advertising or cross-context tracking", "No sale of personal data", "Advertising ID is not collected" (manifest has no `AD_ID`), third-party integrations are "reviewed before any is added". An ad network breaks all four. |
| E2EE and ADR-017 | The server cannot read content, so content targeting is impossible, and must stay impossible. |
| `orbit/PORT_PLAN.md` Part C item 9 | Premium themes were already planned for later; on Android, selling digital items needs Google Play Billing. |
| ADR-033 | Packs are signed data; the app holds the publisher keys. Reuse this for ad creatives. |
| `media/MODULE.md` | Today's limits (4 GiB attachment quota, 5 MiB persistent, 1 GiB backup; attachments kept 30 days, backup 90) are the natural server-enforced plan levers. |
| ADR-034 | Group calls are a mesh capped at four people. Do not sell "bigger group calls". |
| `AGENTS.md` | Public routes need `r.public(...)` and a rate-limit policy; modules talk only through `api.dart`; new package or module dependency goes in `v2PackageDependencies`; wire changes start in `helix_remote_protocol`; target-architecture changes need an ADR and a user-approved change-log entry; Orbit screens follow the prototype ("don't invent"). |
| Terms of service | Already allows suspension for "nonpayment of any applicable fee" and forbids unsolicited advertising by users; needs a paid-plan and ads section. |

## 3. Key decisions (recommended answer first)

### 3.1 Ads: first-party and sold directly, not an ad network
- **Recommended:** Helix Global serves a small catalogue of ads the operator sells or approves
  (local businesses, partners, house ads for Plus). No SDK, no third-party requests, no tracking pixels,
  no ad ID. Creatives are signed by the operator key and checked by the app before drawing (the ADR-033
  idea), so a hacked server cannot push a phishing ad.
- Rejected: AdMob or similar. It needs the ad ID, a data-safety disclosure of sharing, and breaks the claims
  above. It could be added only after an ADR rewrites those claims; not recommended for a privacy product.
- Trade-off: revenue per user is lower and sales are manual. Fine for a first market; the system is built
  so a self-serve advertiser portal can come later.

### 3.2 Plans (placeholders)

| | Free | Plus | Pro |
|---|---|---|---|
| Messaging, 1:1 and group calls, backup, devices | yes | yes | yes |
| Ads | sponsored rows | none | none |
| Attachment quota | 4 GiB (today) | 15 GiB | 50 GiB |
| Max file size | today's `HELIX_MAX_ATTACHMENT_BYTES` | 2x | 4x |
| Attachment kept on server | 30 days (today) | 60 days | 90 days |
| Linked devices | today's cap | same | +more |
| Premium theme, ringtone and animation packs | basic two themes | all packs | all packs + early access |
| Full-backup size | 100 MiB (today) | 250 MiB | 500 MiB |
| Profile badge, custom app icon | no | yes | yes |
| Price | free | e.g. BDT 99 a month, yearly discount | e.g. BDT 249 a month |

Rules: Free equals today's behaviour, so nothing regresses. Plan definitions live **in code** (a typed
catalogue with a version number), not in a table, so they are reviewed and tested; the admin console can
override a limit per account for support cases. Two paid tiers are enough to start; Pro can wait
(keep the model "N tiers", ship Plus first).

### 3.3 How people pay
- **Android:** Google Play Billing (mandatory for digital goods on Play). Server verifies every purchase with
  the Play Developer API and listens to Real-time Developer Notifications.
- **Windows app:** Play Billing does not exist there (`in_app_purchase` has no Windows support). Options:
  redeem codes, a web checkout (SSLCommerz, bKash or Stripe, depending on where the money must land),
  or the Microsoft Store. **Needs the owner's decision** (section 12).
- **Redeem codes** (admin-issued: "1 month Plus") come first. They work on both platforms, need no payment
  provider, and prove the entitlement pipeline end to end before real money moves. Mirrors invite codes
  (hashed at rest, shown once, rate-limited redemption).
- Whether Play in Bangladesh offers local methods (bKash, carrier billing) must be checked in Play Console
  before pricing is fixed; I have not verified it.

## 4. Architecture

Two new server modules, each a normal module (`module.dart`, `MODULE.md`, `api.dart`, `http/`, `application/`,
`data/`, `domain/`). Both are inert unless enabled.

### 4.1 `billing` module (schema `billing`)

Tables (migration 1 in the module):
- `subscriptions`: account_id, plan, source (`play` | `code` | `admin` | later `web`), status
  (`active`, `grace`, `on_hold`, `cancelled`, `expired`), period_end, auto_renew, grace_until,
  external_ref (purchase token sealed under `HELIX_BILLING_KEY`, plus a keyed hash for lookup),
  created/updated. One live row per account; history kept as rows with an end state.
- `billing_events`: idempotency log for webhooks (event id unique, kind, account, outcome). No payloads
  stored beyond what is needed to replay.
- `redeem_codes`: code hash, plan, duration, single use, expiry, created_by (admin), redeemed_by/at.
- `entitlement_overrides`: account_id, limit key, value, reason, by admin, expiry (support cases).

Entitlements:
- `Entitlements` is a small immutable value type in `kernel/` (plan id, limits, features, `adsEnabled`).
  Other modules call `BillingApi.entitlements(accountId)` (the only import) and never read billing tables.
- Computed from the live subscription plus overrides; a missing or expired row means Free. Cached per account
  with a short TTL and invalidated by a bus event `billing.entitlements_changed`.
- Server enforcement points: `media` (quotas, max size, retention at upload time), `identity` (linked-device
  cap), `backup` (envelope size). Each reads the entitlement when it decides, so downgrade needs no cron.
- **Downgrade is never destructive.** Over quota means "no new uploads"; existing objects live out their normal
  expiry. A lapsed subscription gets a grace period (Play grace/hold states honoured, plus 3 days).

Routes (catalog in `helix_remote_protocol/lib/src/modules/billing.dart`, documented in `REST_V2.md`):

| Route | Access | Purpose |
|---|---|---|
| `GET /v1/billing/plan` | session | current plan, limits, period end, source, whether purchase is possible here |
| `POST /v1/billing/play/verify` | session | client sends the purchase token after a Play purchase; server verifies, links to the account, acknowledges |
| `POST /v1/billing/redeem` | session | redeem a code; per-account lockout like password attempts |
| `POST /v1/billing/play/notifications` | **public** (new; snapshot test changes on purpose) | Pub/Sub push from Google; authenticated by verifying Google's OIDC JWT (audience, issuer, service account), not by a session; own rate-limit policy |
| admin: `GET/PUT/DELETE /v1/admin/accounts/{id}/plan`, `POST/GET/DELETE /v1/admin/redeem-codes`, `GET /v1/admin/billing/summary` | admin | grant, revoke, codes, counts by plan (no money amounts from the server beyond counts) |

Realtime: tell the account's other devices to refresh with an `account_signal` subtype (the kind already
exists), so a purchase on the phone updates the PC within seconds.

Security specifics
- Never trust a client claim of "premium". The only client input is a purchase token, verified server-side.
- Bind the Play purchase to the account with `obfuscatedExternalAccountId` = keyed hash of the account id
  (never the raw id or phone). A token already bound to another account is refused (`409`), so one purchase
  cannot unlock many accounts.
- Webhooks and verify are idempotent (event id, token hash). Out-of-order notifications resolve by asking
  Google for current state instead of trusting the message.
- Purchase tokens, codes and receipts go into the redacting logger's deny list, with a test that asserts it
  (AGENTS.md rule: no tokens in logs).
- Account deletion: a hook purges billing rows. If a Play subscription is still active, the delete page warns
  "this will not cancel your Play subscription" with a link to Play subscriptions (the server cannot cancel it).
- Account export gets a `billing` section (plan, dates; no tokens). Admin actions write `audit` rows.
- Federation: plans are per home account and never federated.

### 4.2 `ads` module (schema `ads`)

Tables:
- `campaigns`: id, advertiser label (internal), placement, headline, body, call-to-action label, https target
  URL, image object id (public, non-encrypted bucket on Helix Global), locale list, platform list, weight,
  start/end, daily delivery cap, status (`draft`, `approved`, `paused`, `ended`), signature.
- `campaign_days`: campaign id, day, impressions, clicks. **Aggregate counters only**, no account or device
  column. Advertisers get totals from the operator.

Delivery:
- `GET /v1/ads/feed?placement=&locale=&platform=` (session). For accounts whose entitlement has
  `adsEnabled = false` the answer is an empty list without a database read of campaigns. For Free it returns
  up to N approved, in-date creatives, each with an operator signature over a canonical form
  (id, text, URL, image digest, validity window).
- The app verifies the signature against a trust anchor in the build (`--dart-define` like
  `HELIX_PACK_PUBLISHERS`; ads use their own key), fetches the image by digest, caches it, picks by weight
  with a **local** frequency cap, and counts impressions and clicks locally.
- `POST /v1/ads/report` (session): the app uploads per-campaign counts once a day, no ids beyond the
  campaign id; the server adds them to `campaign_days` and stores no account link. Counts are
  self-reported and capped by a plausibility check; acceptable for directly sold ads.
- Targeting is limited to placement, language, platform and (if the operator wants) a region the app sends
  from the device locale. Nothing is stored per account. No personalisation setting is needed because there
  is no personalisation, and the "Why am I seeing this?" sheet says so.

Rules for what may appear
- Placements: a labelled **Sponsored** row in the Chats list (below the first N chats, never above a
  conversation the person is using), a card on the Calls tab, and a card on the Settings home. **Never** inside
  a conversation, call screen, notification, lock screen, sign-in or backup flows.
- The target URL opens only after a confirm sheet showing the domain, in the system browser. https only, and
  the host must be in the signed creative. No third-party images, no scripts, no HTML: text and one image.
- Frequency caps (impressions per ad per day), a master off switch, and `Remove ads - Plus` on each ad.
- Operator content policy (no adult, gambling, loans, political, scam-adjacent), reviewed in the admin
  console before `approved`; approval writes an audit row.

## 5. Wire contract and clients

- `helix_remote_protocol`: `modules/billing.dart`, `modules/ads.dart` (DTOs), routes in `routes.dart`, error
  codes (`plan_required`, `quota_exceeded` gains `reason: plan`, `purchase_token_in_use`, `code_invalid`),
  `REST_V2.md`, golden fixtures updated deliberately.
- `helix_remote_api`: `billing_client.dart`, `ads_client.dart` (route-parity test requires exactly one method
  per route).
- `helix_remote_engine`: `plan` feature (fetch and cache entitlements, refresh on the account signal and on
  resume) and an ad service (feed, local cap and counters, daily report). Prefer the existing settings store
  or a file cache like `ThemePackStore` over a drift schema change; if a table proves necessary, that is a
  schema 8 to 9 step migration with schema dump and codegen.
- `app/lib/core/billing/`: a Play Billing connector over `in_app_purchase`. A new plugin means regenerated
  registrant files to commit, and entries in the dependency risk register and lockfile policy (CI enforces
  both). On Windows `canPurchase` is false and the page shows redeem and the website instead.
- `app/lib/features/plans/` (Riverpod + presentation): You > Orbit Plus page: current plan, compare table,
  upgrade, redeem a code, restore purchase, "manage in Google Play". `app/lib/features/ads/`: placement
  widget used by Chats, Calls and Settings.
- `orbit_ui`: the plan page, the sponsored row and card, the confirm sheet and "why this ad" sheet (models in,
  actions out). **These screens are not in the prototype, so by the Orbit rules I need your designs or approval
  of a proposal before building them.**
- Premium packs: a pack manifest gains an optional `tier` field (ADR-033 amendment, format change). The app
  hides or locks packs above the account's plan. This is a **soft** gate: pack bytes are public signed data and
  a modified build could bypass it, which is acceptable for cosmetics. Anything that costs real server
  resources (storage, size, retention) is enforced on the server.
- `admin` console: Plans (counts, grants, overrides), Codes, Ads (campaigns CRUD, preview, approve, stats),
  Flags. Admin UI rules apply (tooltips, 48 px, theme colours).
- Config (flags and env): feature flags `billing_enabled` and `ads_enabled` (allow-listed in the ops flags,
  default off); env `HELIX_BILLING_KEY` (seals purchase tokens), `HELIX_PLAY_PACKAGE_NAME`,
  `HELIX_PLAY_SERVICE_ACCOUNT_JSON` path, `HELIX_PLAY_PUBSUB_AUDIENCE`; ad signing key held offline like the
  pack seed in `secrets/` (public half in the build). I will tell you the exact lines at each step and update
  `V2_SERVER_HANDOFF.md` and `.env.example`; I will never touch the live `.env`.

## 6. Privacy, legal and store paperwork (part of the work, not an afterthought)

- ADR-035 (entitlements and plans) and ADR-036 (first-party privacy-preserving ads), plus a user-approved
  entry in the architecture plan change log (new modules change the target architecture).
- Update `PRIVACY_POLICY.md` (ads exist, no tracking, what the plan record holds), `PRIVACY_CLAIM_MATRIX.md`
  (rewrite the "no behavioural advertising" and "no ad ID" rows to the true, narrower claims with evidence
  tests), `METADATA_INVENTORY.md` (subscription record and aggregate ad counters), `APP_STORE_PRIVACY.md`
  (Play "contains ads" declaration; Data safety: purchase history; no ad ID), `RETENTION_AND_DELETION.md`,
  `THREAT_MODEL.md` (fake ads, receipt fraud, webhook spoofing), and the terms (paid plans, auto-renewal,
  refunds via Play, ads, termination). New terms need a new `HELIX_TERMS_VERSION`.
- A tax and business-registration question exists for BDT revenue and Play payouts. That is yours to settle
  with an accountant; nothing in code depends on it.

## 7. Testing

- Server (real Postgres): plan computation, expiry and grace, quota and size enforcement by plan, downgrade
  keeps data, code redeem and lockout, Play verify with a faked Google client, token bound to one account,
  webhook idempotency and out-of-order delivery, public-route snapshot, ad feed empty for Plus, ad
  signature, counters hold no account link, redaction test for tokens, deletion hook, export section.
- `server/test/client/`: engine and api driven against the server for plan fetch, redeem, and ad report.
- Architecture tests: modules only import `api.dart`; `billing` and `ads` added to the dependency map;
  no ad SDK or `AD_ID` in app manifests (extend `product_rules_test`).
- Packages and app: protocol golden fixtures, api route parity, engine unit tests (frequency cap, daily
  report), widget tests for plan page, sponsored row, confirm sheet; rule tests (tooltips, 48 px, no raw
  colours, English only) cover the new UI.
- Manual on device (cannot be automated): a Play test purchase with a licence tester, cancel, grace, refund,
  on two devices. Report that honestly as untested until you run it.

## 8. Phases (each ships with its flag off, in this order)

| Phase | Content | Size | Server migration |
|---|---|---|---|
| P0 | Decisions in section 12, ADR-035 and ADR-036, change-log entry, doc updates | S | none |
| P1 | `billing` module: plans in code, `subscriptions`, `entitlement_overrides`, `GET /v1/billing/plan`, admin grant and revoke, media/identity/backup read entitlements; everyone is Free so behaviour is unchanged | L | billing 1 |
| P2 | Redeem codes (server, api, engine, app plan page with Redeem, admin Codes). First real use: you hand out codes after taking payment by hand | L | billing 2 |
| P3 | Ads: `ads` module, signed creatives, feed and report, admin campaigns, Chats/Calls/Settings placements, `ads_enabled` flag, Plus removes ads | L | ads 1 |
| P4 | Google Play Billing: connector, verify, RTDN public route, grace and hold, restore, delete-account warning | L | billing 3 |
| P5 | Windows purchase path (web checkout or Store), per your decision | M-L | possibly billing 4 |
| P6 | Premium packs gate (`tier`), extra Plus perks, advertiser stats export, optional self-serve advertiser portal | M | none |

P1+P2 deliver a working paid-plan system with no payment-provider risk; P3 can run in parallel with P2
once P1 is in. After each phase I report: what changed, tests with real numbers, whether a new APK is needed
(P2 onward: yes), whether the server must restart and migrate (always: yes, new migration), and any `.env`
line to add.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Ads or payments damage the privacy reputation | First-party only, no ID, signed creatives, narrow honest claims, "why this ad" sheet, Plus removes ads |
| Play rejects the app (policy on billing or ads) | Use Play Billing for Android digital goods; declare ads; no off-store pricing links on Android |
| Receipt fraud or one purchase shared | Server verification, account binding, idempotent events |
| Webhook spoofing | Verify Google's OIDC token; fall back to asking Google for state |
| Paying user loses access by mistake | Grace and hold states, overrides in admin, never destructive downgrade, restore purchase |
| Quota or retention changes strain the PC server | Plan limits capped under the existing server-wide storage budget; TURN relay UDP range still bounds calls |
| Self-reported ad counts are inflated | Plausibility caps; direct sales rely on trust; revisit if scale grows |
| Scope creep into a store of everything | Ship P1-P3 first; Pro and packs wait |

## 10. What this does not change
Cryptography, message routing, content types, the wire format of messages, `helix_local/`, personal-server
behaviour, and the rule that screenshots stay allowed.

## 11. Open questions I could not settle from the code
- Does Play offer bKash or carrier billing for your users in Bangladesh? (Check in Play Console.)
- Is the Windows build distributed outside the Microsoft Store? (Decides P5.)
- Is there a legal entity that can receive Play and gateway payouts?

## 12. Decisions needed from you before P0
1. **Ads model:** first-party sold ads only (recommended), or also consider an ad network after rewriting the privacy claims?
2. **Plans:** ship Free + Plus first (recommended) or Free + Plus + Pro together? Which limits matter most?
3. **Windows payment path:** redeem codes only at first, web checkout, or Microsoft Store?
4. **Placements:** Chats list + Calls tab + Settings home (recommended), or fewer?
5. **Who sells ads and who designs the plan/ad screens** (the Orbit prototype has neither)?
