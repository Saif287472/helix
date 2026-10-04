# helix_remote_ui

Design tokens, the light theme, and the stateless UI components for Helix
Remote. Depends on Flutter only: no engine, database, API or crypto package,
and not `helix_remote_domain` either. The app (Phases A1-A3 of the v2 plan)
maps its own state into the view models below and passes callbacks back out.

Import `package:helix_remote_ui/helix_remote_ui.dart`; everything is one
library split into `part` files under `lib/src/`.

## Rules (each has a test in `test/package_rules_test.dart` or the a11y suite)

- **Colours only from tokens or the colour scheme.** No `Color(0x...)` or
  `Colors.x` (not even `transparent`) outside `lib/helix_remote_ui.dart` and
  `lib/src/chat_tokens.dart`. Chat-specific fills are in `HelixChatColors`;
  severity in `HelixStatusColors`; scrims in `HelixScrimColors`.
- **Light theme only.** No dark variant exists.
- **English literals only.** No localisation layer. Strings that depend on the
  clock or locale (times, "Yesterday", durations, "1d") arrive pre-formatted in
  the view models; components never format dates.
- **Every `IconButton` has a `tooltip:`**; tappable controls are at least
  48 x 48 (guidelines are run against every gallery section). Small visual
  affordances (reaction chips, reply quote) are exposed as custom semantics
  actions on the bubble instead of 24 px buttons.
- **Text scales to 2x without overflow** and layouts are directional
  (`EdgeInsetsDirectional`, `PositionedDirectional`); bubble text takes its
  direction from its first strong letter (`helixTextDirectionOf`), so Arabic
  reads right to left in an English UI.
- **Screenshots are allowed**: nothing here blocks capture.
- **Stateless and cheap.** Components are `const`-constructible and do no work
  in `build` beyond reading the theme and one semantics label. The few
  `StatefulWidget`s own only an animation controller, a gesture recognizer, or
  a drag offset (shimmer, typing indicator, rich text, swipe-to-reply, mic).
- No camera, QR encoding, audio, maps or network code. QR codes are drawn from
  a module matrix the app encodes; the scan frame wraps a preview the app owns.

## Sizing contract for lists

| Component | Height | How to use |
|---|---|---|
| `HelixChatListTile`, `HelixPersonTile`, `HelixCallLogTile`, `HelixMessageSearchTile` | exactly `HelixChatListTile.extentFor(MediaQuery.textScalerOf(context))` | pass it as `ListView.builder(itemExtent:)`; single-line, ellipsised content, so nothing is measured |
| `HelixSectionHeader` | `HelixSectionHeader.height` (40) | fixed |
| `HelixMentionSuggestions` | `rowHeight` x up to `maxRows` | `itemExtent` inside |
| `HelixMessageBubble` and other conversation rows | content-dependent | use `HelixConversationList` (reverse, newest first, `ValueKey(item.id)`, `addAutomaticKeepAlives: false`, `findChildIndexCallback` from a map the caller builds when the list changes) |

Compute `helixRunPositions(messages)` when the list changes, never in `build`.
`HelixValue` gives every view model value equality so callers can skip
rebuilds of equal items.

## Components

**Chat list**: `HelixChatListTile` (avatar, title, preview with tick and
sender prefix, time, unread and mention badges, pinned / muted / archived,
typing, verified), `HelixSwipeableChatListTile` (+ `HelixSwipeAction`, with
matching screen-reader actions), `HelixSelectionBar` (+ `HelixBarAction`),
`HelixSectionHeader`, `HelixArchivedRow`, `HelixChatListEmpty`,
`HelixChatListSkeleton`, `HelixCountBadge`.

**Conversation**: `HelixMessageBubble` (+ `HelixBubbleActions`), run grouping
and tail, reply quote, forwarded / edited labels, `HelixReactionsRow`,
`HelixStatusTicks` (pending / sent / delivered / read / failed, with a Retry
button under failed bubbles), disappearing-timer marker, `HelixMediaGrid`
(1-5+ items, video duration, transfer progress), `HelixDocumentTile`,
`HelixAudioBubbleBody` (waveform, seek, speed), `HelixLocationCard`,
`HelixContactCard`, `HelixLinkPreviewCard`, `HelixViewOnceTile`,
`HelixPlaceholderBody` (deleted for everyone, couldn't decrypt, needs a newer
version, expired), `HelixDateSeparator`, `HelixUnreadDivider`,
`HelixSystemNotice`, `HelixTypingIndicator`, `HelixScrollToBottomButton`,
`HelixTimelineRow`, `HelixConversationList`, `HelixReactionPicker`,
`HelixMessageActionMenu` + `showHelixMessageActionMenu` +
`helixDefaultMessageActions`.

**Composer**: `HelixComposer` (grows to `maxLines`, send / mic toggle, emoji,
attach, camera), `HelixComposerBanner` (reply / edit), `HelixMicButton`
(hold, slide to cancel, slide up to lock; reports gestures only),
`HelixVoiceRecordBar`, `HelixVoiceLockHint`, `HelixMentionSuggestions`,
`HelixAttachmentSheet` + `showHelixAttachmentSheet`.

**General**: `HelixAvatar`, `HelixSearchField`, `HelixSearchAppBar`,
`HelixHighlightedTextView`, `HelixPersonTile`, `HelixMessageSearchTile`,
`HelixCallLogTile`, `HelixNoResults`, `HelixSettingsSection` /
`HelixSettingsTile` / `HelixSettingsSwitchTile` / `HelixProfileHeaderTile`,
`HelixBanner` (offline / connecting / update / info),
`showHelixBottomSheet` / `HelixBottomSheetScaffold`, `showHelixConfirmDialog`,
`showHelixTextInputDialog`, `showHelixDestructiveDialog`, `showHelixSnackBar`,
`HelixSafetyNumberView`, `HelixQrDisplay`, `HelixQrScanFrame`, `HelixShimmer`,
plus the pre-existing `HelixEmptyState`, `HelixErrorState`, `HelixSkeleton`,
`HelixAsyncPanel`, `HelixStatusBadge`.

**Gallery** (no app wiring): `HelixComponentGallery` and the sections
`HelixGalleryChatList`, `HelixGalleryConversation`, `HelixGalleryComposer`,
`HelixGalleryGeneral`, with `HelixGallerySamples`. All sample data is made up.

## View models (`lib/src/view_models.dart`)

Value objects with `==` by content (`HelixValue`).

- Naming: `HelixAvatarModel`, `HelixPersonNames` (display = phone-book name,
  nickname, number, `~Helix name`; `secondary` is the line under it),
  `HelixPersonItem`, `helixInitials`.
- Chat list: `HelixChatListItem`, `HelixChatPreview`, `HelixPreviewKind`,
  `HelixDeliveryStatus`.
- Conversation: `HelixMessage` with a sealed `HelixMessageContent`
  (`HelixTextContent`, `HelixMediaContent` / `HelixMediaItem`,
  `HelixAudioContent`, `HelixDocumentContent`, `HelixLocationContent`,
  `HelixContactContent`, `HelixViewOnceContent`, `HelixPlaceholderContent`),
  `HelixReplyQuote`, `HelixReaction`, `HelixLinkPreview`, `HelixTransferState`,
  `HelixRunPosition` + `helixRunPositions`, and the sealed
  `HelixTimelineItem` (`HelixMessageItem`, `HelixDateSeparatorItem`,
  `HelixUnreadDividerItem`, `HelixSystemNoticeItem`).
- Composer: `HelixComposerBannerModel`, `HelixMentionCandidate`,
  `HelixVoiceRecordState`.
- Search, calls, misc: `HelixMessageSearchResult`, `HelixHighlightedText`,
  `HelixTextRange`, `HelixCallLogItem` / `HelixCallDirection`,
  `HelixBannerKind`, `HelixQrMatrix`.

The content types follow `docs/protocol/v2/CONTENT_V2.md`: text, media
(image / video / document / voice note), location, contact, an unknown type or
newer version shown as "needs a newer version of Helix" (never raw JSON), and
view-once. Sticker, poll, event and live-location bubbles are not built yet;
until they are, the app should map them to `HelixPlaceholderContent(unsupported)`
or add a content type here in the phase that needs it.

## Tests

`flutter test` in this package:

- `chat_models_test.dart`: naming order, initials, run grouping, equality,
  text direction.
- `chat_list_widgets_test.dart`, `conversation_widgets_test.dart`,
  `composer_and_general_test.dart`: behaviour and callbacks of each component.
- `chat_accessibility_test.dart`: tap-target, label and contrast guidelines on
  every gallery section; 1x / 1.5x / 2x text; RTL; tooltips.
- `chat_performance_test.dart`: the 5,000-chat and 1,000-message budgets.
  These count rows built per frame (which must not depend on list length) and
  compare timings between two sizes on the same machine; they never assert a
  wall-clock figure. The 16 ms per frame number is a release-profile property
  to be checked by the app's own performance-budget test (plan 6.4).
- `package_rules_test.dart`: colour literals, tooltips, Flutter-only
  dependencies, no localisation or screenshot blocking.
- `component_gallery_golden_test.dart` (existing) and
  `chat_components_golden_test.dart`: goldens.

### Goldens

Linux is the reference platform (CI's `ubuntu-latest`); on other platforms the
golden tests skip. `chat_components_golden_test.dart` also skips while a
baseline PNG is missing, so a new golden never turns a run red. To create or
refresh baselines, on Linux, from `helix_remote/packages/helix_remote_ui`:

    flutter test test/chat_components_golden_test.dart --update-goldens

then review every PNG in `test/goldens/` and commit them. To look at the output
on another OS without committing, run with `HELIX_GOLDENS_ANY_PLATFORM=1` and
`--update-goldens`, and delete the PNGs afterwards: text and icon rasterisation
differs per platform.

Addition (A2a): `HelixMessage.copyWith({content, status, highlighted})`, for
bubbles whose content or highlight comes from outside the list row.
