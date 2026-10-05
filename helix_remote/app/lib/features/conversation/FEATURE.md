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
  audio_playback.dart       one player, speed 1/1.5/2, played marks
  composer_notifier.dart    reply/edit, drafts, typing (throttled), mentions,
                            files, voice notes
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
  media_viewer_screen.dart, send_files_screen.dart,
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
- **Platform adapters** (`core/platform/`): `AttachmentPicker` (file_picker;
  no camera plugin in the build), `VoiceRecorder`, `AudioPlayerAdapter`
  (both `Unavailable*` until a plugin is chosen), `FileActions` (share sheet).
- **Group management** (members, roles, links) is the groups feature's; the
  settings screen links to its info page.

## Not here

Polls, events, stickers and live-location bubbles (polls and events draw as
text, the others as "needs a newer version"), a video player (videos open
through the share sheet), starred messages (the engine keeps none), report.
