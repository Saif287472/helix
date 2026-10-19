# Orbit gap list (Phase 1, for Review 1)

Written 2026-10-18 from the eight contracts in `contracts/`. Each item has a
recommendation. You can approve them all at once, or change any one.

## At a glance

| | have | derive | local | engine | server | demo | total |
|---|---|---|---|---|---|---|---|
| Model fields | 341 | 113 | 5 | 12 | 3 | 0 | 474 |
| Actions | 287 | 13 | 2 | 5 | 4 | 3 | 314 |

- **About 85% of what the design needs exists in the app today.** Most of
  the rest the app can compute from data it already has (derive).
- **Real backend work is concentrated in a few places:** the You page (share
  your code, the profile photo, storage per chat) and some backup details.
- **The app shows 272 states the prototype never drew:** loading, errors,
  empty lists, permissions, failure messages. See part 4.
- **Reading the code turned up 13 bugs in today's app.** Part 1 lists them.
  They are separate from the redesign, and some matter now.
- **Design change 19 is included.** Your profile on You is now an orbit
  rather than the ID pass. It came from a side session on 2026-10-18. Its
  data and taps are unchanged, so `contracts/you.md` changed in wording only.

## 1. Bugs in today's app (fix now, separately from the redesign)

Found while reading the code, not by running it. Production is live, so the
first three are worth fixing before the redesign lands.

| # | Bug | Where | Effect | Severity |
|---|---|---|---|---|
| B1 | Received disappearing messages never start their timer. `ReadTracker.displayed` is never called, so `markDisplayed` never runs; only engine tests call it. | `app/lib/features/conversation/application/read_tracker.dart`, `conversation_screen.dart` | **Disappearing messages never disappear on the receiving device.** A privacy promise is broken. | High |
| B2 | Take-over cannot finish on Orbit Global. `completeSetup` requires the Terms, but the screen shows the checkbox for new accounts only. | `sign_in_controller.dart` `completeSetup`; `sign_in_screen.dart` line 280 | "Forgot password?" ends in "terms not accepted" with no way to accept them. Account recovery by SMS is blocked. | High |
| B3 | The reset screen treats any startup error as "could not be decrypted" and offers the destructive reset. | `shared/widgets/reset_screen.dart`, `_redirectFor` | A passing error could lead someone to wipe their data. | High |
| B4 | On the restore step, "I have a recovery secret" bounces back: the redirect returns every location to `/restore` while that step is pending. | `core/router/app_router.dart` `_redirectFor` | The recovery-secret path after sign-in is unreachable. | Medium |
| B5 | Invite links live only in memory; the server keeps hashes and offers no list. | `features/groups/application/group_invites.dart` | A link made before a restart, or on another device, can never be revoked. | Medium (see S3) |
| B6 | The app's block dialog says the person "will not be told". | `features/people/…/contact_info_screen.dart` | Contradicts ADR-030: blocks are visible now. | Medium (copy) |
| B7 | The composer ignores the "Enter key sends" setting. | `features/conversation/presentation/composer_bar.dart` | The setting does nothing. | Low |
| B8 | Retry on Archived chats reloads the active list. | `features/chats/presentation/archived_chats_screen.dart` | Retry does nothing useful. | Low |
| B9 | A `helix://contact/add` link opens an empty people search and ignores the account in the link. | `app_router.dart` `routeDeepLink` | The link does not lead to the person. | Low |
| B10 | A short phone number is sent anyway, and the error says "Could not reach the server". | `sign_in_controller.dart` | Misleading error. | Low |
| B11 | The legal sheet shows "┬╖" instead of "·". | `legal_documents_sheet.dart` | Garbled text. | Low |
| B12 | The link countdown can read "Code expires in Expired". | `link_this_device_page.dart` | Odd copy. | Low |
| B13 | Archive and unarchive from the selection bar show no Undo. | `chats_tab.dart` | No way to undo a mistake. | Low |

**Recommendation:** fix B1 to B4 now in a separate session, with tests,
through the normal `helix-feature` process. B6 to B13 can go with them or
wait for the redesign. B5 is the server decision S3 below.

## 2. New backend work

### Server

| # | Item | Needed for | Recommendation |
|---|---|---|---|
| S1 | A share link `helix.agiletechbd.com/u/<~name>`, app links that open it, and scan-to-chat | You: the share sheet (QR, copy, share, scan someone's code) | **Build in Part B** (size M). It is the headline of the You page. It needs a `~name` and "Find me by ~name" turned on. |
| S2 | A live "~name is available" check | Profile editor | **Don't build.** It would let anyone probe which names are taken, which the server avoids on purpose. Instead: show "Looks good" from the name rules as you type, and the server's answer on Save. |
| S3 | List a group's live invite links (id, approval, made by, date; never the secret) | Invite links page: revoking any link | **Built** (Part B, pending review). It fixes B5. |
| S4 | List a group's bans from the server | Banned people, across devices | **Drop.** The design does not need it. |
| S5 | Delete security events after 30 days | "Orbit keeps 30 days of activity" | **Don't build; fix the copy** to "Your account's sign-ins, devices and key changes". |

### Engine (no server change)

| # | Item | Needed for | Recommendation |
|---|---|---|---|
| E1 | Share your profile photo with people you message (the server already has the media kind) | "Who sees what: name, about and photo" | **Build in Part B** (M) |
| E2 | Storage size by kind and by chat (a database query) | Storage bar and Biggest chats | **Build** (S) |
| E3 | Free one chat's photos, videos or documents, keeping the messages | Biggest chats → Free up space | **Build** (M) |
| E4 | A total for a running backup | The backup ring's percentage | **Build** (S) |
| E5 | A separate "waiting for Wi-Fi" backup failure | The failed backup's reason | **Build** (S) |
| E6 | Every device knows whether a recovery backup exists, and when it was made | The checkup and Backup on every device; warning before replacing it | **Build** (S) |
| E7 | A total while history is being prepared ("3 of 8") | Send to my other devices | **Don't build.** Use a plain moving bar |
| E8 | Remove a finished incoming transfer | "Dismiss" | **Don't build in the engine.** Use a local hidden list |
| E9 | A real restore percentage | The restore ring | **Don't build.** The ring steps by phase |
| E10 | Remember that a voice note was played (schema 5 migration) | The blue dot after a restart | **Later.** In-memory is fine for Part B |
| E11 | Theme packs and ringtones | Appearance, Notifications | **Part C** (already planned) |

## 3. Copy and privacy wording to fix

The first two change privacy claims. They must match the product, not the
design.

| # | What | Recommendation |
|---|---|---|
| W1 | "Who sees what" on the profile editor. Since ADR-030 the operator sees your name and your full number. | New wording: **Name**: people you message, and Orbit's operator. **Phone number**: hidden from people; Orbit's operator can see it. **About and photo**: encrypted, only people you message. **~name**: anyone who looks it up. |
| W2 | The bundled privacy policy (2026-09-25) predates ADR-030. | Update the legal text. This is your document, outside the design; flagged so it is not forgotten. |
| W3 | "Orbit keeps 30 days of activity" | "Your account's sign-ins, devices and key changes" (S5) |
| W4 | History transfer: "They accept it first" / "nothing is sent until they accept". The history is uploaded before the other device accepts. | "Sent encrypted. Your other device chooses whether to add it." |
| W5 | The approve step asks you to compare the key code, but the new device only shows it after approval. | Approve compares the check number only; the key code is compared on the new device's "Is this your account?". |
| W6 | Copy on the share sheet, Blocked page, block dialogs | Already fixed in the prototype (design change 17) |

**I'll make W1 and W3 to W5 in the prototype once you approve.**

## 4. What the app shows that the prototype never drew (272 states)

The contracts list every one, under each screen's "The app does this"
table:
- 184 are suggested **keep, in the new style**: today's behaviour, drawn the
  Orbit way.
- 40 are **add to the design**: they need their own drawing.
- 9 are **drop**.
- 39 are mixed or need a decision.

**Recommendation: one more prototype pass before Phase 2, "Phase 1b: the
state kit".** The port must not invent these, so the prototype draws them
first:
1. **Shared state parts, drawn once and used everywhere:**
   - a list loading skeleton;
   - "could not be loaded" with Retry;
   - inline field errors and lockout messages;
   - the empty-list pattern;
   - the permission card (camera, microphone, contacts, notifications);
   - an offline / connecting / update-available banner;
   - toasts with and without Undo.
2. **The about 40 "add" states, drawn on their screens.** For example:
   - the six call end reasons;
   - the video player's buffering and failures;
   - the join-link failure reasons;
   - the backup and restore failures (wrong key, damaged, newer format,
     offline);
   - "never backed up";
   - transfer declined, cancelled and resume;
   - the phone-number prompt on linked devices;
   - an "Opening Orbit…" startup screen.
3. **The 9 drops are removed from the contracts; the 39 mixed ones get a
   decision** using the same rules.

Each state gets an index entry and an interaction line, so the compare tool
and the checklist cover them too.

## 5. Product questions (with my recommendation)

### Calls
1. Audio output → **keep the app's way:** a toggle with two outputs, a sheet
   when there are more, hidden on Windows.
2. Esc on a live call (window) → **does nothing.** No accidental hang-ups.
3. Call details for someone who blocked you → **hide the call buttons** and
   say why, as the chat does.
4. Your camera off in a video call → **keep their video full screen** (the
   app's way).
5. "Camera flipped" toast → **drop it.** The mirrored view already shows
   it.

### Home
1. Every chat archived → an empty state **"All your chats are archived"**
   with "Open archived chats".
2. Blocked people in search → **show them marked "Blocked"**, so you can
   find and unblock them.
3. A number without a country code → **keep the app's rule:** read it as
   your own country. The prototype's hint changes to match.
4. A plain word like "arif" → **also offer a ~name lookup** (the app's
   way).
5. A contact link → **opens that person** (fixes B9).
6. The chosen filter → **for the visit only.**

### Conversation
1. Enter key → **follow the "Enter key sends" setting:** on by default on
   Windows, off on phones (fixes B7).
2. Voice note "played" after a restart → **later** (E10).
3. A live waveform while a locked recording runs → **drop it.** Show the
   timer and a still wave.
4. "Show in chat" from media → **open the chat at that message** (the app's
   way).
5. Block wording → the prototype's (ADR-030). Done.

### People and groups
1. The contact page when they blocked you → **say "<Name> has blocked you"
   and hide the call tiles.**
2. Invite links that need approval → **off by default** (the app's way);
   admins turn it on.
3. The invite links list → **build it** (S3).
4. "Only lets people they know add them" → neutral: **"<Name> could not be
   added. Send them an invite link."**
5. Members when a group allows everyone → **show them Edit and Add
   members.**
6. Safety-number mismatch → **keep the app's stronger warning** ("do not
   trust this chat").

### Sign-in
1. Take-over → **add the Terms checkbox** (fixes B2).
2. Back from the password step → **the phone step.**
3. Country → **a country picker,** Bangladesh by default (client only; the
   dependency policy applies).
4. Phone length → **check it on the device for the picked country:** "This
   number looks too short" (fixes B10).
5. The restore ring → **steps by phase** (E9).
6. "No, cancel" on "Is this your account?" → **stay and explain** that the
   approval was declined (the app's way).
7. Startup → **an "Opening Orbit…" screen** with the logo.
8. An invite link while signed in → **say "You're already signed in"**
   instead of dropping it.
9. After a failed invite → **add a "Use a recovery code instead" button.**

### Devices and backup
1. The 30-day footnote → **change the copy** (S5, W3).
2. Key code at approve time → **compare the check number only** (W5).
3. Making a new recovery backup → **warn that the old secret stops
   working.**
4. Delete recovery backup → **add it to the danger zone.** The app can
   already do it.
5. Transfer wording → W4.

### You
1. Share your code → **build** (S1).
2. "~name is available" → **rules as you type, the server's answer on
   Save** (S2).
3. The profile photo for contacts → **build** (E1).
4. "Who sees what" → W1, and the policy → W2.
5. Checkup rules:
   - backup "needs attention" when there has been none in 7 days, or never;
   - devices when one has been inactive for over 30 days;
   - password when none is set (fix: Set a password);
   - recovery when none is made;
   - app lock when it is off.
6. The privacy preview's name → **your most recent chat,** or "Someone".
7. The theme before sign-in → **a device setting,** so it survives sign-out.
   Packs are hosted on Helix Global and signed with your key (both decided).
8. Ringtone → **keep "Phone's ringtone" as a choice** next to the bundled
   default.
9. Biggest chats and freeing space → **build** (E2, E3).
10. About → **show version and build number** (from the app's package
    info).

## Status (2026-10-18)

Review 1 was approved with every recommendation.
- The answers and wording fixes are drawn in the prototype (Phase 1b, design
  change 20).
- Each contract has a "Decisions and Phase 1b" section.
- B1 to B4 have a proposed fix session; it runs separately from the
  redesign.

## What happens after Review 1

1. B1 to B4 are fixed in a separate session, if you agree.
2. The approved wording (W1, W3 to W5) and the answers above go into the
   prototype and the contracts.
3. Phase 1b, the state kit, if you agree. Then Phase 2, the Flutter
   foundation.
