# Helix Remote component gallery

`helix_remote_ui` provides the shared visual language for the Remote client.

- `HelixEmptyState` and `HelixErrorState` for predictable asynchronous outcomes.
- `HelixSkeleton` and `HelixAsyncPanel` for content-aware loading.
- `HelixStatusBadge` for compact state labels.
- `showHelixDestructiveDialog` for dangerous, confirmed actions.

The app is light-only: themes are supplied by `HelixThemes.light()` and `HelixThemes.highContrastLight()` (there is no dark theme, and the shell pins `ThemeMode.light` in `app/lib/app/helix_remote_app_shell.dart`). UI text is plain English string literals; there is no localization layer. Use `HelixColorTokens`, `HelixSpace`, `HelixInsets`, and `HelixRadius` instead of new ad-hoc values.

Use filled buttons for the primary action, tonal buttons for an important secondary action, outlined buttons for a visible alternative, and text buttons for low-emphasis actions. Destructive actions must use `showHelixDestructiveDialog`.

`HelixBreakpoints` defines the compact, tablet, and desktop layout thresholds. Conversation surfaces use a list on compact screens and a master-detail layout from tablet width upward. Page transitions are configured by `HelixThemes`, and conversation avatars use a shared Hero tag when moving from the list to the detail surface.
