# Helix Usability Session Log

**Phase:** 9 — Accessibility, localization, and ease-of-use certification  
**Created:** 2026-06-20  
**Status:** Framework established; live sessions scheduled for pre-release validation

---

## Session matrix

Each session covers one product (Local or Remote) and one primary task scenario.
Sessions are conducted with real users or structured task observations.

| Session | Product | Scenario | Participants | Date | Status |
|---|---|---|---|---|---|
| US-01 | Local | First-time setup (name + secret code) | 3 users (non-technical) | TBD | Pending |
| US-02 | Local | Find a nearby peer and send a message | 3 users | TBD | Pending |
| US-03 | Local | Receive a connection request and accept it | 2 users | TBD | Pending |
| US-04 | Local | Share QR code; scan QR code (Android) | 2 users | TBD | Pending |
| US-05 | Local | Use secret-code connect flow | 2 users | TBD | Pending |
| US-06 | Local | Change secret code in Settings | 2 users | TBD | Pending |
| US-07 | Local | Trigger panic wipe from Settings | 1 user (guided) | TBD | Pending |
| US-08 | Remote | Create an account (new user) | 3 users | TBD | Pending |
| US-09 | Remote | Restore an account from backup | 2 users | TBD | Pending |
| US-10 | Remote | Send a message to a contact | 3 users | TBD | Pending |
| US-11 | Remote | Verify a contact's identity | 2 users | TBD | Pending |
| US-12 | Remote | Export an encrypted backup | 2 users | TBD | Pending |
| US-13 | Remote | Delete account (full flow) | 1 user (guided) | TBD | Pending |
| US-14 | Local | Full keyboard-only on Windows (P9-03) | 1 power user | TBD | Pending |
| US-15 | Both | TalkBack (Android) and Narrator (Windows) | 1 user with screen reader | TBD | Pending |

---

## Metrics tracked per session

For each scenario the facilitator records:

| Metric | Description |
|---|---|
| Task completion rate | % of participants who complete the task without facilitator intervention |
| Time on task | Median and range in seconds |
| Error count | Number of wrong paths, dead ends, or unrecoverable states |
| Abandonment | Whether any participant gave up before completing |
| Error rate | # errors / total task steps |
| Confusion points | Specific UI elements or copy that caused hesitation > 5 s |
| Severity | P0 (blocks completion) / P1 (significant friction) / P2 (minor friction) |

---

## Remediation process

1. Facilitator documents each finding in the **Findings** section below within 48 h of the session.
2. Engineer confirms severity and assigns fix target (pre-release / follow-on).
3. Fix is committed with a reference to the finding ID (e.g., `fix: US-01-F2 name field empty-state`).
4. Regression test is added if the scenario can be automated.
5. Finding is marked **Closed** with the commit SHA.

---

## Findings

*No live sessions conducted yet. Entries below are pre-identified risks from code review and heuristic evaluation (2026-06-20).*

| ID | Session | Severity | Description | Status |
|---|---|---|---|---|
| US-PRE-01 | Setup (both) | P1 | Secret-code and restore-code fields use `obscureText` but toggle-visibility button has no semantic label on older Flutter widget path. Fixed in P9-02 via `HelixSemanticButton`. | Closed — P9-02 |
| US-PRE-02 | Remote setup | P1 | Registration error message was a floating `Text` widget below the field, not field-associated via `errorText`. Screen readers did not announce it. Fixed in P9-08. | Closed — P9-08 |
| US-PRE-03 | Local home (Windows) | P2 | No keyboard shortcut to switch between Home / Requests / Chats / Settings tabs. Added Ctrl+1–4 in P9-03. | Closed — P9-03 |
| US-PRE-04 | Both | P2 | No `highContrastTheme` / `highContrastDarkTheme` in Remote app. Added in P9-05. | Closed — P9-05 |
| US-PRE-05 | Both | P2 | Animations not respecting platform reduced-motion preference. `HelixAnimation` utility added in P9-07; explicit `AnimationController` sites should adopt it as found. | Open — ongoing |
| US-PRE-06 | Local | P2 | Status indicators (connected/disconnected chips) convey state by color only in some widgets. `HelixStatusLabel` now provides icon + text alongside color. Sites using bare `Color` for status should migrate. | Open — ongoing |
| US-PRE-07 | Both | P2 | No `localizationsDelegates` in either app, so `GlobalMaterialLocalizations` date/time formatting and screen reader locale hints were absent. Fixed in P9-01. | Closed — P9-01 |
| US-PRE-08 | Local (Android) | P1 | QR share screen shows a `QrImageView` with no semantic label — TalkBack announced it as "unlabelled image". `semQrCode` string added to `HelixLocalizations`; widget-level Semantics wrapper to be applied in follow-on work. | Open |

---

## Accessibility gate for release

A release is certified when:

- [ ] All P0 findings are closed.
- [ ] All P1 findings are closed or have documented risk-accepted mitigations.
- [ ] Core scenario matrix (US-01 through US-13) achieves ≥ 80% task completion without facilitator intervention.
- [ ] Keyboard-only scenario (US-14) completes all primary tasks.
- [ ] Screen-reader scenario (US-15) completes first-run setup and send-a-message without facilitator help.
- [ ] Zero critical violations in automated `flutter_test` semantics suite (`phase9_accessibility_test.dart`).
- [ ] All user-visible strings use `HelixLocalizations` (untranslated-string lint passes).
