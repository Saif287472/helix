# Sweep 17b — `admin/` console: accounts, ops, logs, reports, audit, invites

Read-only. Scope: the console's feature screens and controllers
(`features/accounts/{accounts_controller.dart 120, accounts_screen.dart 348,
account_detail_screen.dart 566}`, `features/settings/settings_screen.dart 598`,
`features/ops/ops_screen.dart 80`, `features/logs/{logs_controller.dart 190,
logs_screen.dart 303}`, `features/reports/{reports_controller.dart,
reports_screen.dart 301}`, `features/audit/{audit_controller.dart,
audit_screen.dart 196}`, `features/invites/{invites_controller.dart 44,
invites_screen.dart 189}`, `features/dashboard/{dashboard_screen.dart 438,
server_controller.dart 221, metrics_summary.dart 109}`,
`features/common/format.dart` 63, `widgets/dialogs.dart` 333), the console kit
where a screen's behaviour depends on it, and the feature tests
(`accounts_test.dart` 444, `invites_reports_audit_test.dart`, `logs_test.dart`,
`settings_test.dart`, `dashboard_test.dart`, `error_text_test.dart`,
`metrics_summary_test.dart`). Session, transport and the shell are
`17a_admin_session.md`.

## What is sound

- **Destructive actions are heavy in proportion to their cost.** Ban and
  delete need the word `BAN`/`DELETE` typed (`phrase:` on a reason dialog, or
  the typed-confirm dialog); revoke, invite cancel and suspend ask first;
  suspend's reason is optional and goes to the audit log
  ([account_detail_screen.dart:79-179](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/accounts/account_detail_screen.dart#L79-L179),
  [dialogs.dart:65-170](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/dialogs.dart#L65-L170),
  [accounts_test.dart:259-320](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L259-L320)).
- **Failed actions never claim success.** Every action goes through
  `attempt`, which reports the failure to the session and returns operator
  text; a failed suspend leaves the account unsuspended
  ([feature_controller.dart:29-37](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/common/feature_controller.dart#L29-L37),
  [accounts_test.dart:238-257](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L238-L257)).
  Switch state follows the server's answer, not the tap (`_patch` replaces
  `_config`; a feature flag is written only on success)
  ([server_controller.dart:158-202](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L158-L202)).
- **One-time codes are handed to the caller and kept nowhere.** No controller
  field holds a recovery or invite code (pinned by a rules test), only two
  files read one, and the dialog is the only place it is rendered
  ([rules_test.dart:229-257](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L229-L257),
  [accounts_test.dart:344-367](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L344-L367)).
- **Paging is cursor-based with a generation guard.** A refresh that overtakes
  an older one wins; a failed first page is an error state with retry, a failed
  "load more" keeps what is shown
  ([feature_controller.dart:42-138](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/common/feature_controller.dart#L42-L138),
  [accounts_test.dart:131-169](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L131-L169)).
- **The log is a tail, never a store.** At most 1000 lines in memory, filtering
  is client-side, redaction is the server's, a dropped socket falls back to
  polling and says so, and nothing is written anywhere
  ([logs_controller.dart:51-189](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/logs/logs_controller.dart#L51-L189)).
- **Dashboard numbers are the server's or a dash.** A family the server did
  not report, or a `NaN`, stays null and renders "—", never a zero; the parser
  ignores junk and unknown families
  ([metrics_summary.dart:53-108](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/metrics_summary.dart#L53-L108)).
- **Error text is built from codes, never from the server's wording**, and a
  5xx carries the request id so the operator can find it in the log
  ([error_text.dart:8-49](file:///J:/Projects/helix/helix_remote/admin/lib/src/api/error_text.dart#L8-L49)).
- **The open-report badge and the queue agree** while the operator is on the
  open filter, and the shell's badge is updated as reports are resolved
  ([reports_screen.dart:44-48](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/reports/reports_screen.dart#L44-L48),
  [server_controller.dart:136-141](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L136-L141)).
- **A phone number reaches the screen in exactly one place**, and the console
  never reads a phone hash (ADR-030; a rules test pins both)
  ([format.dart:28-37](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/common/format.dart#L28-L37),
  [rules_test.dart:259-295](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L259-L295)).

## AUD-17b-1 Resolving a report under the "All" filter can throw `StateError` and leave the card open after the server accepted it

**Severity:** P3
**Confidence:** confirmed
**Where:** [reports_controller.dart:28-62](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/reports/reports_controller.dart#L28-L62),
[reports_screen.dart:76-90](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/reports/reports_screen.dart#L76-L90)

**What:** `resolve` sends the request, and on success takes one of two paths.
With a status filter it removes the card (`removeWhere`); with the "All" filter
(`_status == null`) it builds the replacement from
`items.firstWhere((r) => r.reportId == reportId)`. `items` is whatever the
last `refresh`/`loadMore` left behind, and the call is awaited across the
network, so the list can have been replaced in the meantime. If the report is
no longer in it, `firstWhere` throws `StateError` inside the controller; the
screen's `_resolve` awaits without a `try`, so no message is shown and the
exception reaches the zone as an unhandled async error. The server has already
resolved the report, so the card stays visible as "Open" until the next
refresh.

**Trigger:** on the "All" chip, tap Resolve and then pull to refresh (or a
refresh started for any other reason lands) before the response returns.
`refresh` replaces `_items` with page one; with more than one page of reports,
or with new reports arriving, the resolved report can fall past the page
boundary and disappear from `_items`
([feature_controller.dart:78-101](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/common/feature_controller.dart#L78-L101),
[reports_screen.dart:109-161](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/reports/reports_screen.dart#L109-L161)).
The window is the network round trip; it widens with latency.

**Evidence:** the "All" branch is the only one that looks an item up by id,
and it is the only branch no test exercises — every resolve test runs on the
default open filter
([invites_reports_audit_test.dart:208-239](file:///J:/Projects/helix/helix_remote/admin/test/invites_reports_audit_test.dart#L208-L239)).
`replaceWhere` itself is safe; the throw is the lookup.

**Impact:** an unhandled exception on a moderation screen, and a stale card
that says a report is open when the operator just closed it (a second operator
or a later refresh sees the truth). No data is lost and the action did happen;
the report cannot be resolved twice because the server answers `conflict` the
second time.

**Fix sketch:** use `firstWhereOrNull` (or an index lookup) and skip the
in-place replacement when it is missing — the list will show the server's state
on the next refresh anyway. A `try` around the body would only hide it. No
wire or schema change.

**Test that proves it:** feed two pages, switch to "All", make the resolve
response slow, start a `refresh()` that drops the report from page one, then
complete the resolve: today the test sees a `StateError`; with the fix, the
card for the other report remains and no error escapes.

**Overlap:** none. The open-queue path (`removeWhere`) is correct and tested.

## AUD-17b-2 The "shown only now" code dialog can be dismissed with the Android back gesture, destroying the only copy of the code

**Severity:** P3
**Confidence:** confirmed
**Where:** [dialogs.dart:256-314](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/dialogs.dart#L256-L314),
[account_detail_screen.dart:157-165](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/accounts/account_detail_screen.dart#L157-L165),
[invites_screen.dart:47-54](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/invites/invites_screen.dart#L47-L54)

**What:** `showCodeOnceDialog` uses `barrierDismissible: false`, which stops a
tap outside the dialog but not a route pop. The Android back button, the back
gesture and the desktop Escape-equivalent pop the dialog route through
`Navigator.maybePop` regardless of `barrierDismissible`, so the dialog closes
without "Done" or "Copy code". The code is a server-side secret that is shown
exactly once: a recovery code (single use, 48 hours) or an invite code (the
only way onto an invite-only server). After the pop the console holds nothing —
the controller never kept it — so the code is gone and a new one must be
issued.

**Trigger:** an operator holding the phone reaches for back (or the system
gesture fires) while reading the code.

**Evidence:** the dialog is the only consumer of the code
([rules_test.dart:229-240](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L229-L240)),
there is no `PopScope`/`WillPopScope` in `lib/`
(a `PopScope` would appear in the rules scan as ordinary code; there is none in
`dialogs.dart`), and the only way the tests close it is the "Done" button
([accounts_test.dart:361-363](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L361-L363)).

**Impact:** the one-time secret is silently discarded at the moment it matters;
the person waiting for an invite or the locked-out account owner has to wait
for a second code, and the operator may not realize the first one was never
seen. Nothing leaks and nothing is unrecoverable, but the "shown only now"
promise is broken by an ordinary navigation gesture.

**Fix sketch:** wrap the dialog body in `PopScope(canPop: false)` and give it an
explicit secondary action ("Discard code") next to "Done", so leaving requires
an intent. The web/desktop variants inherit the same guard through the route.
No wire or schema change.

**Test that proves it:** open the recovery-code dialog, call
`tester.pageBack()`, and assert the dialog and the code are still on screen;
today the dialog is gone.

**Overlap:** the copy/never-log side of one-time codes is sound and pinned by
the rules test; this is only about dismissal.

## AUD-17b-3 The audit trail's kind filter can hide "Load more", so later matching events are unreachable

**Severity:** P3
**Confidence:** confirmed
**Where:** [audit_screen.dart:76-92](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/audit/audit_screen.dart#L76-L92),
[paged_list.dart:35](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/paged_list.dart#L35),
[paged_list.dart:46-95](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/paged_list.dart#L46-L95)

**What:** the audit screen filters the *loaded* page by kind
(`_AuditKind.of(entry.action)`) and passes the result to `PagedListView` as
`shown`. When the filter matches nothing in the loaded page, the list switches
to its empty state, and `PagedListView` draws the empty state *instead of* the
footer — the "Load more" button only exists when `state == null`. If the server
has more pages, the operator sees "No moderation events loaded / Try another
filter, or load more events" with no way to load more. The same shape applies
to the header chips: "All events (n)" counts only the loaded page.

**Trigger:** a server with more than one page of audit entries (50) where the
first page has no event of the selected kind — e.g. a quiet moderation day and
a filter on "Moderation", or any filter on a server whose page one is all
`admin.*` sign-ins.

**Evidence:** the footer is the last item of the non-empty list and the empty
state replaces the whole list body
([paged_list.dart:69-92](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/paged_list.dart#L69-L92));
the audit screen is the only `shown` caller
([audit_screen.dart:76-82](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/audit/audit_screen.dart#L76-L82)).
The audit paging test runs with no kind filter, and the chip test's data fits
in one page
([invites_reports_audit_test.dart:302-313](file:///J:/Projects/helix/helix_remote/admin/test/invites_reports_audit_test.dart#L302-L313),
[:352-](file:///J:/Projects/helix/helix_remote/admin/test/invites_reports_audit_test.dart#L352)).

**Impact:** the moderation audit is silently truncated exactly when the
operator is looking for something rare; the screen's own message tells them to
do something it does not offer. No data loss (the server keeps everything).

**Fix sketch:** keep the footer whenever `hasMore`, even in the empty state
(show the empty copy above it), or make the empty state carry its own "Load
more" for a filtered `shown`. The structural variant is the proposal below.
No wire change for the cheap fix.

**Test that proves it:** two pages where only page two holds a `report.*`
event; select "Moderation" on page one and assert a "Load more" control is
present and loads page two.

**Overlap:** the reports "All" queue and the audit trail share
`PagedListView`; AUD-17b-1 is the reports controller, this is the list widget.

## AUD-17b-4 A refresh that overlaps a config change can put the old value back on the switches

**Severity:** P3
**Confidence:** likely
**Where:** [server_controller.dart:76-132](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L76-L132),
[server_controller.dart:158-167](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L158-L167),
[server_controller.dart:206-220](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L206-L220)

**What:** `refresh()` fires five reads in parallel and each writes its field
when it returns (`_config = await …`). There is no request generation and no
guard against a second refresh or against `_patch`. `_patch` (maintenance,
federation, rename) also assigns `_config` from its own response. If a refresh's
`config()` request was issued before a patch and its response arrives after
it, the stale document overwrites the fresh one; the shell's ServerController
is shared by the Dashboard, the Config screen and the shell title, so the
maintenance and federation switches, the health rows and the server name all
revert to the pre-change values until the next refresh.

**Trigger:** `purge()` schedules a background `refresh()`
([server_controller.dart:216-218](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L216-L218)),
and the operator immediately flips maintenance on the same screen; or a
pull-to-refresh on Overview is still in flight when the operator moves to
Config and flips a switch. Both are ordinary on a slow or distant server.

**Evidence:** `refresh` and `_patch` both write `_config` with no ordering
token, unlike `PagedController`'s `_generation`
([feature_controller.dart:55-57](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/common/feature_controller.dart#L55-L57)).
The refusal test only covers a single in-flight patch
([settings_test.dart](file:///J:/Projects/helix/helix_remote/admin/test/settings_test.dart)),
and no test overlaps a refresh with a patch.

**Impact:** the console shows the opposite of the server's state for a setting
whose whole point is whether apps are being served (`maintenance`) or whether
peers are accepted (`federation`). The change *was* applied on the server, so
the operator may "fix" it by flipping again and end up back where they started.
Recovered by any later refresh.

**Fix sketch:** give `ServerController` a generation counter as
`PagedController` has, or have `_patch` bump it and have `refresh` discard a
`config` result older than the latest successful patch. Not optimistic UI —
just last-writer-wins by request order. No wire or schema change.

**Test that proves it:** hold the fake server's config response, flip
maintenance (complete it), then release the older response; the switch must
still show the flipped value.

**Overlap:** the same "one writer, no ordering" shape as AUD-17b-1, but here it
is a display race rather than a crash.

## Structural proposal — filter the audit trail before paging, not after

**Current shape:** `AuditScreen` loads a page of 50 entries and filters by kind
in the widget (`audit_screen.dart:76-92`), passing `shown` to a list that pages
by cursor. The kind is a console taxonomy (`_AuditKind.of` maps action prefixes
and substrings, `audit_screen.dart:23-36`); the server's audit route takes only
a cursor.

**Hazard:** the filter's result is a function of an arbitrary page of a
changing table. It can be empty while thousands of matching events exist, and
the UI then hides the only control that could reach them (AUD-17b-3). The
"All events (n)" count is also a page count dressed as a total.

**Proposed shape:** either (a) keep the taxonomy client-side but give the list
a "scan" mode for a filtered `shown` — keep loading pages while `hasMore` and
the last page added no matches (bounded, say 10 pages, then offer "Keep
looking"); or (b) add an `action_prefixes`/`kind` query parameter to
`GET /v1/admin/audit` so the server filters before the cursor. (a) needs no wire
change and keeps the taxonomy where it is; (b) is the one that scales to a large
audit table and makes the count honest. Prefer (a) now, (b) when the console is
next touched for audit reporting.

**Migration path (for b):** expand — add the optional query parameter, default
unchanged; migrate — the console sends it and keeps the client filter as a
guard for older servers; contract — drop `shown` from the audit screen once the
oldest supported server understands the parameter.

**Risk:** (a) turns one tap into several requests (a busy server's first page
is rarely all one kind, so it is bounded in practice) and a mistyped filter
costs a burst; (b) puts a console-side label into the wire contract, so the
kind set would need to be documented as protocol, not UI.

**Rough size:** (a) ~40 lines in `audit_screen.dart` plus a test; (b) ~15
protocol lines, ~25 server lines in the audit query, ~30 console lines, plus
route-catalog and fixture updates.

## Coverage gaps

- No test resolves a report from the "All" filter, so AUD-17b-1's branch is
  untested; the "open queue" branch is.
- No test dismisses a once-shown dialog with back (AUD-17b-2); `pageBack` is
  used only to leave the account page
  ([accounts_test.dart:422-424](file:///J:/Projects/helix/helix_remote/admin/test/accounts_test.dart#L422-L424)).
- The audit filter is tested only with data that fits one page, so
  AUD-17b-3's dead end is invisible.
- No test overlaps `ServerController.refresh` with a patch (AUD-17b-4).
- No console screen is tested at 2x text scale; `_ReasonDialog` and
  `_TypedConfirmDialog` put two fields in a non-scrolling `AlertDialog` content
  ([dialogs.dart:118-146](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/dialogs.dart#L118-L146),
  [:218-240](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/dialogs.dart#L218-L240)),
  while the change-password dialog wraps its fields in a `SingleChildScrollView`
  ([settings_screen.dart:541-597](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/settings/settings_screen.dart#L541-L597)) —
  the ban/delete dialogs are the ones most likely to overflow with a keyboard
  up, and nothing measures them.
- No test of the lists with a full page (50 rows) for scroll performance; the
  log tail's 1000-line cap is tested, not drawn.

## Considered and dropped

- **`_act`/`_create`/`_patch` returning `null` when the same key is already
  running** — `null` means both "no problem" and "not sent", and callers print
  the success sentence in both cases
  ([accounts_controller.dart:73-80](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/accounts/accounts_controller.dart#L73-L80),
  [server_controller.dart:158-167](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L158-L167)).
  Reaching it needs a second tap in the same frame, and the suspend/ban paths
  put a dialog in between; the switches disable themselves on the next
  notify. Latent, no trigger found; worth a distinct "busy" result the day a
  destructive action loses its dialog.
- **No confirmation before Resolve/Dismiss.** Both are terminal, and one tap
  closes a report. It is a single row with two clearly labelled buttons and no
  undo; treating every moderation action as irreversible would make the queue
  slow to work. Left as product judgment, not a finding.
- **`ReportsScreen._openAccount` ignores the pushed route's result**, so
  banning the reported account from a report does not refresh the queue
  ([reports_screen.dart:92-101](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/reports/reports_screen.dart#L92-L101)).
  The account's report is still in the list until refresh; the shell's badge
  follows only the open filter. Cosmetic.
- **The user's earlier `checkServer` race** — see `17a_admin_session.md`,
  "Considered and dropped".
