# Sweep 14f — app `core/`: the links that come from outside, and the router

**Where:** `helix_remote/app/lib/core/links/` — `deep_link.dart` (250),
`helix_code.dart` (111), `link_channel.dart` (27), `pending_link.dart` (29) —
plus `core/router/app_router.dart` (234) — 651 lines. Cross-reads:
`shared/widgets/app_link_listener.dart` (119, the only consumer that turns a
link into navigation), `main.dart:133-180` (the cold-start link),
`features/sign_in/application/sign_in_controller.dart:60-160` (how a parked
setup code is consumed), the group/people route registrations and
`test/deep_link_test.dart` (268).

The parsing is careful and tested: the shared web form is accepted only at
`/open` over `https`, the code is read from the fragment after one decode, a
`~name` is normalised in one place and checked against the server's own
pattern, the contact form requires every field and a known version, and the
codes are opaque base64url with a round-trip test. The router has the hard
parts right too: one router for the run, a redirect driven by a refresh notifier
rather than a rebuilt router, the platform default location overridden so a
crafted `https://…/anything` cannot pick the first screen, and invite codes kept
out of route locations because those are kept in history. Nothing in this sweep
is exploitable; the one finding is a path from a design that was dropped.

## Findings

### AUD-14f-1 A contact-add link is parsed with a signed payload that nothing reads

**Severity:** Idea  **Confidence:** confirmed
**Where:**
[deep_link.dart:209-235](file:///J:/Projects/helix/helix_remote/app/lib/core/links/deep_link.dart#L209-L235)
(`_contactAdd`), [deep_link.dart:109-111](file:///J:/Projects/helix/helix_remote/app/lib/core/links/deep_link.dart#L109-L111)
(the parse branch),
[app_router.dart:224-225](file:///J:/Projects/helix/helix_remote/app/lib/core/router/app_router.dart#L224-L225)
(the only consumer).
**What:** `helix://contact/add?v=1&id=…&a=…&n=…&e=…&s=…` is parsed into a
`contactAdd` link carrying a link id, account id, nonce, expiry and signature.
`routeDeepLink` responds by going to `/home/people`; no code anywhere reads the
five payload fields (`contactLinkId`, `contactAccountId`, `contactNonce`,
`contactExpiresAt`, `contactSignature` appear only in the parser). The design
that made them meaningful — a signed contact link with replay state and a
confirmation step — is in
`docs/protocol/F4_MESSAGING_PRODUCTIVITY_DESIGN.md`, and that design's "contact
request" contradicts the product rule that there are no contact requests. So a
person who receives such a link lands on the people search page with nothing
said about why the link did nothing.
**Trigger:** someone taps a contact-add link — any app or page can send one to
`helix://contact/add…`; the form is still accepted and still tested
(`deep_link_test.dart:103-122`). No current build generates one.
**Evidence:** the parser builds the object (227-234); the router's `case
HelixDeepLinkKind.contactAdd: router.go('${AppRoutes.home}/people');` is the
only use of the kind outside the parser; both files' payload fields have no
reader; `PeoplePaths.home` (`shared/navigation/people_paths.dart:5-8`) documents
the path as "also what a `helix://contact` link opens", so the destination is
deliberate and the payload is the dead part.
**Impact:** a link that looks like it should do something (add a contact, in the
old design) silently opens a search page. It is not a security issue — the
payload is ignored, not trusted — but it is dead input surface: a parser, five
fields and a route case that a future change has to keep working for no user.
**Fix sketch:** either delete the kind, the parse branch, its fields and the
test (the honest choice while no build issues such links), or, if a
contact-exchange design returns, wire the payload to that flow and refuse
expired/replayed links — the signature is there for exactly that. Leaving the
parse and discarding the payload is the one option that cannot be right.
**Test that proves it:** `deep_link_test.dart` drops the contact case with the
code, and a router test asserts a `helix://contact/add…` URI is not accepted
(or is handled with a sentence, if the second option is taken).
**Overlap:** T4 (ideas and dead paths). F4's contact links are also why the
parser's "every field is load-bearing" test exists; the finding is that the
app does not use the load.

## Verified safe

- **The web form** (`deep_link.dart:116-135`): only `https`, only `/open` or
  `/open/`, for the setup code; a `/u/<one name>` path for a person. The host
  is not trusted for anything (the code names its server, and the `/u` page is
  static), which is sound.
- **Cleartext links**: a `http://server/join?invite=…` link does parse and
  yields an `http` origin, but the address is then put through `ServerPolicy`
  (`core/engine/server_policy.dart:36-53`), which refuses `http` outside a
  debug build's loopback hosts, so no session can be opened over it. The same
  applies to `decodeHelixInviteCode`'s legacy URL branch.
- **The codes** (`helix_code.dart`): invite and recovery codes round-trip,
  trailing slashes are normalised, the invite separator is taken from the last
  `|` (so a URL cannot smuggle one), a malformed base64 or UTF-8 answers null,
  and the recognisers match the prefixes case-insensitively.
- **The channel and the parking** (`link_channel.dart`, `pending_link.dart`):
  one handler installed with the singleton, a parsed link broadcast, and a
  provider that a link can be parked in and taken from once. Sign-out and an
  account change clear it (`session_providers.dart:87, 230`), so a code cannot
  be applied by the next account's sign-in.
- **The listener** (`app_link_listener.dart`): links that need an account are
  parked and replayed when `authState` reaches ready; a setup code is refused
  with a sentence when already signed in; a person link is taken before its
  lookup starts so a failure cannot re-fire it; a group link opens a preview
  with an explicit Join, never a silent join.
- **The router** (`app_router.dart`): the startup latch cannot return to
  "Opening Orbit…"; the restore step owns its two routes; a revoked device is
  pushed off home; an account switch returns to home; the router and its
  refresh notifier are disposed together; invite codes never enter a location.

## Coverage notes

- Read in full: the five files in **Where** (651 lines) plus the listener,
  `main.dart`'s link wiring and the sign-in consumer named above.
- Not filed, weighed:
  - An invite link tapped while signed in is refused ("for setting up a new
    device") although the app has an Add account flow in Settings
    (`accounts_providers.dart:73`). That is a product choice with a clear
    sentence, not a defect; if the owner wants the link to offer Add account,
    it is a small change in `AppLinkListener._onLink`.
  - A warm link is delivered only while `AppLinkListener` is mounted; the gate
    keeps its child in a `Stack` under the lock screen
    (`app_lock.dart:265-278`), so links do arrive while locked and are routed
    behind it — no loss. A link that arrives while the process is being torn
    down is dropped by the platform channel, which no Dart code can prevent.
  - A link opened while signed out that names a call is routed and immediately
    redirected to sign-in, so the call id is lost. There is nothing to join
    without a session; a "call back" affordance would be a feature.
- Not read here: the Android `MainActivity` intent handling (native, outside
  `lib/`) and the join-group screen's own link parsing (sweep 15, groups).

## Structural proposals

**S14f-1 — a link kind exists only if a flow reads it.** Every `HelixDeepLink`
kind should be consumed by a named action (setup code, route, lookup). A kind
whose payload nothing reads — today `contactAdd` — is either a feature or dead
input, and the parser test should assert the distinction by exercising the
consumer, not just the fields.
