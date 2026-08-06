# Phase 7 manual screen-reader pass

Run this checklist on each release candidate after the automated Flutter
guideline tests pass.

## Android — TalkBack

1. Enable TalkBack and move through onboarding, chats, calls, contacts, settings, and device management with swipe navigation.
2. Confirm every icon control announces its tooltip, every status badge announces its value, and destructive actions announce their confirmation.
3. Set display size/text to 200%; verify the primary action remains visible and each list is scrollable.
4. Open an empty and an offline/error state; confirm its primary action and retry action are reachable and named.

## Windows — Narrator

1. Start the app with Narrator enabled and use Tab/Shift+Tab through each screen.
2. Confirm focus order follows visual order, focus remains visible, and Escape closes the topmost dialog or page.
3. Verify all tooltips and status labels are announced, including call, connection, and outbox status.
4. At 200% text scaling, complete the invite-to-first-message walkthrough and device-management retry flow.

Record the OS version, screen reader version, and any failed control in the release checklist.
