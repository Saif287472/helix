# Contract: conversation

Prototype screens: `chat` (states: `chat`, `chat-typing`, `chat-reply`, `chat-edit`, `chat-attach`, `chat-emoji`, `chat-rec`, `chat-rec-lock`, `chat-actions`, `chat-actions-mine`, `chat-select`, `chat-search`, `chat-search-q`, `chat-kinds`, `chat-transfer`, `chat-new`, `group`, `group-mention`, `group-pending`, `group-pending-member`, `group-left`, `chat-blocked`, `chat-blocked-me`), `forward` (states: `forward`, `forward-picked`), `message-info` (states: `message-info`, `message-info-group`, `message-info-gone`), `media-viewer` (states: `media-viewer`, `media-video`, `media-video-failed`, `media-not-here`, `media-viewonce-opened`, `media-viewonce-mine`), `send-files` (states: `send-files`, `send-files-empty`), `shared` (states: `shared`, `shared-docs`, `shared-links`, `shared-empty`), `chat-settings` (states: `chat-settings`, `chat-settings-group`, `chat-settings-blocked`)
Today's app: `features/conversation/presentation/…`, `features/conversation/application/…`, `core/chat/…`, `shared/widgets/pending_members_prompt.dart`, `shared/widgets/unconfirmed_member_host.dart`, `helix_remote_ui/lib/src/{view_models,message_bubble,message_media,composer,conversation_parts,message_actions}.dart`

Paths below: `conv/` is `helix_remote/app/lib/features/conversation/`, `app/` is `helix_remote/app/lib/`, `ui/` is `helix_remote/packages/helix_remote_ui/lib/src/`. A `rowId` is the message's database id as a string (`HelixMessage.id`); a `messageId` is its content id (what quotes, jumps and search hits name). Names are `Chat*` for the conversation itself, so they do not clash with the app's `ConversationScreen` and `ConversationActions`.

## Conversation (`chat`)

Dart: `ChatScreen`, `ChatModel`, `ChatActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `conversationId` | `String` | have | route param `conversationId` (`conv/conversation_routes.dart`) | `direct:<account>` or `group:<id>` |
| `loadState` | `ChatLoadState` {loading, openFailed, loadFailed, ready} | have | `conversationOpenProvider(id)` and `timelineProvider(args)` AsyncValues (`conv/application/timeline_provider.dart`) | The prototype draws only `ready`; see the app-only table |
| `title` | `String` | have | `ConversationHeader.title` from `conversationHeaderProvider(id)` (`conv/application/conversation_header.dart`) | People naming rule; group name or "Group" |
| `avatar` | `HelixAvatarModel` | have | `ConversationHeader.avatar` | |
| `subtitle` | `String?` | have | `ConversationHeader.subtitle` | Direct: "typing...", "online", "last seen …" (`formatLastSeen`, `app/core/format/labels.dart`), else number or ~name. Group: "Sam is typing...", "You, Sam, Lee", "N members", "You are no longer a member" |
| `subtitleIsTyping` | `bool` | have | `ConversationHeader.typing` | Accent colour on the subtitle |
| `verified` | `bool` | have | `ConversationHeader.verified` | Seal after the name |
| `isGroup` | `bool` | have | `ConversationHeader.isGroup` | Menu says "Group info" or "Contact info" |
| `showCallButtons` | `bool` | derive | `ConversationHeader.peerAccount != null && !blocked && !blockedByPeer` (today inline in `conv/presentation/conversation_app_bar.dart`) | Never for groups |
| `hasInfoPage` | `bool` | derive | `infoLocationOf(id) != null` (`conv/application/conversation_links.dart`) | Hides "Contact info"/"Group info" when null |
| `pendingMembers` | `List<PendingMemberItem>` {account, title, explanation, canRemove} | have | `pendingMembersProvider(groupId)` → `PendingMemberView.account/.title/.explanation/.canRemove` (`app/features/groups/application/group_pending.dart`) | Groups only. Two reasons today (roster, invite link); the prototype draws only the roster one |
| `rows` | `List<ChatRow>` {item: `HelixTimelineItem`, messageId: `String?`, replyToId: `String?`}, newest first | have | `timelineProvider(args)` → `TimelineSnapshot.newestFirst` → `TimelineEntry.item/.messageId/.replyToId` (`conv/application/timeline_builder.dart`) | Every bubble kind, day separators, unread divider, notices. Empty list = the "Messages are end-to-end encrypted. Say hello." card |
| media content of shown rows | merged into `HelixMessage.content` of `rows` | derive | `messageMediaProvider(rowid)` + `mediaContentOf(...)` (`conv/application/media_content.dart`), with `playbackProvider` for audio (`conv/application/audio_playback.dart`) | Media rows carry a blank placeholder (`mediaPlaceholderContent`) until merged. Today `_MediaBubble` (`conv/presentation/timeline_row.dart`) watches per built row; the connector does the same for the ids from `onRowsShown`. `HelixAudioContent.played` (the blue dot) is in memory only: see New backend work |
| `hasOlder` | `bool` | have | `TimelineSnapshot.hasOlder` | |
| `hasNewer` | `bool` | have | `TimelineSnapshot.hasNewer` | True after a jump into the past; scroll-to-latest stays visible |
| `someoneTyping` | `bool` | have | `conversationTypingProvider(id)` is not empty | Typing bubble under the newest message |
| `unreadCount` | `int` | have | `conversationRowProvider(id)` → `ConversationRow.unreadCount` | Badge on "Scroll to latest message" |
| `jump` | `({String messageId, int serial})?` | have | `timelineJumpProvider(id)` → `TimelineJump.messageId/.serial` | Scroll to it and highlight; clears after 2.2 s (prototype 1.6 s) |
| `initialMessageId` | `String?` | have | route query `m` (`ConversationScreen.messageId`) | Opened from a search hit or "Show in chat" |
| `selectedIds` | `Set<String>` | have | `messageSelectionProvider(id)` (`conv/application/message_actions.dart`) | Non-empty = selection bar, no composer, no pending cards |
| `HelixMessage.authorAvatar` (new field) | `HelixAvatarModel?` = null | derive | `PeopleDirectory.avatarOf(row.sender)` (`app/core/people/people_names.dart`), set in `mapMessage` (`conv/application/message_mapper.dart`) | The 30 px avatar beside the last incoming bubble of a group run. Today groups show only the coloured name |
| `HelixMediaItem.sizeLabel` (new field) | `String?` = null | derive | `formatFileSize(AttachmentRow.size)` in `_gridItem` (`conv/application/media_content.dart`) | "2.4 MB" in the download chip of a photo or video not yet downloaded |
| `HelixSystemNoticeItem.tone` (new field) | `HelixNoticeTone` {plain, warning, missedCall} = plain | derive | `safety_number_changed` payload → warning; incoming missed `call_log` → missedCall (same test as `callLogIcon`, `app/core/chat/message_semantics.dart`); set in `buildTimeline` | Amber key-change notice, red missed-call notice |
| `HelixReplyQuote.thumbnail` (exists, unfilled) | `ImageProvider?` | derive | not set by `quoteOf` (`conv/application/message_mapper.dart`); would be the quoted message's first attachment thumbnail | Optional. The prototype draws it when present; no prototype state uses it |
| `composerDisabledReason` | `String?` | have | `ConversationHeader.composerDisabledReason` | Replaces the composer: "You blocked this contact. Open chat settings to unblock." / "<Name> has blocked you. You can't message or call them." / "You can no longer send messages to this group." Same copy as the prototype |
| `initialDraft` | `String` | have | `composerDraftProvider(id)` (`conv/application/composer_notifier.dart`) | The unsent text from last time |
| `banner` | `HelixComposerBannerModel?` | have | `composerProvider(id)` → `ComposerState.reply/.edit` (`ComposerTarget.authorName/.text/.kind`); the model is built in `conv/presentation/composer_bar.dart` today | "Replying to <name>" / "Edit message". Prototype says "Replying to yourself", app "Replying to You" (style only) |
| `editing` | `bool` | have | `ComposerState.edit != null` | Send button becomes "Save edit" |
| `mentionCandidates` | `List<HelixMentionCandidate>` | have | `ComposerState.mentionCandidates` | Groups only; yourself left out |
| `recording` | `HelixVoiceRecordState?` | have | `ComposerState.recording` | Held vs locked, elapsed label, slide progress |
| `recordingLevels` | `Uint8List?` | derive | `DeviceVoiceRecorder` reads loudness (`amplitudes`, `app/core/platform/device_voice_recorder.dart`) but `VoiceRecorder` (`app/core/platform/voice_recorder.dart`) does not expose it while recording | Live waveform in the locked recording bar. App-only adapter change, no engine work |
| `enterSends` | `bool` | have | `enterToSendProvider` (`app/features/settings/application/settings_providers.dart`) | The composer ignores this setting today. Default is off; the prototype sends on Enter |
| `toast` | `({String text, int serial})?` | have | `ComposerState.notice/.noticeSerial` and `PlaybackState.notice/.noticeSerial` | Sentences listed in the app-only table |
| `searchState` | `ChatSearchState` {idle, loading, error, ready} | have | `inChatSearchResultsProvider(id)` AsyncValue (`conv/application/conversation_search.dart`) | idle = empty query |
| `searchHits` | `List<SearchHitItem>` {result: `HelixMessageSearchResult`, messageId} | have | `InChatHit.result/.messageId` | Snippet ranges mark the matching words |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenInfo` | `void Function()` | have | `context.push(infoLocationOf(id))` (`conv/application/conversation_links.dart`) | Interaction: tap header; menu "Contact info"/"Group info" |
| `onCall` | `Future<String?> Function({required bool video})` | have | `ConversationCalls.isAvailable`, `.start(peer, video:)` (`conv/application/conversation_calls.dart`) | Returns a sentence to show, null when the call started. Interaction: tap Voice / Video |
| `onOpenSharedMedia` | `void Function()` | have | push `sharedMediaLocation(id)` (`app/shared/navigation/chat_locations.dart`) | Interaction: menu "Media, links and docs" |
| `onOpenSettings` | `void Function()` | have | push `chatSettingsLocation(id)` | Interaction: menu "Chat settings" |
| `onLoadOlder` | `void Function()` | have | `TimelineWindowNotifier.loadOlder` (`conv/application/timeline_provider.dart`) | Within 800 px of the top today |
| `onLoadNewer` | `void Function()` | have | `TimelineWindowNotifier.loadNewer` | Only after a jump into the past |
| `onScrollToLatest` | `void Function()` | have | `TimelineWindowNotifier.jumpToLatest` when `hasNewer` | Interaction: tap Scroll to latest (the scroll itself is inside) |
| `onAtBottomChanged` | `void Function(bool atBottom)` | have | `ReadTracker.setAtBottom` (`conv/application/read_tracker.dart`) | Marks read only at the bottom |
| `onRowsShown` | `void Function(List<String> rowIds)` | derive | `ReadTracker.messagesChanged`, `ReadTracker.displayed`, and the media merge above | `ReadTracker.displayed` (starts disappearing timers on first display) exists but nothing calls it today |
| `onJumpTo` | `void Function(String messageId)` | have | `TimelineJumpNotifier.to`; `TimelineWindowNotifier.jumpTo` when the message is outside the window (`conv/presentation/timeline_view.dart`) | Interactions: tap quoted reply; tap search result |
| `messageMenu` | `Future<MessageMenuModel?> Function(String rowId)`; `MessageMenuModel` {actionIds, allowReactions, currentReaction} | have | `ConversationActions.menuFor(rowid)` → `MessageMenu.actions[].id/.allowReactions/.currentReaction` (`conv/application/message_actions.dart`) | Interactions: long-press, right-click. Rules: no reply on deleted, undecryptable, unsupported or view-once; edit own text or media, sent, within 15 min; delete for everyone own (or anyone's, for a group admin), sent, within 2 days; no star. Null when the message is gone |
| `onReact` | `Future<void> Function(String rowId, String emoji)` | have | `ConversationActions.react` | Same emoji again takes it back; another swaps. Interactions: reaction in the actions view; "+" sheet |
| `reactionsOf` | `Future<List<ReactionItem>> Function(String rowId)`; `ReactionItem` {emoji, name, avatar, mine} | have | `reactionDetailsProvider(rowid)` → `ReactionLine` (`conv/application/message_info.dart`) | Interaction: tap reaction under a message |
| `onRemoveMyReaction` | `Future<void> Function(String rowId)` | have | `ChatGateway.react(rowid, null)` (`app/core/chat/chat_gateway.dart`) | "Tap to remove" in the Reactions sheet; today's sheet rows do nothing on tap |
| `onReply` | `Future<void> Function(String rowId)` | have | `ComposerNotifier.reply` | Interactions: swipe 56 px; menu Reply |
| `onCopy` | `Future<void> Function(List<String> rowIds)` | have | `ConversationActions.copy` | Oldest first, one per line. Interactions: menu Copy; selection Copy |
| `onForward` | `void Function(List<String> rowIds)` | have | push `forwardLocation(id, rowids)` | Interactions: menu Forward; selection Forward |
| `onEdit` | `Future<String?> Function(String rowId)` | have | `ComposerNotifier.beginEdit` | Returns the text for the field; null when it can no longer be edited |
| `onMessageInfo` | `void Function(String rowId)` | have | push `infoLocation(id, rowid)` | Interaction: menu Message info |
| `onSelect` | `void Function(String rowId)` | have | `MessageSelection.start` | Interaction: menu Select |
| `onToggleSelect` | `void Function(String rowId)` | have | `MessageSelection.toggle` | Interaction: tap or long-press while selecting |
| `onClearSelection` | `void Function()` | have | `MessageSelection.clear` | Interaction: × in the selection bar; back |
| `onDeleteForMe` | `Future<void> Function(List<String> rowIds)` | have | `ConversationActions.deleteForMe` | The confirm dialog is inside. Interactions: menu; selection Delete |
| `onDeleteForEveryone` | `Future<bool> Function(String rowId)` | have | `ConversationActions.deleteForEveryone` | False → "It can no longer be deleted for everyone." |
| `onRetry` | `void Function(String rowId)` | have | `ConversationActions.retry` → `ChatGateway.retrySend` | Interaction: Retry on a failed message |
| `onOpenLink` | `void Function(String url)` | have | `launchUrl(uri, externalApplication)`, http and https only (`conv/presentation/conversation_screen.dart`) | Not in INTERACTIONS.md; links are underlined in bubbles and the link card is tappable |
| `onTapMedia` | `Future<void> Function(String rowId, int index)` | have | `MediaActions.tap` (`conv/application/media_viewer.dart`); then push `mediaLocation(id, rowid, index:)` for a photo or video, `MediaActions.share` for a document | Downloads, cancels or retries when not on the device. Interactions: tap photo; Document button |
| `onOpenViewOnce` | `void Function(String rowId)` | have | push `mediaLocation(id, rowid)` | The viewer says "already opened" or "you sent it". Interaction: tap view-once |
| `onToggleAudio` | `Future<void> Function(String rowId)` | have | `PlaybackNotifier.toggle(rowid, attachmentId)`; `MediaActions.tap` when not downloaded | Interaction: voice play |
| `onAudioSpeed` | `void Function()` | have | `PlaybackNotifier.cycleSpeed` | 1x, 1.5x, 2x; one speed for every note. Interaction: voice speed |
| `onAudioSeek` | `void Function(String rowId, double fraction)` | have | `PlaybackNotifier.seek` | Not in INTERACTIONS.md; SCREENS.md says "tap or drag to seek" |
| `onTextChanged` | `void Function(String text, int cursor)` | have | `ComposerNotifier.onChanged` | Saves the draft after 500 ms, sends typing, offers mentions. Interactions: type in the box; @ in a group |
| `onPickMention` | `({String text, int cursor}) Function(HelixMentionCandidate person, String text, int cursor)` | have | `ComposerNotifier.pickMention` | Inserts "@Name " and remembers the account for the mention range |
| `onSend` | `Future<bool> Function(String text)` | have | `ComposerNotifier.send` | Also saves an edit. True → clear the field. Interactions: Send; Enter; Save edit |
| `onCancelBanner` | `void Function()` | have | `ComposerNotifier.cancelTarget` | Interaction: × on the reply or edit banner |
| `onPickFiles` | `Future<void> Function(ChatAttachSource source)` {gallery, document, audio, cameraPhoto, cameraVideo} | have | `ComposerNotifier.pick(AttachmentSource)` → `PendingAttachments.set` → push `sendFilesLocation(id)` (`conv/presentation/composer_bar.dart`) | Interactions: Camera sheet (Take a photo, Record a video); attach sheet (Document, Camera, Gallery, Audio) |
| `onVoiceStart` | `Future<void> Function()` | have | `ComposerNotifier.startVoice` | Asks for the microphone the first time. Interaction: hold Microphone |
| `onVoiceSlide` | `void Function(double cancel, double lock)` | have | `ComposerNotifier.slideVoice` | |
| `onVoiceLock` | `void Function()` | have | `ComposerNotifier.lockVoice` | Interaction: slide onto the lock |
| `onVoiceEnd` | `Future<void> Function({required bool send})` | have | `ComposerNotifier.endVoice` | Interactions: release; Send / Delete while locked; slide to cancel |
| `onLeave` | `Future<void> Function(String text)` | have | `ComposerNotifier.flushDraft`, `PlaybackNotifier.stop` | Screen closing: saves the draft, stops typing and playback |
| `onSearchQuery` | `void Function(String query)` | have | `InChatSearchQuery.set` | 250 ms debounce in the provider. Interaction: type in Search; × clears; ← closes (sets "") |
| `onConfirmMember` | `Future<String?> Function(String account)` | have | `GroupActions.confirmMember` → `GroupResult.message` (`app/features/groups/application/group_actions.dart`) | Copy differs in meaning: prototype toast "Karim Uncle confirmed."; app "<name> was confirmed. They get your messages in this group from now on." Keep the app's |
| `onRemoveMember` | `Future<String?> Function(String account)` | have | `GroupActions.removeMember` → `GroupResult.message` | Admins only; the "Remove <name>?" dialog is inside |
| simulated reply after Send | none | demo | none | "In the demo chat Nadia types, then replies": not built |

The connector, not the screen, follows the app lifecycle: `ReadTracker.setForeground`, `ComposerNotifier.appBackgrounded` / `appResumed` (a held recording is dropped, a locked one pauses).

### Kept inside the screen

- Search open or closed, the query text, the × and ← buttons.
- Selection bar layout; the Delete confirm dialog ("Delete this message?" / "Delete N messages?", "They are removed from this device only.").
- The actions view (overlay with reactions, the message, the menu), closing it on an outside tap, the "+" emoji sheet, the Reactions sheet, every confirm dialog, the "Copied" toast.
- Swipe-to-reply tracking and the 56 px threshold (off while selecting, and when `composerDisabledReason` is set, as in the prototype; the app still allows it today).
- Long-press timer, right-click.
- Scroll position, opening at the unread divider or `jump`, the scroll-to-latest button's visibility and animation, keeping the reading position when messages arrive below, the highlight flash.
- The text controller, cursor, field growth to 128 px, mic-to-send swap, camera button hidden while typing, Enter versus Shift+Enter (reads `enterSends`).
- Emoji panel open or closed, its tab, inserting an emoji at the cursor, closing it when the field gets focus. The panel is pure Dart (`emojiGroups`, `conv/presentation/emoji_panel.dart`), not a platform piece; it moves into `orbit_ui`.
- The attach and camera sheets themselves; the pick goes through `onPickFiles`.
- The hold-to-record gesture, the lock pill, "Slide to cancel".
- "Hold the microphone to record a voice message." on a plain tap of the mic.
- The ⋮ menu.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none: camera and file picker | System UI opened by `onPickFiles` through `AttachmentPicker` (`app/core/platform/attachment_picker.dart`); nothing is embedded | Goes straight to `send-files` |
| none: audio playback | No widget. `AudioPlayerAdapter` (`app/core/platform/audio_player.dart`) feeds `HelixAudioContent` (playing, progress, position, speed) | Static voice bubble |
| none: links and calls | System browser (`onOpenLink`); the call screen (`onCall`) belongs to `calls.md` | A toast or the call screen |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner while the conversation opens; "This conversation could not be opened." and "This conversation could not be loaded." | `conv/presentation/conversation_screen.dart`, `timeline_view.dart` | Add to the design (loading and error states) |
| Opens at the unread divider; follows the newest message when at the bottom or after you send; otherwise keeps your place | `conv/presentation/timeline_view.dart` | Keep today's behaviour |
| Paging older and newer, and jumping to a message outside the loaded window | `conv/application/timeline_provider.dart` | Keep today's behaviour |
| Read receipts sent only while in the foreground and scrolled to the bottom | `conv/application/read_tracker.dart` | Keep today's behaviour |
| Back closes selection, then search, before leaving | `conv/presentation/conversation_screen.dart` (`PopScope`) | Keep today's behaviour |
| Composer toasts: "The message could not be sent." · "The camera is not available on this device." · "Allow camera access in your phone settings to take photos and videos." · "Sending files is not available on this device." · "These files could not be prepared, so nothing was sent. Photos are only sent once their location details have been removed." · "One file was not sent: its location details could not be removed." / "N files were not sent: …" · "The files could not be sent." · "Voice messages are not available on this device." · "Allow microphone access in your phone settings to record voice messages." · "Hold the microphone to record, then let go to send." (too short, or the permission prompt ended the hold) · "That is the longest a voice message can be, so it was sent." (10 minutes) · "The recording was stopped because you left the app." · "Nothing was recorded. Hold the microphone and speak." · "The voice message could not be sent." | `conv/application/composer_notifier.dart` | Keep in the new toast style |
| Camera and microphone permission prompts (system) | `composer_notifier.dart` via `AttachmentPicker`, `VoiceRecorder` | Keep today's behaviour |
| Playback toasts: "Downloading the audio..." · "The audio could not be downloaded." · "Audio playback is not available on this device." · "This audio could not be played." | `conv/application/audio_playback.dart` | Keep in the new toast style |
| "Calls are not available on this device." and the call launcher's failure sentence | `conv/presentation/conversation_app_bar.dart` | Keep in the new toast style |
| "It can no longer be deleted for everyone." (too late) | `conv/presentation/conversation_screen.dart` | Keep (SCREENS.md lists it) |
| A group admin sees "Delete for everyone" on other people's messages | `conv/application/message_actions.dart` | Keep (the menu decides) |
| Reactions sheet spinner while loading | `conv/presentation/conversation_screen.dart` (`_ReactionsList`) | Keep today's behaviour |
| In-chat search spinner; "The search could not be run." | `conv/presentation/in_chat_search_view.dart` | Add the error to the design |
| Pending card: second reason "<name> joined this group through its invite link, and nothing else vouches for them."; buttons disabled while busy; result toasts ("… was confirmed. They get your messages in this group from now on." · "… is no longer waiting for confirmation." · "… was removed." · failure sentences) | `app/core/groups/pending_member_copy.dart`, `app/shared/widgets/pending_members_prompt.dart`, `group_actions.dart` | Add the invite-link reason to the design; keep the toasts |
| App-wide toast "<name> was added to "<group>" by the server roster. Review it." with Review, 8 s | `app/shared/widgets/unconfirmed_member_host.dart` | Keep; it belongs to `frame.md` |
| Leaving mid-recording throws the recording away; leaving saves the draft and stops typing | `composer_notifier.dart` (`build` dispose, `flushDraft`) | Keep today's behaviour |
| "Ask to resend" / "Update Helix" buttons under placeholders exist in `ui/message_media.dart` but the app never wires them | `conv/presentation/timeline_row.dart` | Drop (SCREENS.md: never draw) |

### New backend work

| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| Remember that a voice note was played | Blue dot "until an incoming note is played". Today `PlaybackState.played` is in memory only: the dot returns after a restart and clears only when played to the end | Engine and db: a local flag and schema 5 migration; no protocol | M (optional) |

## Forward (`forward`)

Dart: `ForwardScreen`, `ForwardModel`, `ForwardActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `messageCount` | `int` | have | route query `ids` (`ForwardScreen.rowids`, `conv/conversation_routes.dart`) | Title "Forward message" / "Forward N messages" |
| `loadState` | `LoadState` {loading, error, ready} | have | `forwardTargetsProvider` AsyncValue (`conv/application/forward_targets.dart`) | |
| `targets` | `List<ForwardTargetItem>` {id, title, avatar, isNewChat} | have | `ForwardTarget.id/.title/.avatar/.newPeer != null` | Chats newest first, then people without a chat by name; blocked people left out. The prototype lists chats only |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onSend` | `Future<int> Function(Set<String> targetIds)` | have | `ConversationActions.forward(rowids, targets, peersToOpen:)` (`conv/application/message_actions.dart`) | Returns the number of failed sends. 0 → close and "Forwarded"; more → close and "Some messages could not be forwarded". Interaction: Send to N chats |

### Kept inside the screen

- Picked rows (Interaction: tap chat row), the search text and filtering by title (Interaction: type Search), the busy spinner on the button.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner; "Your chats could not be loaded." | `conv/presentation/forward_screen.dart` | Add to the design |
| "Some messages could not be forwarded" | `forward_screen.dart` | Keep in the new toast style |
| People without a chat as targets (the chat is created on send) | `conv/application/forward_targets.dart` | Add to the design (rows look the same) |
| No results: "Nothing matches "q"." (prototype: "No results" only) | `HelixNoResults` (`ui/search_people.dart`) | Keep today's copy |

### New backend work

None.

## Message info (`message-info`)

Dart: `MessageInfoScreen`, `MessageInfoModel`, `MessageInfoActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `loadState` | `MessageInfoState` {loading, error, notFound, ready} | have | `messageInfoProvider(rowid)` (`conv/application/message_info.dart`); null value = not found | `message-info-gone`: "Message not found" / "It may have been deleted." (same in both) |
| `message` | `HelixMessage` | derive | `mapMessage(row, ctx)` (`conv/application/message_mapper.dart`) over `ChatGateway.message(rowid)` | The prototype shows the bubble; today the page shows only `MessageInfo.preview` (text) |
| `sentLabel` | `String` | have | `MessageInfo.sentLabel` | |
| `isGroup` | `bool` | derive | `peerOfConversation(row.conversationId) == null` (`app/core/chat/chat_naming.dart`) | "Recipients" heading for groups |
| `recipients` | `List<ReceiptItem>` {name, avatar, readLabel?, deliveredLabel?} | have | `MessageInfo.lines` → `ReceiptLine` | Prototype shows one line ("Read …", else "Delivered …", else "Not delivered yet"); the app shows Read and Delivered both. Style only |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| none | | | | INTERACTIONS.md: nothing beyond reading and the back arrow (frame) |

### Kept inside the screen

- Nothing.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner; "The details could not be loaded." | `conv/presentation/message_info_screen.dart` | Add to the design |

### New backend work

None.

## Media viewer (`media-viewer`)

Dart: `MediaViewerScreen`, `MediaViewerModel`, `MediaViewerActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `state` | `ViewerState` {loading, nothingToShow, viewOnceOpened, viewOnceMine, ready} | have | `viewerMetaProvider(rowid)` → `ViewerMeta.viewOnce/.outgoing/.alreadyOpened` (`conv/application/media_viewer.dart`) and `messageMediaProvider(rowid)` | "This view-once message has already been opened." / "You cannot open a view-once message you sent." (same in both) |
| `title` | `String` | have | `ViewerMeta.senderName` | "You" for yours; "View once" when it is your own view-once |
| `timeLabel` | `String` | have | `ViewerMeta.timeLabel` | The screen adds "(2 of 6)" from its index |
| `caption` | `String` | have | `ViewerMeta.caption` | |
| `items` | `List<ViewerItem>` {isVideo, image: `ImageProvider?`, thumbnail: `ImageProvider?`, onDevice: `bool`} | have | the visual `MediaPart`s of `messageMediaProvider(rowid)`: `.isVisual`, `.ready`, `view.localPath ?? row.localPath`, `mediaThumbnailOf(part)` (`conv/application/media_content.dart`) | The photos and videos of one message (an album). Not on device → "This file is not on your device yet." (`media-not-here`) |
| `initialIndex` | `int` | have | route query `i` (`conv/conversation_routes.dart`) | |
| `canShare` | `bool` | derive | `!ViewerMeta.viewOnce` | The prototype hides Share for view-once and missing files |
| `video` | `VideoView?` {phase: opening, ready or failed; playing; buffering; completed; fraction; positionLabel; durationLabel; speed; message} | have | `videoSessionProvider(path)` → `VideoViewState` (`conv/application/video_session.dart`) | Only for the video on screen |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onPageChanged` | `void Function(int index)` | derive | The connector moves the video session to that page's file (today `_MediaPage(active:)` in `conv/presentation/media_viewer_screen.dart`) | Interactions: swipe left and right; Previous / Next; ← / → |
| `onShare` | `Future<void> Function(int index)` | have | `MediaActions.share(part)` | Interaction: Share |
| `onOpenVideoElsewhere` | `Future<void> Function(int index)` | have | `MediaActions.share(part)` | Interaction: Open video (cannot play) |
| `onVideoToggle` | `Future<void> Function()` | have | `VideoSession.toggle` | Plays again from the end. Interaction: Play / Pause |
| `onVideoSeek` | `Future<void> Function(double fraction)` | have | `VideoSession.seek` | The seek bar |
| `onVideoSpeed` | `Future<void> Function()` | have | `VideoSession.cycleSpeed` | Interaction: Speed |
| `onViewOnceShown` | `Future<void> Function()` | have | `ViewOnceSession.open` (`viewOnceSessionProvider(rowid)`) | Only once the file is on screen; tells the sender |
| `onClose` | `Future<void> Function()` | have | `ViewOnceSession.close` | Leaving deletes a view-once file for good |

The connector pauses the video when the app goes to the background (`VideoSession.pause`).

### Kept inside the screen

- The current page and the "(n of m)" subtitle and dots.
- Controls shown or hidden (Interaction: tap Video), hiding 3 s after playing starts.
- The seek bar while dragged, photo zoom and pan, swipe tracking, the arrow keys, the window's Previous / Next buttons.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| `videoSurface` | `VideoViewState.surface` from `VideoPlayers` (`app/core/platform/video_player.dart`, the `video_player` plugin) | A still picture under the play button |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner while loading; "There is nothing to show here."; "This picture cannot be shown." | `conv/presentation/media_viewer_screen.dart` | Add to the design |
| Video opening (poster with spinner), buffering spinner, "Play again" after the end | `conv/presentation/video_player_view.dart` | Add to the design |
| Three failure sentences: "Videos cannot be played inside Helix on this device." · "This video cannot be played on this device." · "This video stopped playing." (prototype: "This video cannot be played.") | `conv/application/video_session.dart` | Keep today's sentences in the prototype's layout |
| Photo zoom and pan | `media_viewer_screen.dart` (`InteractiveViewer`) | Keep today's behaviour |
| Share shown but disabled for view-once | `media_viewer_screen.dart` | Hide it, as the prototype does |

### New backend work

None.

## Send files (`send-files`)

Dart: `SendFilesScreen`, `SendFilesModel`, `SendFilesActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `files` | `List<SendFileItem>` {id, name, sizeLabel, kind: image, video, audio or document} | have | `pendingAttachmentsProvider(id)` → `AttachmentDraft.path/.name/.sizeLabel/.kind` (`conv/application/composer_notifier.dart`) | Empty → "Nothing to send" / "Go back and pick a file." (same in both). Title "Send file" / "Send N files" |
| `SendFileItem.preview` for a photo | `ImageProvider?` | have | `FileImage(AttachmentDraft.path)` (today `Image.file` in `conv/presentation/send_files_screen.dart`) | |
| `SendFileItem.preview` for a video | `ImageProvider?` | derive | `VideoFrameSource.frame(path, maxSide:)` (`app/core/platform/video_frames.dart`) | Today a video shows an icon |
| `showViewOnce` | `bool` | derive | any file is an image or video | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onRemove` | `void Function(String id)` | have | `PendingAttachments.remove` | Interaction: × on a file |
| `onSend` | `Future<bool> Function({required String caption, required bool viewOnce})` | have | `ComposerNotifier.sendFiles` | True → back to the chat. Failures are toasts on the chat. Interaction: Send |
| `onDiscard` | `Future<void> Function()` | have | `PendingAttachments.discard` | Leaving without sending deletes the camera's files |

### Kept inside the screen

- The caption text (Interaction: type Caption), the View once switch (Interaction: tap View once), the busy state.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Photos and videos lose their location, time and camera details before sending; a photo that cannot be cleaned is not sent | `conv/application/composer_notifier.dart` (`MediaSanitizer`) | The prototype's footnote "Location details are removed from photos and videos before they are sent." is true; keep it |
| The caption field grows to 4 lines | `send_files_screen.dart` | Keep today's behaviour |

### New backend work

None.

## Media, links and docs (`shared`)

Dart: `SharedMediaScreen`, `SharedMediaModel`, `SharedMediaActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `title` | `String` | have | `conversationHeaderProvider(id)` → `.title`, else "Media, links and docs" | |
| `initialTab` | `SharedTab` {media, docs, links} | derive | a route parameter (today the page always opens on Media) | The prototype opens on a given tab |
| `filesState` | `LoadState` | have | `sharedFilesProvider(id)` AsyncValue (`conv/application/shared_media.dart`) | Media and Docs tabs |
| `linksState` | `LoadState` | have | `sharedLinksProvider(id)` AsyncValue | Links tab |
| `media` | `List<SharedTileItem>` {thumbnail, isVideo, durationLabel, label} | have | `SharedFiles.media` → `SharedMediaTile` | Newest first; `label` is for screen readers ("Photo, Yesterday") |
| `documents` | `List<SharedDocItem>` {name, detail} | have | `SharedFiles.documents` → `SharedDocument` | "482 KB, PDF, Yesterday" (prototype uses "·"; style) |
| `links` | `List<SharedLinkItem>` {url, host, whenLabel, messageId} | have | `sharedLinksProvider(id)` → `SharedLink` | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenMedia` | `Future<String?> Function(int index)` | have | `sharedOpenProvider(part, messageRowid)`; viewer → push `mediaLocation(id, rowid, index:)` | Returns a toast: "Downloading..." or "This file is no longer on this phone.". Interaction: tap photo or video |
| `onOpenDocument` | `Future<String?> Function(int index)` | have | `sharedOpenProvider` (share sheet when on the phone, download when not) | Prototype: "Opens the share sheet" |
| `onOpenLink` | `void Function(String url)` | have | `launchUrl` (`conv/presentation/shared_media_screen.dart`) | The prototype's link row is not tappable |
| `onShowInChat` | `void Function(String messageId)` | have | push `chatLocation(id, messageId:)` | Behaviour differs: the prototype returns to the chat; the app opens the chat at that message. Keep the app's |

### Kept inside the screen

- The current tab (Interaction: Media / Links / Docs).
- Interaction "Back to the chat (empty state)": the prototype's empty state draws no button; it is the frame's back arrow.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner per tab; "This could not be loaded." | `conv/presentation/shared_media_screen.dart` | Add to the design |
| An empty state per tab: "No documents yet" / "Files you share in this chat show up here."; "No links yet" / "Web links sent in this chat show up here." (the prototype draws only "No media yet") | `shared_media_screen.dart` | Add to the design |

### New backend work

None.

## Chat settings (`chat-settings`)

Dart: `ChatSettingsScreen`, `ChatSettingsModel`, `ChatSettingsActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `loading` | `bool` | have | `conversationSettingsViewProvider(id)` is null (`conv/application/conversation_settings.dart`) | |
| `title` | `String` | have | `ConversationSettingsView.title` | |
| `subtitle` | `String?` | have | `ConversationSettingsView.subtitle` | Same line as the chat header ("online", "N members", …) |
| `avatar` | `HelixAvatarModel` | have | `ConversationSettingsView.avatar` | |
| `isGroup` | `bool` | have | `ConversationSettingsView.isGroup` | Group: "Group info" row, no block row |
| `hasInfoPage` | `bool` | derive | `infoLocationOf(id) != null` | |
| `muted` | `bool` | have | `ConversationSettingsView.muted` | Row says "Muted" or "Off" |
| `muteChoices` | `List<({String id, String label})>` | have | `MuteFor.values` (`app/shared/widgets/mute_choice.dart`) | "8 hours", "1 week", "Always"; "Unmute" added when muted |
| `disappearingLabel` | `String` | have | `ConversationSettingsView.disappearingLabel` | |
| `disappearingSeconds` | `int?` | have | `ConversationSettingsView.disappearingSeconds` | Ticks the current choice |
| `disappearingChoices` | `List<({int? seconds, String label})>` | have | `disappearingChoices` | Off, 5 minutes, 1 hour, 1 day, 1 week, 90 days (same in both) |
| `blocked` | `bool` | have | `ConversationSettingsView.blocked` | "Block <name>" or "Unblock <name>" |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenInfo` | `void Function()` | have | push `infoLocationOf(id)` | Row "Contact info" / "Group info" |
| `onOpenSharedMedia` | `void Function()` | have | push `sharedMediaLocation(id)` | |
| `onMute` | `Future<void> Function(String? muteId)` | have | `ConversationSettingsActions.mute(MuteFor?)`; null unmutes | Interaction: Mute notifications |
| `onSetDisappearing` | `Future<void> Function(int? seconds)` | have | `ConversationSettingsActions.setDisappearing` | Interaction: Disappearing messages |
| `onClear` | `Future<void> Function()` | have | `ConversationSettingsActions.clear` | Confirm inside. Interaction: Clear chat. The prototype then toasts "Chat cleared"; the app says nothing |
| `onBlock` | `Future<void> Function()` | have | `ConversationSettingsActions.block(peer)` | Confirm inside. Copy differs in meaning: prototype "They will not be able to message or call you, and Orbit tells them that you blocked them. You can unblock them here at any time."; app omits "tells them" (out of date since ADR-030). Take the prototype's |
| `onUnblock` | `Future<void> Function()` | have | `ConversationSettingsActions.unblock(peer)` | At once, no confirm |

### Kept inside the screen

- The mute and disappearing sheets, the clear and block dialogs.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Spinner until the chat loads | `conv/presentation/conversation_settings_screen.dart` | Keep today's behaviour |

### New backend work

None.

## Decisions and Phase 1b (2026-10-18)

Review 1 approved every recommendation in `../GAPS.md`. For this contract:

- Enter follows “Enter key sends”: on by default on a window, off on a phone (fixes B7).
- A voice note’s “played” mark after a restart: later (E10).
- A locked recording shows the timer and a still wave; no live waveform.
- “Show in chat” opens the chat at that message (the app’s way).
- The block wording is the prototype’s (ADR-030).

**How the “keep” rows are drawn.** Every row above marked keep (today’s
behaviour, in the new style) uses the state kit (`frame.md`, the `state-kit`
screen):
- a list that is loading: `Kit.skeleton`;
- a page that is opening: `Kit.loading`;
- “could not be loaded”: `Kit.loadFailed`, with Try again;
- a permission: `Kit.permission`;
- a field refusal or lockout: the field’s error and `Kit.fieldLock`;
- any other refusal: an error toast;
- a sentence on the page: `Kit.notice`.

Rows marked drop are not built.

New prototype states drawn in Phase 1b (keys in `screens.json`):

- `group-pending-link`: Group · unconfirmed member who joined by link
- `chat-loading`: Conversation · opening
- `chat-error`: Conversation · could not be opened
- `media-cannot-show`: Media viewer · picture cannot be shown
- `media-video-buffering`: Video player · buffering
- `media-video-ended`: Video player · played to the end
- `shared-docs-empty`: Shared · no documents yet
- `shared-links-empty`: Shared · no links yet
