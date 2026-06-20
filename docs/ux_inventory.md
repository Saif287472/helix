# Helix UX Inventory — Phase 8

Generated: 2026-06-20. Update whenever routes, screens, dialogs, or primary tasks change.

---

## helix_local

### Routes

| Route | Screen file | Primary task |
|---|---|---|
| `/setup` | `ui/screens/setup/setup_screen.dart` | First-run: set display name + secret sentence |
| `/home` | `ui/screens/home/home_screen.dart` | Discover nearby peers, browse chats, manage requests, open settings |
| `/chat/{threadId}` | `ui/screens/chat/chat_screen.dart` | Send/receive messages, share files, call peer, verify identity |
| `/group/{groupId}` | `ui/screens/home/group_screen.dart` | Group chat, manage members, group announcements |
| `/qr-share` | `ui/screens/qr/qr_share_screen.dart` | Display own QR code for peer to scan |
| `/qr-scan` | `ui/screens/qr/qr_scan_screen.dart` | Scan a peer's QR code to add them |
| `/settings` | `ui/screens/settings/settings_screen.dart` | Profile, security, appearance, notifications, advanced, trusted devices |
| `/diagnostics` | `ui/screens/diagnostics/diagnostics_screen.dart` | Session/network diagnostics, log export |

**Lock screen** (no route): `ui/screens/lock_screen.dart` — biometric gate before home.

### Tabs (within `/home`)

| Tab index | Label | Widget | Primary task |
|---|---|---|---|
| 0 | Home | `_HomeTab` | Peer discovery, session status, discoverability toggle |
| 1 | Requests | `RequestsScreen` | Accept/decline incoming connection requests |
| 2 | Chats | `_ChatsTab` | Browse active chat threads |
| 3 | Settings | `SettingsScreen` | User preferences |

### Dialogs & sheets

| Trigger | Type | Widget / location |
|---|---|---|
| Tap peer → Connect | Bottom sheet | `SecretCodeSearchSheet` |
| Chat → Verify identity | Bottom sheet | `_VerifyIdentitySheet` |
| Chat → Attachments | Bottom sheet | `_ChatComposerActions` |
| Chat → Message long-press | Bottom sheet | `_ChatMessageActions` |
| Chat → Thread ⋮ menu | Bottom sheet | `_ChatThreadActions` |
| Home → QR button (mobile) | Modal bottom sheet | Inline in `_HomeTab._openQrOptions` |
| Home → Trusted devices | Bottom sheet | `TrustedDevicesSheet` |
| Settings → Change secret sentence | Alert dialog | `_showChangeCodeDialog` |
| Settings → Choose theme | Alert dialog | `_showThemeDialog` |
| Settings → Choose accent | Alert dialog | `_showAccentDialog` |
| Settings → Auto-lock timeout | Alert dialog | `_showAutoLockDialog` |
| Settings → Ringtone | Modal bottom sheet | `_showRingtoneSheet` |
| Settings → Security limitations | Alert dialog | `_showSecurityLimitationsDialog` |
| Settings → Reset preferences | Alert dialog | `_confirmResetPreferences` |
| Settings → Reset Helix | Alert dialog | `_resetHelix` |
| Settings → Export outside wipe | Alert dialog | `_confirmExternalExportWarning` |
| Settings → Panic wipe | Alert dialog | `_showPanicWipeDialog` |
| Settings → Rename trusted device | Alert dialog | Inside `TrustedDevicesCard` |
| Incoming call | Overlay banner | `CallOverlay` |

### Async / loading states

| Location | Current pattern | Notes |
|---|---|---|
| Session init | `bool _sessionInitStarted` + `setError()` | `HomeScreen._initSession` |
| Panic wipe execution | `bool _resetting` flag | `SettingsScreen._resetHelix` |
| Secret code save | `bool _savingCode` flag | `SettingsScreen._saveCode` |
| Discovery search | `bool _searching` + 10s timer | `_HomeTab._refresh` |
| Secret code sheet | Internal state | `SecretCodeSearchSheet` |
| Request accept/decline | Internal state per row | `RequestsScreen` |

### Dead ends & hidden actions

- "Export diagnostic log" only visible inside `/diagnostics` — hard to find.
- Panic wipe accessible via three taps in Settings → Advanced → hidden tap sequence.
- Group creation is implicit (public lobby auto-created) — no explicit "Create group" UX.
- Trusted devices count is not visible from any badge or status; buried in Settings.

---

## helix_remote

### Routes / screens

helix_remote uses imperative navigation (`Navigator.push`) with no named-route system.

| State / screen | Class | Primary task |
|---|---|---|
| Loading / boot | `_buildLoadingScreen` | Waiting for initialization |
| Setup (unauthenticated) | `_buildSetupScreen` | Register new device or restore existing account |
| Ready | `ConversationListScreen` | Browse conversations |
| Conversation | `ConversationScreen` | Send/receive messages |
| Groups | `GroupsScreen` | Group conversations |
| Device management | `DeviceManagementScreen` | Linked devices |
| Settings | `SettingsScreen` (remote) | Account preferences |
| Privacy | `PrivacyScreen` | Privacy controls |
| Backup | `BackupScreen` | Export / import backup |
| Error | `_buildErrorScreen` | Recoverable startup failure with retry |
| Reset required | `_buildResetScreen` | Database key missing — must reset |

### Dialogs & sheets

Remote screens use in-page navigation; no dedicated dialog/sheet infrastructure has been inventoried beyond what `ConversationScreen` and `BackupScreen` contain.

### Async / loading states

All screens use `bool _loaded / _loading / _registering` flags + manual `setState`. No shared pattern.

---

## Duplication & consolidation opportunities

| Pattern | Current state | Target (Phase 8) |
|---|---|---|
| Loading spinner | Inline `CircularProgressIndicator` everywhere | `HelixAsyncPanel(state: .loading)` |
| Error display | Inline `Text(error, color: red)` | `HelixAsyncPanel(state: .error(...))` |
| Confirm dialog | Separate `AlertDialog` per call site | `HelixConfirmDialog.show()` |
| Destructive confirm | Ad-hoc `AlertDialog` with inconsistent text | `HelixDestructiveDialog.show()` |
| Breakpoint | Hardcoded `width > 600` | `HelixTokens.breakpointWide` |
| SnackBar feedback | Inline `ScaffoldMessenger.of(context).showSnackBar(...)` | `HelixFeedback.error/success/retry()` |
| Privacy context | Missing | `HelixPrivacyNote` widget in relevant settings sections |
