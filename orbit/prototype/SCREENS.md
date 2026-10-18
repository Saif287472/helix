# Orbit (formerly Helix) screen checklist

Every screen, state and line of copy in the real app (`helix_remote/app`),
gathered on 2026-10-16 from the presentation code. The redesign has to cover
exactly this list. It adds nothing the app doesn't have and drops nothing the
app has. A tick means the prototype draws it.

**Status: every screen below is drawn in the prototype ✓ (pass 1 and pass 2). Still to do: the wide Windows layout.**

## Design changes you approved (these differ from today's app)

When the design is ported, these need real Flutter work, not just restyling:

1. **Chat filters (2026-10-16).** Chips under the Chats title: All, Unread
   (with a count), Groups (with a count).
   - The filtering is local: unread is `unreadCount > 0`, groups are the
     `group:` ids. No engine or server change is needed.
   - The empty states:
     - Unread: "No unread chats" / "You're all caught up. New messages show up
       here until you read them."
     - Groups: "No groups yet" / "Start a group from the menu, or join one
       with a link.", with a "New group" button.
2. **Archived chats move to the menu (2026-10-16).** The "Archived" row at the
   top of the chat list is gone. The Chats tab's ⋮ menu now reads "New group",
   "Join a group with a link", a divider, then "Archived chats (N)".
3. **Call screen colour (2026-10-16).** No black. The voice and incoming call
   screens use the logo's teal-to-blue gradient: `#0B7A84` → `#1D63D8` →
   `#1A3C9E`, with white text at 5:1 or better. Video calls still show the
   video full screen.
4. **Floating dock with a round "new" button** in place of the full-width
   navigation bar.
5. **Accent colour:** Helix blue, the app icon's `#2563EB`, used everywhere.
   Sign-in already used it.
6. **Two tabs (2026-10-16).** The dock holds Chats and Calls only. Settings
   left the dock: your avatar at the top-left of both tab headers opens it.
7. **No dot after titles (2026-10-16).**
8. **Design comes first (2026-10-16).** From here the prototype is not
   limited to today's features. This file stays as the reference for copy and
   rules.
9. **"You" replaces the Settings page (2026-10-16).** The avatar opens it.
   - **Your profile:** your photo, name, about, ~name, masked number, server
     and device count, with two buttons: share your code and edit profile.
     First drawn as a card in the brand gradient (the "Helix ID pass"); since
     design change 19 it is the Orbit profile.
   - **Privacy checkup:** shows only what needs attention, with one-tap fixes
     (for example "Fix", "Turn on"), and a score "3 of 5". "See all checks"
     lists all five: backup, linked devices, password, recovery backup and app
     lock. When everything passes it reads "Everything that keeps your account
     safe is in place."
   - **Topic tiles, each with a live status line:** Privacy, Notifications,
     Chats, Devices, Backup, Storage. Below them, rows for Account, Help and
     about, and Advanced. A search icon opens settings search.
   - **Share your Helix code (new feature):** a small profile, a QR code, a link
     (`helix.agiletechbd.com/u/<name>`), "Copy link", "Share", and "Scan
     someone's code" (the scanner with the hint "Point the camera at someone's
     Helix code to start a chat").
10. **Profile editor redesigned (2026-10-16).**
    - A live preview of your profile sits at the top and updates as you type.
    - Photo, name and about, and the ~name, which is checked as you type
      ("~x is available" or the rule that fails).
    - A "Who sees what" card:
      - Name, about and photo: Encrypted, for people you have messaged. Photo
        sharing is a new feature.
      - ~name: Public.
      - Phone number: Hidden.
    - "Remove my ~name".
11. **Orbit wordmark and profile chip (2026-10-16).**
    - "Orbit" in gradient lettering (`#0EA5B7` → `#2563EB` → `#7C3AED`)
      replaces the "Chats" and "Calls" titles. The dock shows which tab you
      are on.
    - On the right of the header: search, ⋮, then your round profile picture
      (no name) in a gradient ring.
    - It opens You. It shows an amber dot while the privacy checkup needs
      attention.
    - On You, your whole profile is a button into the profile editor, with an
      "Edit profile" pill. The QR button still opens the share sheet.
12. **The product is renamed Orbit (2026-10-16).**
    - Every user-facing "Helix" in the prototype now says Orbit: "Orbit ID",
      "~Orbit name", "Orbit Global", "continue to Orbit", "not even Orbit",
      "Orbit is locked", and so on.
    - New logo mark: `assets/orbit-mark.svg`, a planet with a ring and a moon
      on the teal → blue → violet gradient.
    - Not renamed, because they are infrastructure and protocol rather than
      design: the server domain `helix.agiletechbd.com` and the code formats
      `HLX-INV-`, `HLX-REC-`, `HLX-GRP-` and `helix-link`. Renaming them needs
      a new domain and a wire-protocol change.
    - The copy quoted earlier in this file is the current app's, so it still
      says Helix.
13. **Topic pages in the You style (2026-10-16).** Privacy, Notifications,
    Chats, Storage, Devices, Backup and Account (`js/screens/topics.js`) all
    use the same parts:
    - A summary card: gradient icon, one-line mono status, status pills.
    - Choices inline as segmented controls instead of pop-up radio sheets.
    - A red-edged "Danger zone" at the bottom.

    Each page:
    - **Privacy:** a live "What Nadia sees" preview that follows the controls:
      online / last seen / nothing, blue or grey read ticks on her message,
      the typing line. Then inline Everyone/Nobody choices, the receipts and
      typing switches, the new-chat timer (Off / 24 h / 7 d / 90 d), finding
      you, app lock with its lock-again time, and Blocked.
    - **Notifications:** a live lock-screen preview that follows "Show message
      previews", sound and vibrate. Then Messages / Groups / Calls as toggle
      tiles, and the muted chats.
    - **Chats:** a live conversation preview at the chosen text size (four
      "Aa" buttons), Enter key, and auto-download as Never / Wi-Fi / Always
      for each media kind.
    - **Storage:** a stacked usage bar with a legend. "Biggest chats" with size
      bars is a new feature: tap one to free up its photos, videos or
      documents without deleting messages.
    - **Devices:** device cards (this device highlighted), "Link a new
      device", recent security activity, and the danger zone (sign out all
      others).
    - **Backup:** a status ring (done, running with a percentage, or failed),
      "Back up now", the daily and mobile-data switches, Restore and Send
      tiles, a recovery backup card, and the danger zone (delete server
      backup).
    - **Account:** a summary with password, devices and "since" pills, then
      Sign-in, Your data, and a danger zone (sign out, delete account).

    Settings are shared across pages (`window.OrbitPrefs`). The You tiles show
    live values ("Receipts off", "Text extra large"), and the Privacy app lock
    is the same switch the checkup fixes.
14. **Themes (2026-10-17).** Eight themes, all free; premium themes come
    later. You pick one under You > Appearance, and it stays until you change
    it: no day/night switching, no sign-up step.
    - **The themes:**
      - Light: Orbit (default), Bloom (aesthetic), Mochi (cute), Papyrus
        (ancient).
      - Dark: Orbit Night, Arcade (gaming and neon), Terminal (tech), Field
        (army).
    - **What a theme sets ("full vibe"):** colours, heading font, body and
      label fonts, corner shapes, avatar shape, bubble shape, chat pattern,
      icon weight (light, two-tone, regular or bold), call gradient, wordmark
      gradient (also the ring on your profile), and small effects (Arcade glow, Terminal
      cursor and `[ ]` dividers, Papyrus ❦ ornaments and double-rule cards,
      Mochi ♡, Field side stripes).
    - **What it never changes:** layout and components. The title "Orbit"
      stays in every theme; only its styling changes.
    - **Single source:** `tools/themes.py` generates `css/themes.css` and
      `js/themes.js`. It also checks 33 text pairings per theme against
      contrast minimums (body text 7:1, other text 4.5:1, icons 3:1). Every
      theme passes. Status colours keep red for problems and green for
      success in every theme.
    - **Appearance page:** live preview cards, each drawn in its own theme
      (`data-theme` on the card), grouped Light and Dark. The You tile shows
      the current theme's name.
    - **For the port:**
      - The table becomes `ThemeExtension<OrbitTokens>`: one per theme, with
        `ThemeMode` fixed by the theme.
      - The "light theme only" rule and its `product_rules_test` are retired.
      - All theme fonts are bundled. Fetching them at runtime would leak IP
        addresses.
      - Phosphor supplies the light, duotone and bold weights.
    - **Palette sources:**
      - Figma's colour combinations: Blue eclipse, Cobalt sky, Evening rose,
        Pastel garden, Cotton candy skies, Hydrangea, Golden taupe, Spiced
        chai, Technicolor dream, Neon noir, Mossy hollow.
      - Dribbble's guidance: one accent plus one secondary per theme, colour
        matched to emotion, and culture in mind.
15. **The Windows layout (2026-10-17).** Windows 840 px and wider
    (`HelixBreakpoints.medium`) use panes. Narrower windows use the phone
    layout. Pick Phone, 960 or 1280 at the top of the viewer.
    - **The panes:**
      - **List pane, 380 px, on the left.** It holds Home (Chats and Calls,
        with the dock), Archived chats, You, New group and Join a group.
      - **Right pane.** It shows what the list picked: a chat, a call's
        details, a settings topic or the profile editor.
      - **When nothing is picked,** the right pane shows an orbit picture
        with "Pick a chat", "Pick a call" or "Pick a setting".
      - **Info pane, 360 px, beside the chat (1200 px and wider).** It holds
        contact info, group info and its pages, media and docs, chat settings
        and message info, with a close button. On narrower windows these
        open over the chat with a back arrow.
      - **Full window:**
        - calls, with their controls kept at 440 px wide;
        - the media viewer, with previous and next buttons and the arrow
          keys;
        - the sign-in box.
    - **Going back:**
      - The right pane remembers its page for each list. Go Chats → Calls →
        Chats, or open You and come back, and the chat you had open is still
        there.
      - The first page on the right has no back arrow: the list is the way
        back.
      - Esc closes the topmost thing, in this order: a menu or sheet, a call
        or the viewer, the info pane, then the right pane.
      - Home does not swipe between tabs on a window; the dock switches.
    - **What is open stays marked in the list:** the open chat, call or topic
      has an accent tint and a 3 px accent edge.
    - **The sign-in box:** sign-in, restore after sign-in, link this device,
      reset and lock sit in a centred 440 px box on a soft gradient. Today's
      app already boxes sign-in on wide windows.
    - **Overlays:**
      - Bottom sheets become centred dialogs.
      - A sheet opened from the composer (attach) pops up above its button.
      - Menus hang from the button that opened them.
      - Toasts sit centred under the right pane, clear of the dock.
    - **Width limits:** pages drawn for a phone keep a 680 px column in the
      right pane. Chat bubbles are at most 540 px wide.
    - **Title bar:** the system's own, tinted to the theme. On Windows 11 the
      app sets the DWM caption colour to `--bg` and the text to `--ink-2`.
      That takes a few lines in the Windows runner, not a frameless-window
      package.
    - **Windows Hello wording on Windows:**
      - the lock screen: "Unlock with Windows Hello (your face, fingerprint or
        PIN)";
      - the app-lock switch;
      - the checkup's app-lock dialog;
      - approving a new device: "Use Windows Hello".
      Today's app says "fingerprint, face or phone PIN" on Windows too.
    - **For the port:** the `PLACEMENT` table in `js/app.js` says where each
      screen opens. It becomes the app's routing for wide windows: list,
      detail, info or full. Screens themselves do not know which layout they
      are in. `screens.json` lists each screen state with its placement.
16. **The pages under the topics, in the You style (2026-10-17).**
    - **Which pages:**
      - Change or set a password, Delete my account, Blocked.
      - Help and about, Terms and Privacy Policy, Advanced.
      - Link a new device, Security activity.
      - Restore history, and the restore step after sign-in, which shares it.
      - Send to my other devices, Recovery backup.
    - **The shared look:** each page opens on a summary card. The card has a
      gradient icon (or a status ring, or the Orbit logo), a title, a one-line
      status in mono and status pills. Grouped cards and footnotes follow,
      with live feedback where it helps.
    - **Shared parts:**
      - In `js/kit.js`: `Kit.youPage`, `hero`, `ring`, `steps`, `rules`,
        `formCard`, `danger`. The topic pages use the same parts.
      - In Flutter: `OrbitTopicPage`, `OrbitSummaryCard`, `OrbitStatusRing`,
        `OrbitStepPills`, `OrbitRules`, `OrbitSection`, `OrbitDangerZone`.
    - **New on these pages:**
      - **Password:** rules tick as you type: 8 characters, not the current
        one, and both new passwords match. The button stays off until all
        three pass. Pills say "Checked on this device" and "Never sent to
        Orbit".
      - **Delete my account:**
        - a red summary card;
        - a "What happens" list;
        - "Export my data first";
        - the confirmation in a red-edged card.
      - **Blocked:** says "Orbit tells them they are blocked", because blocks
        are visible since ADR-030.
      - **Help and about:**
        - the Orbit logo card;
        - Terms and Privacy as two tiles, each opening its own document;
        - Server details opens Advanced.
      - **Advanced:**
        - status pills: Connected or "Cannot reach it", the server version,
          and whether new accounts can join;
        - server features as On/Off tags;
        - an "Up to date" tag after checking.
      - **Link a new device and Recovery backup show their steps:**
        - Scan → Check → Done;
        - Save the secret → Confirm → Create.
      - **Security activity:**
        - grouped into This week and Earlier;
        - the key reset flagged "Check";
        - "Something you do not recognise?" with Review your devices and
          Change your password.
      - **Restore:** a status ring shows ready, running with a percentage,
        nothing found, or done.
      - **Send to my other devices:** pills for "encrypted" and "they accept
        it first", and how many transfers are waiting here.
      - **Recovery secret:** it wraps only between its groups.
    - **Copy fix:** "That is not an Orbit link code" and "…an Orbit group link" (they said "a Orbit").
    - **For Phase 1:** check whether the app has the data these pages show:
      - when the password was last changed;
      - 30 days of security activity;
      - the server's feature flags and version;
      - whether a recovery backup exists.
17. **Fixes found while listing every interaction (2026-10-17).**
    - **The block dialogs follow ADR-030.** On the contact page and in chat
      settings they now say that Orbit tells the person they are blocked.
    - **Archived chats: swipe left to unarchive, with Undo.** The swipe
      background was already drawn, but the gesture was missing.
    - **A slow swipe on a chat row no longer starts selection mode.** It
      pins, archives or unarchives as intended.
    - **"…an Orbit group link"** (it said "a Orbit").
    - **The interaction lists:**
      - Each screen's interactions live next to its code (`interactions` in
        `js/screens/*.js`).
      - The app frame's are in `js/app.js` and the page kit's in `js/kit.js`.
      - `tools/manifest.py` exports them to `screens.json` and to the
        `INTERACTIONS.md` checklist, and fails when a screen has no list.
18. **Shapes (2026-10-18).** Avatars are rounded squares at 25% (was 18%).
    Bubbles have a 9 px radius (was 10 px). This applies to the Orbit and
    Orbit Night themes; the other themes keep their own shapes.
19. **Your profile on You is an orbit (2026-10-18).** It replaces the Orbit ID
    pass, which read as a credit card. The goal was something that is neither
    a card nor a usual profile header. It was chosen from four drafts: the
    card, Orbit, Aura (a soft glow behind a large photo) and Intro (your
    profile as a chat bubble).
    - **The planet:** your photo, round in every theme (92 px; 76 px in the
      editor's preview).
    - **The ring:** a tilted ellipse in the theme's wordmark gradient. It
      passes behind the photo at the top and in front of it at the bottom.
    - **The moons:** ~name, device count and E2E, as small chips riding the
      ring.
    - **Under it:** your name (the display font), your about, then the masked
      number and the server in mono, then "Edit profile" and a QR button.
    - **No card:** it sits on the page background.
    - **Tapping:** the whole thing opens the profile editor (Enter and Space
      do too). The QR button opens the share sheet.
    - **The share sheet** starts with a small version: the planet and its
      ring, your name and ~name.
    - **The data is unchanged,** so the contract only changes in wording.
    - **Flutter:** `OrbitProfile`; the ring is a CustomPainter with a gradient
      shader, drawn in two halves around the photo.

---

## Shared pieces

- **Snackbar.** Floating, shown for 4 s, with an optional action. A new one replaces the old.
- **Dialogs.**
  - Destructive: title, message, "Cancel" and a red action.
  - Confirm: "Cancel" and a filled "OK" (or a custom label).
  - Text input: one field, "Cancel" and "Save".
- **Sheets.** A drag handle, an optional title and a scrolling body.
- **Empty and error states.**
  - Empty: an icon, a title, a message and an optional action.
  - Error: "Something went wrong", the message and "Retry".
  - Loading: a spinner or skeleton rows. The chats skeleton reads "Loading chats".
- **Settings look.** Sections have an optional title, a rounded card and an optional footer.
  - Rows: icon, title, subtitle, value, chevron. Destructive rows are red.
  - Switch rows have the same layout.
- **Inline notices.** Info, success and error, each with an optional action. A page intro is an optional title plus a paragraph.
- **QR.** The code is drawn at 240 px.
  - Scanner frame hint: "Point the camera at the QR code".
  - No camera: "The camera is not available. Allow camera access for Helix in your phone settings to scan a code."
- **Avatar.**
  - Sizes: 24, 32, 40, 52 and 72 px.
  - Shows the picture or the initials. Groups get a group glyph and numbers show "#". Selection mode shows a check face.
- **Reset screen** (`/reset`).
  - "Helix is already open in another window. Close that one, then try again." with "Try again".
  - "Your local data is fine."
  - "Reset required" in two cases: the key is missing, or the database can't be decrypted.
  - Confirming: "Type DELETE to confirm", then "Reset Helix Remote", which shows "Deleting…" while it runs.
- **App lock.**
  - "Helix Remote is locked", "Unlock with your fingerprint, face or phone PIN." and "Unlock".
  - A plain privacy cover while the app is in the background.
- **Unconfirmed-member snackbar.** `<name> was added to "<group>" by the server roster. Review it.` with the action "Review". It stays 8 s.
- **Pending members card** (one amber card per person).
  - Title "Confirm <name>?" with one of two reasons:
    - `<name> joined this group through its invite link, and nothing else vouches for them.`
    - `<name> was added by the server roster, but no admin of this group announced it.`
  - Body: "Until you confirm, what you send in this group stays unreadable to them."
  - Buttons: "Confirm", and "Remove" for admins only. Remove asks: "Remove <name>?" / "…The group key changes, so they cannot read anything new." / "Remove".
  - Non-admins also see: "Only an admin can remove someone. If you do not know them, you can leave the group."
- **Mute sheet.** "Mute notifications": "8 hours", "1 week", "Always", and "Unmute" when the chat is already muted.

## Sign-in (`/sign-in`) ✓

- **Frame.**
  - A back arrow on some pages.
  - Centre column: logo, title, subtitle and an optional server badge.
  - Then the fields, an error line, and a secondary text button with the filled primary button.
  - Footer link on the left. Hidden 152×56 corner on the bottom right.
  - Wide windows put the column in an outlined box.
- **Phone page.** "Sign in" / "Use your phone number to continue to Helix."
  - Field "Phone number" with the prefix "+880 ".
  - Helper: "New to Helix? Enter your number and we will set up your account."
  - Button "Next". Footer "Terms & Privacy".
  - Errors:
    - "Enter a valid phone number."
    - "This phone number already has an account on this server. Ask your server admin for a recovery code to sign back in."
    - "Could not reach the server. Check your connection and try again."
    - "Too many attempts. Wait a moment and try again."
    - "This server is down for maintenance. Try again shortly."
- **Personal-server phone page.**
  - Title "Join the server" or "Recover your account". Shows the server badge.
  - Helper: "Continuing moves your account to this phone."
- **SMS code page.** "Enter the code" / "We sent a 6-digit code by SMS to +880 …"
  - Field "Enter code", 6 digits, submits on the sixth.
  - Buttons "Resend code" and "Next".
  - Errors:
    - "Enter the six-digit code from the SMS."
    - "Request a new code first."
    - "That code is not right. Check the SMS and try again."
    - "This account has been blocked."
    - "This server cannot send SMS codes. Ask your server admin for an invite code."
    - "Could not sign in. Please try again."
- **Password page.** "Welcome back" / the phone label.
  - Field "Password" with an eye toggle ("Show password" / "Hide password").
  - Note: "Your other devices stay signed in. Signing in with an SMS code instead signs them out."
  - Buttons "Link from another device instead", "Forgot password?" and "Sign in".
  - Errors:
    - That password is not right. Try again, or use "Forgot password".
    - Too many wrong passwords. Try again later, or use "Forgot password". (A second version adds "Try again after HH:MM".)
    - This password no longer unlocks your account. Use "Forgot password" to reset it with an SMS code.
- **Name page (new account).** "Your name" / "This is how your contacts will see you."
  - Field "Your name".
  - Helix Global only: the checkbox "I agree to the Helix Terms of Service and Privacy Policy" and the link "Read the Terms and Privacy Policy".
  - Helper "Set a password (optional)…" and the field "Password (optional)".
  - Buttons "Skip" and "Create account".
- **Take-over page.** "Welcome back" / "Accept the terms to continue to your account."
  - Buttons "Link from another device instead" and "Continue".
  - Bug: the terms checkbox is missing, so a Helix Global take-over can't finish.
- **Code page (advanced).** "Personal server" / "Enter the invite or recovery code from your server admin."
  - Monospace field, hint "HLX-INV-… or HLX-REC-…".
  - The line under the field says what was detected:
    - "Recovery code: you will sign back in to your account."
    - "Invite code: you will create an account on that server."
    - "Your server admin gives you this code."
  - Errors cover: invalid, incomplete, used, cancelled, expired, recovery code not valid, and an insecure server.
- **Server confirmation.** "This code wants to sign you in on <host>."
  - Body: "Only continue if you know this server and expected this code. Your phone number and messages will be handled by it."
  - Buttons "Cancel" and "Continue".
- **Hidden advanced mode.** Three taps, each within 2 s, reveal "Advanced mode" for 2 s.
- **Legal sheet.**
  - 88% of the screen, with a close X.
  - Line "Version X · Effective <date>".
  - Segmented "Terms" / "Privacy" over a scrolling text box.
- **Restore step (`/restore`).**
  - "Restore your chats", with no back.
  - Intro "Welcome back", and a section "From your other devices" with the transfer rows.
  - Progress phases:
    - "Looking for your backup..."
    - "Downloading your backup..."
    - "Unlocking it..."
    - "Adding messages..."
    - "N messages added so far"
  - Buttons "Restore from my backup", "I have a recovery secret" and "Skip for now".
  - Results: "Restored N messages." or "Your backup is already on this phone. Nothing new to add.", then "Continue".
  - Footer: "You can restore later from Settings, Backup."

## Home (`/home`) ✓

- **Tabs.** Chats, Calls and Settings, with labels.
  - Swipeable on narrow windows. The app has no tab badges.
  - At 840 px and wider: the tabs switch in place, and Chats shows a two-pane view (a 380 px list beside the chat). The empty pane says "Select a chat" / "Pick a conversation from the list, or tap the new chat button to find someone."

## Chats tab ✓

- **App bar.** "Chats", a search button and an overflow menu.
  - Menu: "New group", "Join a group with a link" and "Archived chats (N)". Archived chats was moved here (approved change 2).
  - Filter chips under the title: All, Unread, Groups (approved change 1).
- **FAB.** "New chat" opens search.
- **List.** No "Archived" row any more. It moved to the menu (approved change 2).
- **Row.**
  - Avatar 52.
  - Title, bold when unread, and a verified mark for verified direct chats.
  - Time: "14:05", "Yesterday", "Mon" or "12/09/26". Accent-coloured when unread and not muted.
  - Preview line:
    - Tick (own messages only): pending, sent, delivered, read or failed.
    - Kind icon, then "Draft: " in red, or "You: ", or "<First>: " in groups.
    - Text, or the kind's label:
      - Photo, Video, GIF, Voice message, Document, Sticker, Location, Contact, Poll, Call.
      - "This message was deleted", "Couldn't decrypt this message" and "Needs a newer version of Helix", all in italics.
    - Typing replaces the line: "typing...", "Sam is typing...", "Sam and Lee are typing..." or "3 people are typing...".
  - Flags on the right, in order: muted, pin, archive (search results only), "@" (when unread), then the count ("99+" above 99). Grey when the chat is muted.
  - Never shown on a row: online dot, presence, marked-unread dot, disappearing timer.
- **Swipe.**
  - Start to end: "Pin" or "Unpin".
  - End to start: "Archive", which shows the snackbar "Chat archived" with "Undo".
- **Long-press.** Starts selection.
  - Bar: "N selected" with "Archive chats" and "Delete chats".
  - More menu: "Pin"/"Unpin", "Mute"/"Unmute"/"Mute or unmute", and "Mark as read" when anything is unread.
  - Delete asks: "Delete N chats?" / "The messages are removed from this device. People you chatted with keep their copies." / "Delete".
- **Search.** Hint "Search chats, messages and people".
  - Sections, in order: Chats, then the people panel (Groups, People, lookup rows), then Messages (snippet with the match in bold accent). Tapping a message jumps to it.
- **People panel.**
  - Contacts card: "Find your contacts on Helix", plus text saying numbers are compared scrambled and never leave the phone. Button "Allow contacts", or "Open settings".
  - "Refresh contacts" row. Its subtitle is one of:
    - "Checking your contacts..."
    - "Today's limit for checking contacts is used up. Helix will try again tomorrow."
    - "Your contacts could not be checked. Helix will try again later."
    - "N contacts are on Helix."
    - "Check which of your contacts are on Helix."
  - Number lookup:
    - Incomplete number: "To find someone by number, type the whole number, starting with the country code, like +880 1711 000001."
    - Complete number: the row "Find +880 1711 000001 on Helix" / "Only a scrambled version of the number is sent."
    - `~name`: the row "Find ~name on Helix".
  - Lookup results:
    - "Looking on Helix..."
    - Found: a person row.
    - "Not on Helix" / "Nobody on Helix matches that, or they do not let people find them this way."
    - "That is you" / "This is your own account."
    - "Too many lookups" / "You have looked up as many numbers as Helix allows today. Try again tomorrow."
    - "No connection" / "Check your connection and try again."
    - "Could not look this up" / "Something went wrong. Try again in a moment."
  - Sections: "Groups" (subtitle "Group"), "People on Helix" when browsing, "People" when searching.
  - Person rows show the name and one second line: number, ~name, about, or "Blocked".
  - Empty: "Nobody yet" / "Type a phone number or a ~Helix name to find someone." When searching: "No matches" / Nobody you know matches "q".
- **States.**
  - Loading: 8 skeleton rows.
  - Error: "Your chats could not be loaded." with "Retry".
  - Empty: "No chats yet" / "Search for a name or a number to start a secure conversation. Anyone on Helix can message you unless you block them." with "Find people".
- **Archived chats** (`/archived-chats`).
  - Swipe to "Unarchive". The selection bar has "Unarchive chats" and "Delete chats".
  - Menu: "Mute…" and "Mark as read".
  - Empty: "No archived chats" / "Chats you archive stay here until you unarchive them."

## Conversation (`/chat/:id`) ✓

- **Header.** Avatar 32, title and verified mark. Tapping it opens contact or group info.
  - Direct subtitle:
    - "typing..."
    - "online"
    - "last seen today at 14:05", "last seen yesterday at 14:05" or "last seen 12 September"
    - otherwise the number or ~name
  - Group subtitle:
    - the typing label
    - "You, Sam, Lee" (4 or fewer members)
    - "N members"
    - "You are no longer a member"
  - Actions: "Video call" and "Voice call", for direct chats only and only when nobody is blocked.
  - Menu: "Search", "Contact info" or "Group info", "Media, links and docs", "Chat settings".
- **Above the timeline.** The pending members cards (groups).
- **Timeline.**
  - Day separators: "Today", "Yesterday", the weekday, or "12 September 2026".
  - Unread divider: "N unread messages".
  - Typing dots.
  - "Scroll to latest message" button with an unread badge.
  - Empty chat: "Messages are end-to-end encrypted. Say hello."
  - Loading: spinner. Error: "This conversation could not be loaded."
- **Notices.**
  - Disappearing timer:
    - "<Who> set disappearing messages to 1 day"
    - "<Who> turned off disappearing messages"
  - Key change: "Your safety number with <name> changed"
  - Group membership:
    - "<actor> created this group"
    - "<actor> added A, B and C"
    - "<who> joined"
    - "<actor> removed …"
    - "<who> left"
  - Group changes:
    - "<actor> changed the role of <who>"
    - "<actor> changed the group settings"
    - `<actor> renamed the group to "<title>"`
    - "<actor> changed the group picture"
  - Join request: "<actor> asked to join the group"
  - Unconfirmed member: "<name> was added by the server roster. … Your messages stay hidden from them until you confirm them in the group info."
  - Your own status:
    - "You were removed from this group"
    - "You left this group"
    - "This group was deleted"
  - Calls:
    - "Voice call"
    - "Video call, 2:13"
    - "Missed voice call"
    - "No answer"
    - "Call declined"
    - "Declined video call"
    - "Call failed"
- **Bubble.** Top to bottom:
  - Author name: first incoming bubble of a run, groups only.
  - "Forwarded".
  - Reply quote: coloured bar, author ("You" for yours), kind icon and 2 lines of text. If the original is gone: "Original message not available".
  - The content.
  - Meta:
    - Timer label "5m", "1h", "1d" or "1w".
    - "Edited".
    - The time.
    - Ticks on your own messages.
    - Media without a caption shows the meta as a pill over the picture.
  - Reaction chips (emoji, plus the count when above 1; yours outlined). Tap opens the Reactions sheet.
  - Under a failed message: "Not sent" with "Retry".
- **Content.**
  - Text: mentions in bold accent, underlined links, an optional link preview (title, description and host, never an image).
  - Media grid: 1 item, 2 side by side, 3 as one large over two, or 2×2 with "+N".
    - Videos show a play glyph and a duration chip. GIFs show a "GIF" chip.
    - Transfers: download, progress ring, retry.
    - Optional caption.
  - Voice note:
    - Round play button and waveform; tap or drag to seek.
    - Shows the duration, or the position while playing.
    - Blue dot until an incoming note is played.
    - Speed chip "1x", "1.5x" or "2x", shown only while playing or when the speed isn't 1x.
  - Audio file: the file name, with no dot and no speed chip.
  - Document: icon, name on 2 lines, "482 KB · PDF", optional caption.
  - View once: a ringed "1", "Photo" or "Video", and a status: "Tap to view", "Sent" or "Opened".
  - Location: a map tile, the label ("Location") and the address. Not tappable.
  - Contact: avatar, name, and the number or "N numbers". Not tappable, with no buttons.
  - Poll or event: plain text, "Poll: …" followed by "- option" lines, or "Event: …".
  - Placeholders:
    - "You deleted this message" / "This message was deleted"
    - "Couldn't decrypt this message"
    - "This message needs a newer version of Helix"
    - "This message has disappeared"
- **Gestures.**
  - Long-press opens the actions.
  - Swiping a bubble 56 px to the side replies.
  - Tap the quote to jump, the reactions for the Reactions sheet, the media to open it.
- **Actions.**
  - Reactions: 👍 ❤️ 😂 😮 😢 🙏, plus "+" ("More reactions") for the full picker.
  - Menu, each item only when allowed:
    - "Reply"
    - "Copy" (shows "Copied")
    - "Forward"
    - "Edit": your own text or media, sent, within 15 minutes.
    - "Message info": your own messages.
    - "Select"
    - "Delete for me", which asks: "Delete this message?" / "It is removed from this device only."
    - "Delete for everyone": your own messages (or anyone's, for a group admin), within 2 days. It asks: "Delete for everyone?" / "People in this chat will see that it was deleted." If it's too late: "It can no longer be deleted for everyone."
  - No star.
- **Selecting messages.** "N selected" with Copy, Forward and Delete.
  - Delete asks: "Delete N messages?" / "They are removed from this device only." / "Delete for me".
- **Composer.**
  - Field: emoji button, the hint "Message", "Attach" (paperclip) and "Camera". The round mic sits outside the field.
  - Typing: the camera hides and the mic turns into "Send".
  - Reply: the banner "Replying to <name>" with "Cancel reply".
  - Edit: the banner "Edit message" with "Cancel edit"; the send button becomes "Save edit".
  - Mentions: "@" opens a list of up to 4 rows.
  - Emoji panel: 260 px, with chips "Smileys", "Gestures", "Hearts and symbols", "Things".
  - Attach sheet: "Document", "Camera", "Gallery", "Audio".
  - Camera sheet: "Take a photo" and "Record a video".
- **Recording.**
  - Hold the mic: a red dot, "0:07" and "‹ Slide to cancel", with a lock hint above.
  - Locked: "Delete recording", the timer, and "Send recording".
  - A plain tap shows: "Hold the microphone to record a voice message."
- **Composer replaced.** A bar with one of:
  - "You blocked this contact. Open chat settings to unblock."
  - "<Name> has blocked you. You can't message or call them."
  - "You can no longer send messages to this group."
- **In-chat search.** Hint "Search this chat".
  - Empty: "Search this chat" / "Type a word to find messages that contain it."
  - Results are a list of messages; tapping one jumps to it.
  - None: "No results" / Nothing matches "q".
- **Sub-pages (✓).** Forward, Message info, Media viewer, Video player, Send files, Shared media, Chat settings, Reactions sheet.

## Calls ✓

- **Calls tab.** "Calls" with a search button.
  - FAB "New call".
  - Quick actions: round bubbles for "Call", "Keypad", and up to two recent people ("Call <name>").
  - Header "Recent".
  - Row:
    - Avatar, and the name with "(3)" when calls are folded together. The name is red when missed or failed.
    - An arrow, then the time ("Today, 14:05", "Mon, 14:05", "12 Sep, 14:05"). Incoming and outgoing arrows are green, missed red, declined grey, failed a red error mark.
    - A call-back button.
  - Tap opens the details.
  - Long-press opens a sheet: "Voice call", "Video call", "Delete from call history".
  - Swipe to delete asks: "Delete from call history?" / "This call with <name> will be removed from your call history." / "Delete".
  - Empty: "No calls yet" / "Calls you make and receive will show up here."
  - No filters and no menu.
- **Dial pad.**
  - "Enter a number", and "Delete digit" once something is typed.
  - Keys with letters under 2–9 and "+" under 0 (long-press 0).
  - The green button "Find on Helix" is enabled at 6 or more digits and puts the number into the people search.
- **Call details.**
  - Avatar 72, name, number.
  - Round actions: "Voice call", "Video call", "Contact".
  - Section "Calls": "<Direction> voice call", the time, and the duration on the right.
  - Delete asks: "Delete from call history?" / "All N calls with <name> will be removed from your call history."
- **Incoming call.**
  - "Helix voice call" or "Helix video call", with a lock and "End-to-end encrypted".
  - A pulsing avatar, the name, and a subtitle with the number.
  - Status: "Incoming voice call".
  - A notice bar (with "Dismiss") when needed.
  - Buttons "Decline" and "Answer".
- **In call (voice).**
  - Status:
    - "Calling…", "Ringing…", "Connecting…"
    - the timer "00:12"
    - "Reconnecting…"
    - the ended reason
  - A "Poor connection" chip when the link is weak.
  - Tray: Speaker, "Video" (disabled: "Video is not available on a voice call"), "Mute", "End".
- **In call (video).**
  - Remote picture full screen, and a self tile you can drag (100×142). Tap swaps them.
  - Tap the screen to hide or show the controls.
  - Tray: "Flip", "Video", "Mute", Speaker, "End".
- **Speaker.** With two outputs it toggles. With more it opens "Audio output": "Phone", "Speaker", "Bluetooth", "Headset".
- **Ended reasons.**
  - "Call ended", "Call declined", "Call cancelled", "Missed call", "No answer".
  - "Busy: on another call" / "They are in another call right now."
  - "Answered on another device", "Declined on another device".
  - "Call failed" / "The call could not connect. Check your connection and try again."
  - The screen closes by itself after a short hold.
- **Back is ignored** during a call. There is no minimised bar and no group calls.
- **Failure sentences** (snackbar or notice):
  - Already in a call.
  - You blocked them. They blocked you.
  - Couldn't place the call.
  - Too many calls.
  - Nothing left to answer.
  - Media couldn't start.
  - Microphone permission. Camera permission.
  - "This server has no call relay set up, so calls cannot connect. Ask the server's operator to set one up."

## People ✓

- **People search** (`/home/people`). Field "Name, number or ~Helix name", with the panel below.
- **Contact info.**
  - Header: avatar 112, name, number or ~name, "Blocked" in red, and the about line.
  - Tiles: "Message", "Voice call", "Video call".
  - The key-changed banner, with "Review".
  - **Name.**
    - "Rename" (subtitle "Choose a name only you see"). Opens the dialog "Rename" with field "Name".
    - After renaming:
      - It may ask "Save in your phone contacts too?".
      - Result: "Saved, and updated in your contacts." / "Saved in Helix. Your phone did not let Helix change your contacts." / "Saved."
    - Phone row and "Helix name" row.
    - Footer: "Renaming also saves the name in your phone's contacts."
  - **Chat.**
    - "Media, links and docs".
    - "Mute notifications" switch, with "Until 14:05" or "Always".
    - "Disappearing messages": Off, 24 hours, 7 days, 90 days.
  - **Encryption.**
    - "Verify safety number", with one of: "Verified", "Safety number changed", "Not verified", "Available after your first message".
    - Footer: "Messages and calls with <name> are end-to-end encrypted. Only the two of you can read them."
  - "N groups in common".
  - "Block <name>" / "Unblock <name>".
  - "Report <name>":
    - Reasons: "Spam", "Abuse or harassment", "Pretending to be someone else", "Something else".
    - Then "Add a note (optional)".
    - Result: "Reported. No messages were sent with the report."
- **Safety number.**
  - The QR code, and 12 groups of 5 digits on a card, marked "Verified" when verified.
  - Text: "To check that your chat with <name> is private, compare this number with the one on their phone, or scan their QR code. If they match, nobody can be listening in."
  - Buttons "Scan their code" and "Mark as verified" / "Mark as not verified".
  - Not ready yet: "No safety number yet" / "Send a message first. A safety number needs both of your keys."
- **Key-changed banner.** "Safety number changed" / "Your safety number with <name> changed. That usually means they got a new phone or reinstalled Helix. It can also mean someone is interfering. Compare safety numbers with them to be sure."
- **Scan code.**
  - Dark background, hint "Point the camera at the code on their phone".
  - Match: "Verified. Your chat is private."
  - Mismatch: "That code does not match".

## Groups ✓

- **New group.**
  - Picture button, field "Group name", member picker, and the FAB "Create group" / "Create with N".
  - If some people couldn't be added: "Some people were not added".
- **Member picker.**
  - Chips for the people picked so far.
  - Search "Search name, number or ~name".
  - Check circles on each row.
  - The lookup row: `Find "<text>" on Helix`.
- **Group info.**
  - Header: avatar, title, "N members · on <server>", description, and "Edit group info".
  - The pending members cards.
  - **Group section.**
    - "Disappearing messages".
    - Admins only: "Group settings", "Invite with a link", "Join requests" ("Nobody is waiting" / "N people are waiting"), "Banned people".
  - **Members** ("N members").
    - "Add members".
    - Member rows: "You", plus "Not confirmed", "Owner"/"Admin", their server and number.
    - The ⋮ sheet: "Make admin"/"Remove admin", "Make owner", "Remove from group", "Remove and ban".
  - "Leave group", and "Delete group" for the owner.
  - Not a member: "You are not in this group".
- **Group settings.**
  - "Members can": "Edit group info", "Add members", "Send messages", each "Everyone" or "Only admins".
  - Footer: "Admins can always do all of these."
- **Invite with a link.**
  - Intro, the switch "Admins approve new members", and "Create link".
  - Link cards: "Share", "Copy" ("Link copied."), "Revoke".
- **Join requests.** Rows with "Asked <when>" and reject or approve.
  - Empty: "No one is waiting".
- **Banned people.** Rows with "Banned <when>" and "Unban".
  - Empty: "No one is banned".
- **Add members.** The picker and the FAB "Add N".
  - Results: "Added N people." or the dialog "No one was added".
- **Join a group.**
  - Field "Group link" with "Paste", and "Continue".
  - "Opening the link…".
  - Preview: avatar, name, "N members", description, and the approval note.
  - Buttons "Join group" or "Ask to join", and "Cancel".
  - Outcomes:
    - Already in: "You are already in this group." with "Open group".
    - "Joining…".
    - Joined: `You joined "<name>"`.
    - Pending: "Request sent".
    - Failed: the reason and "Retry".

## Settings ✓

- **Settings tab.**
  - Title "Settings", and the search field "Search settings".
  - Profile card: avatar 72, the name or "Add your name", the about line, "Available on <host>", and an "Edit profile" pencil.
  - Groups and rows:

| Group | Row | Subtitle |
|---|---|---|
| "Your account" | Account | "Password, export, sign out, delete" |
| | Devices | "Where you are signed in" |
| | Backup | "Encrypted history and transfer" |
| "Privacy and notifications" | Privacy | "Last seen, receipts, blocked, app lock" |
| | Notifications | "Messages, groups and calls" |
| "Messaging" | Chats | "Text size, Enter key, media downloads" |
| "System" | Storage and data | "What Helix keeps on this phone" |
| | Help and about | "Version, terms, privacy policy" |
| | Advanced | "Server details and connection" |

  - While searching: "Search results", or `No settings match "q"` / "Try a different title or description."
- **Account.**
  - "You": the masked number, and "~name".
  - "Sign-in": "Change password" or "Set a password", and "Security activity".
  - "Your data": "Export my data".
  - "Sign out" (red), with its dialog.
  - "Delete my account" (red), with the choices "Export first" / "Continue".
- **Change password.**
  - Fields "Current password", "New password", "Confirm new password", and "Show passwords".
  - Errors as in the app.
  - Done: "Your password is saved. Use it to sign in on a new phone."
- **Delete my account.**
  - "This cannot be undone", and "Type DELETE to confirm".
  - Proof, depending on the account: a password, an SMS code, or this phone's key.
- **Privacy.**
  - "Who can see": "Last seen", "Online status", "Who can add me to groups" (Everyone or Nobody).
  - "Being found": "Find me by phone number", "Find me by ~name".
  - "Messages": "Read receipts", "Typing indicators", and "Disappearing messages" for new chats.
  - "Contacts": "Blocked".
  - "App lock": "Lock Helix", and "Lock again" (Immediately, 1 minute, 5 minutes or 30 minutes).
- **Blocked.**
  - Rows with "Unblock".
  - Empty: "Nobody is blocked".
- **Notifications.**
  - When the phone has blocked them: "Notifications are turned off for Helix…", with "Allow notifications".
  - "Alerts": Messages, Groups, Calls.
  - "Sound": Sound, Vibrate.
  - "Lock screen": "Show message previews".
  - "Muted chats", each with "Unmute".
- **Chats.**
  - "Text size": Small, Default, Large, Extra large.
  - "Enter key sends".
  - "Media auto-download": Photos, Voice messages, Videos, Documents. Each is Never, On Wi-Fi only, or On Wi-Fi and mobile data.
- **Storage and data.**
  - "On this phone": Total, Messages and keys, Photos videos and files.
  - "Data use": two links. No clear-cache button.
- **Help and about.**
  - Version and Server.
  - "Legal": Terms and Privacy, Open-source licences.
  - "Diagnostics": "Send crash reports".
- **Legal page.** Segmented "Terms" / "Privacy", then the version and the body.
- **Advanced.**
  - "Server" facts.
  - "Server features": On or Off.
  - "Connection": "Check for messages now".

## Profile, Devices, Backup ✓

- **Profile.**
  - Avatar 72, with "Choose a photo" and "Remove photo". Note: "Your photo is kept on this phone. Sharing it with your contacts is not available yet."
  - "Name and about", with "Save".
  - "~Helix name": "Claim ~name" or "Save ~name", and "Remove my ~name". Rules: 3 to 32 characters, starts with a letter.
  - "Phone number", masked.
- **Devices.**
  - Intro: "These devices can read your messages…"
  - "Signed in": device rows with "This device" or "Last active …".
  - Device sheet: "Rename", "Remove this device", "Lost or stolen".
  - "Link a new device" and "Security activity".
  - "Sign out all other devices".
- **Link a new device** (approving side).
  - Scanner, and "Or paste the code" (it starts with "helix-link").
  - "Approve this device?": the "Check number", the "Your account key code", and a warning.
  - "Approve" (asks for the phone's own unlock).
  - Done: "Send history to this device".
- **Security activity.** Event rows:
  - "Signed in", "A device was added", "A device was removed", "Password changed", "Recovery code used", "Your account key was reset".
- **Link this device** (new device's side).
  - QR code, "Check number", and "Waiting for approval. Code expires in 9:45."
  - "Approved. Signing in...".
  - "Is this your account?": masked phone, ~name, key code, then "Yes, this is my account" or "No, cancel".
- **Backup.**
  - Intro.
  - "Chat history backup": "Back up automatically", "Use mobile data", "Last backup", and "Back up now".
  - "Get your history on another phone": "Restore history", "Send to my other devices".
  - "Recovery backup".
  - "Delete my server backup".
- **Restore history.** The same page as the restore step, with "Done".
- **Send to my other devices.** "Send my history", the transfer rows, and "Waiting for this phone".
- **Transfer row.**
  - Statuses:
    - "Getting your history ready (x of y)"
    - "Waiting for your other device to accept…"
    - "Ready to receive…"
    - "Receiving (x of y)"
    - "Adding messages (x of y)"
    - "Done", "Declined", "Cancelled", "Stopped"
  - Buttons: Accept, Decline, Pause, Resume, Cancel, Dismiss.
- **Recovery backup.**
  - Segmented "Create" / "Restore".
  - Create: the secret in a monospaced box, "Copy" and "Share", "I saved it", then "Create recovery backup".
  - Restore: the field "Recovery secret", then "Restore from recovery backup".
  - Footer: "Helix cannot reset or recover a recovery secret."

## Never draw these

The UI kit has them, but the app doesn't use them:
- **Chrome:** connectivity banners, and tab badges.
- **Chat rows:** online dot, marked-unread dot, presence.
- **Messages:** star, buttons under placeholders, link-preview images, tappable location or contact cards.
- **Attach sheet:** Location, Contact, Poll.
- **Calls:** call-log filters, group calls, the minimised call bar.
