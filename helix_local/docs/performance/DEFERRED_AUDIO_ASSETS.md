# Deferred Local Audio Assets

Phase 10 reduced the bundled Local asset directory by moving oversized optional
ringtone tracks out of `apps/helix_local/assets/sounds/`.

Deferred files are staged under `docs/performance/deferred_assets/sounds/` for
future product review. They are not available in `kAvailableRingtoneAssets` and
must not be lazy-downloaded unless privacy/network policy explicitly approves an
optional download flow.

Bundled tones now keep the default ringtone and compact alternatives only.
