# F10 Personalization Design

Status: completed locally on 2026-06-25.

F10 adds local-first visual personalization, profile metadata, and sticker
organization without introducing AI-dependent generation or unsafe media bypasses.

## Local State

Local storage schema v22 adds:

- `theme_preferences` for global and per-chat light/dark/system choices,
  high-contrast preference, color seed, and encrypted/local wallpaper pointers.
- `profile_about_notes` for temporary encrypted About text with audience and
  expiry.
- `profile_images` for private/encrypted profile image and thumbnail attachment
  references with cache-version invalidation.
- `sticker_packs` and `stickers` for static, animated, and text sticker
  metadata, favorites, recents, search tags, shared pack manifests, and safety
  constraints.

## Stickers

Sticker sending uses `helix.remote.content.sticker.v1` inside the standard
encrypted content envelope. Sticker assets remain attachment objects, so the
existing encrypted attachment pipeline, thumbnail handling, and export warnings
still apply.

Safety rules enforce a 512KB sticker limit and a 3-second animated-sticker
duration limit before metadata is accepted. Emoji-to-sticker suggestions use a
deterministic local map and local sticker tags.

## Profiles And Themes

About notes are encrypted locally and expire by timestamp. Profile image records
carry audience and cache version so clients can invalidate stale thumbnails.
Theme preferences are scoped as `global` or `conversation`; large wallpapers are
kept local or represented as encrypted attachment references.

The service exposes a simple contrast check to prevent unreadable color choices.

## Compatibility

Clients advertise:

- `helix.remote.personalization.v1`
- `helix.remote.content.sticker.v1`
- `helix.remote.local-storage-schema.v22`

Older clients ignore sticker content messages and personalization rows while
continuing to process ordinary encrypted messages.
