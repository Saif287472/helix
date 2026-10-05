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
                            admins), react toggle, forward, selection
  read_tracker.dart         mark read only when foreground + at bottom;
                            starts disappearing timers on display
  conversation_header / _search / _settings / forward_targets / message_info /
  media_viewer / conversation_calls
presentation/
  conversation_screen.dart  implements `ConversationUi` (taps -> engine/nav)
  timeline_view.dart        reverse list, paging, jump-to-message, scroll to
                            bottom, keeps position when messages arrive below
  timeline_row.dart         one row; widgets are reused while the entry is equal
  composer_bar.dart, emoji_panel.dart, conversation_app_bar.dart,
  in_chat_search_view.dart, forward_screen.dart, message_info_screen.dart,
  media_viewer_screen.dart, video_player_view.dart, send_files_screen.dart,
  conversation_settings_screen.dart
conversation_routes.dart    /chat/:id and its sub-routes
```

## Seams

- **Calls:** the header buttons go through `callLauncherProvider`
  (`core/calls/call_launcher.dart`), which resolves to `placeCallProvider`; a failure
  is the outcome's sentence in a snackbar.
- **Info pages:** the header title and the menu open the contact info (direct chat,
  `PeoplePaths.person`) or the group info (`GroupPaths.info`); see
  `application/conversation_links.dart`.
- **Shared media:** `/chat/:id/shared` (`shared_media_screen.dart`): photos and videos
  in a grid, documents, links; from the menu, the settings and the contact info
  (`ConversationSeams.openSharedMedia`). Backed by the engine's
  `watchSharedAttachments` / `watchMessagesWithLinks`.
- **Platform adapters** (`core/platform/`, each plugin in one file): `AttachmentPicker`
  (`file_picker` for the gallery and files, `image_picker` camera through `CameraCapture`),
  `MediaSanitizer` (EXIF/location/time removed before the engine copies a photo or video; a photo that
  cannot be cleaned is not sent), `VoiceRecorder` (`record`), `AudioPlayerAdapter` (`audioplayers`),
  `VideoPlayers` (`video_player`; share sheet where unsupported), `FileActions` (share sheet),
  `MediaTemp` (the cache folders for captures, recordings and cleaned copies, and their deletion). The
  engine's previews come from `FlutterMediaProcessor`.
- **Group management** (members, roles, links) is the groups feature's; the
  settings screen links to its info page.
- **Unconfirmed group members:** above a group conversation sits
  `shared/widgets/pending_members_prompt.dart` ("Confirm NAME?" with Confirm,
  and Remove for admins) for members the server's roster added without an
  announcement; the timeline shows the engine's `member_unconfirmed` notice
  (`core/chat/message_semantics.dart`). The groups feature owns the logic.

## Not here

Polls, events, stickers and live-location bubbles (polls and events draw as
text, the others as "needs a newer version"), proximity/earpiece playback,
video notes recorded in app, starred messages (the engine keeps none), report.
