# conversation

One conversation, direct or group (same screen): header, message timeline,
composer, message actions, media, in-chat search, settings.

```
application/
  timeline_provider.dart    window notifier (latest N / from a key, paging
                            both ways, jumps), `timelineProvider` (StreamProvider
                            over watchLatest/watchFrom + the window's reactions,
                            coalesced to one snapshot per 16 ms)
  timeline_builder.dart     rows -> entries: day separators, unread divider,
                            notices, run grouping, newest first
  message_mapper.dart       MessageRow -> HelixMessage (content kinds, quotes,
                            reactions, mentions)
  media_content.dart        per-message attachments + transfers -> media /
                            audio / document content (watched per row)
  audio_playback.dart       one player, speed 1/1.5/2, played marks, failure
  video_session.dart        the full-screen video player's state (autoDispose
                            per file; stops a playing voice note)
  composer_notifier.dart    reply/edit, drafts, typing (throttled), mentions,
                            camera/gallery picks, cleaning and sending files,
                            voice notes (permission, lock/cancel, interruption,
                            background, 10 minute limit)
  message_actions.dart      menu rules (edit 15 min, delete-for-everyone 2 days,
                            admins), react toggle, forward
  read_tracker.dart         mark read only when foreground + at bottom;
                            starts disappearing timers on display
  send_preview.dart         the send-files page's pictures: a photo scaled
                            down, a video's first frame (`videoFramesProvider`)
  conversation_header / _search / _settings / forward_targets / message_info
  (with the message's bubble) / media_viewer / conversation_calls
presentation/
  conversation_screen.dart  connector: draws orbit_ui's `ChatScreen` from the
                            providers above (timeline window, jumps, media of
                            the rows drawn, player, composer, search, pending
                            members) and maps its actions to the notifiers and
                            routes; follows the app lifecycle. The screen
                            itself (lazy reversed list, paging, jumps, scroll
                            to latest, keeping your place, selection, sheets,
                            hold-to-record) is `orbit_ui`'s.
  forward_screen.dart, message_info_screen.dart, media_viewer_screen.dart,
  send_files_screen.dart, conversation_settings_screen.dart,
  shared_media_screen.dart  connectors for orbit_ui's conversation pages
                            (`ForwardScreen`, `MessageInfoScreen`,
                            `MediaViewerScreen`, `SendFilesScreen`,
                            `ChatSettingsScreen`, `SharedMediaScreen`); the
                            viewer's connector watches the video session of
                            the page on screen, pauses it in the background
                            and opens and ends a view-once message
conversation_routes.dart    /chat/:id and its sub-routes
```

## Seams

- **Calls:** the header buttons go through `callLauncherProvider`
  (`core/calls/call_launcher.dart`), which resolves to `placeCallProvider`; a failure
  is the outcome's sentence in a snackbar.
- **Blocks:** when you blocked them, or they blocked you (`peerBlocksMeProvider`,
  told by the server at once), the header has no call buttons and the composer
  shows `ConversationHeader.composerDisabledReason` ("<Name> has blocked you.
  You can't message or call them.") instead of the text field.
- **Admins-only groups:** when a group lets only admins send, a plain member's composer shows "Only
  admins can send messages to this group." (`groupCanSendProvider`, from `GroupDetails.canSend`) instead of a
  field whose send would fail; the engine refuses the send as well (`ChatsService._routeOf`).
- **Info pages:** the header title and the menu open the contact info (direct chat,
  `PeoplePaths.person`) or the group info (`GroupPaths.info`); see
  `application/conversation_links.dart`. Your own note-to-self chat has no info
  page, and its header (from `conversation_header.dart`) carries no peer, so it
  offers no call buttons, no presence and no block either.
- **Shared media:** `/chat/:id/shared` (`shared_media_screen.dart`, `?tab=docs` or
  `?tab=links` to open on another tab): photos and videos
  in a grid, documents, links; from the menu, the settings and the contact info
  (`ConversationSeams.openSharedMedia`). Backed by the engine's
  `watchSharedAttachments` / `watchMessagesWithLinks`.
- **Platform adapters** (`core/platform/`, each plugin in one file): `AttachmentPicker`
  (`file_picker` for the gallery and files, `image_picker` camera through `CameraCapture`),
  `MediaSanitizer` (EXIF/location/time removed before the engine copies a photo or video; a photo that
  cannot be cleaned is not sent), `VoiceRecorder` (`record`), `AudioPlayerAdapter` (`audioplayers`),
  `VideoPlayers` (`video_player`; share sheet where unsupported), `FileActions` (share sheet),
  `MediaTemp` (the cache folders for captures, recordings and cleaned copies, and their deletion),
  `VideoFrameSource` (`fc_native_video_thumbnail`; the send-files page's video stills). The
  engine's previews come from `FlutterMediaProcessor`.
- **Group management** (members, roles, links) is the groups feature's; the
  settings screen links to its info page.
- **Unconfirmed group members:** above a group conversation the Orbit screen
  draws "Confirm NAME?" (Confirm, and Remove for admins) from
  `shared/pending_members.dart` (as the group info page does) for members the server's
  roster added without an announcement; the timeline shows the engine's `member_unconfirmed` notice
  (`core/chat/message_semantics.dart`). The groups feature owns the logic.

## Polls and events

A poll or an event is made from the attach sheet (Poll, Event): `orbit_ui`'s
`OrbitNewPollPage` and `OrbitNewEventPage` hand a draft to `ConversationActions.sendPoll`
/ `sendEvent`, which send through the gateway (`ChatsService.sendBody`). The bubble
(`message_mapper.dart`, `_poll` and `_event`) is drawn from the votes and RSVPs the engine keeps in
the message payload; a tap calls `vote` / `rsvp` and the bubble redraws from the database.
Polls are single or multiple choice; closing a poll (`closes_at`) is honoured, not offered. Events
have a title, a start, and a place; plus-ones and an end time are not offered.

## Stars and pins

The message menu offers **Star** and **Pin** (not for a deleted, broken or view-once message).
A star is a private bookmark: `ConversationActions.star` -> `ChatsService.setStarred`, nothing is sent,
and the bubble shows a small star. Every starred message of every chat is on **You > Starred
messages** (`StarredScreen`, `starred_messages.dart`; a row opens the chat at the message).
A pin is shared: `ConversationActions.pin` -> `ChatsService.pinMessage` sends a `pin` action
(CONTENT_V2.md §3) and the other side's engine applies it. A chat keeps three; a fourth is refused with
"A chat keeps three pinned messages. Unpin one first." The pinned messages show as a banner under the
conversation's header (`pinned_messages.dart`), one at a time: a tap jumps to it and moves on to the
next. Both survive a backup restore. Favourite *chats* are the chats feature's.

## Not here

Stickers and live-location bubbles (drawn as "needs a newer version"),
proximity/earpiece playback,
video notes recorded in app, report.
