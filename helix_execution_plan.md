# Helix Remote & Helix Admin — Phase-by-Phase Execution Plan

> **AGENT INSTRUCTIONS:** You are tasked with executing this remediation plan phase by phase across `helix_remote` (`app`, `packages`, `backend`) and `helix_remote/admin` (`helix-admin`). Read Section 0 before modifying any file.

---

## SECTION 0 — MANDATORY AGENT RULES & PRODUCT OVERRIDES (READ FIRST)

Before touching any code, you **MUST** obey these four product overrides. They supersede any conflicting recommendations from the original audit report:

### 1. STOP-AND-ASK Protocol for Redesigned UI / Stray Screens
- Both **`helix-remote` (especially the Welcome / Onboarding screens)** and **`helix-admin`** recently underwent a complete UI/UX redesign.
- Because of this redesign, several unreferenced screens, widgets, or tab routes in the codebase are **leftover stray files from the old design**, while others are newly built features awaiting wiring.
- **STRICT RULE:** Do **NOT** guess or assume product direction when encountering stray screens, unreferenced widgets, or ambiguous navigation layouts. Whenever a task below is marked with **`[STOP & ASK USER]`**—or whenever you are unsure if a screen belongs to the old design vs. the new design—**pause and ask the user before writing or deleting UI code.**

### 2. Federation Server & Related Topics Are DEFERRED
- Federation ("Worldwide Mode", S2S directory, federated group invites/history) is intentionally deferred for 1–2 years.
- **DO NOT EXECUTE:**
  - **Finding 2 (F2):** Do not spend time wiring federation `TextEditingController`s or fixing Worldwide Mode in `ops_tab.dart` / `config_tab.dart` (unless the user asks you to simply hide the Federation UI card).
  - **Finding 7 (F7 — partial):** Ignore the `federation_directory_v2` feature flag. Only wire `crash_reporting_upload` and `minimal_analytics`.
  - **Finding 12 (F12):** Do not build `GroupFederationRepository` history packaging for `group_history_packages`. Leave the migration untouched so schema version numbers do not break.
  - **Finding 20 (F20 — partial):** Ignore `config['federation']['address']`.
  - **Part 4 (`federated_group_invites`):** Leave dormant.

### 3. NO Dark Mode — Strictly Light & Colorful UI Only
- Dark mode is intentionally deferred. The entire product (`helix-remote` and `helix-admin`) must be **light, vibrant, and colorful**. No ugly black or dark-mode screens may remain.
- **OVERRIDES:**
  - **Finding 15 (F15):** Do **NOT** implement `AppTheme.dark`. Instead, lock `themeMode: ThemeMode.light` in `admin/lib/main.dart`, remove dark color branches (such as `Color(0xFF0B0B12)` in `app_theme.dart:132`), and replace any dark/black surfaces across both apps with clean, light, colorful surfaces matching the new design system.
  - **Finding 14 & 35 (Dark Mode / Appearance toggles):** Remove or hide any "Dark Mode" toggles in `helix-admin` (`settings_tab.dart`) and `helix-remote` (`settings/actions.dart`).

### 4. Bengali (`bn`) Localization Is DEFERRED
- **OVERRIDE FOR FINDING 36 (F36):** Do **NOT** translate the ~250 keys in `app/lib/l10n/app_bn.arb`.
- Instead, remove `Locale('bn')` from `app/lib/l10n/helix_localizations.dart:96-98` and any in-app language selector so users are not offered an untranslated language option. Leave `app_bn.arb` dormant for future work.

### Execution Discipline
1. Execute **one phase at a time**.
2. At the end of each phase, run `dart analyze` / `flutter analyze` and relevant unit tests for the modified packages.
3. Report completed changes to the user and resolve any **`[STOP & ASK USER]`** checkpoints before starting the next phase.

---

## PHASE 1 — Truthfulness, Data Integrity & Quick Backend Fixes
**Objective:** Stop `backend` and `helix-admin` from fabricating data, fix the broken user device list/count, fix crash log string interpolation, and make admin mutations report real HTTP outcomes.

### Step 1.1: Fix User Connected Device Fabrication & Missing `device_count` (Fixes F9, F20)
1. **`backend/lib/src/database/accounts_devices_repository.dart:418-441`**
   - In `getDevices(String accountId)`, **delete** the `if (list.isEmpty) { ... registerDevice(...) ... }` block that fabricates `'Primary Registered Device'` on read.
   - Return `const []` when an account has no registered devices.
2. **`backend/lib/src/database/server_config_repository.dart:64-99`**
   - In `getAllUsersDetailedPaginated`, include an accurate `device_count` field computed via a `LEFT JOIN` or subquery on `devices WHERE account_id = accounts.account_id AND status = 'ACTIVE'`.
3. **`admin/lib/screens/users_tab.dart:627` & `:928-931`**
   - Update the device count expression at `:627` to read `user['device_count'] ?? devices.length` (defaulting to `0`, never `1`).
   - When `devices.isEmpty`, render a clean, light-themed `"No connected devices"` empty state in the user detail view with no revoke button.

### Step 1.2: Fix Crash-Report Truncation Bug & Support Bundle WebSocket Metric (Fixes F10, F13)
1. **`backend/lib/src/modules/operability.dart:238-243` (F10)**
   - In `_truncate(String value)`, remove the erroneous backslash before `${flattened...}` on line 242 so it interpolates properly:
     ```dart
     return flattened.length <= _crashValueLimit
         ? flattened
         : '${flattened.substring(0, _crashValueLimit)}…';
     ```
2. **`backend/lib/src/modules/operability.dart:357-362` & `:448-456` (F13)**
   - Extract the WebSocket readiness calculation from `_ready` (`(wsRelay.stats()['rejected_reconnects'] as int? ?? 0) < websocketRejectLimit`) into a private helper `_isWebsocketReady()`.
   - Call `_isWebsocketReady()` in both `_ready` (`:357`) and `_supportDiagnostic` (`:450`), replacing the hardcoded `'websocket_ready': true`.

### Step 1.3: Purge All Fabricated Mock Data in `helix-admin` (Fixes F16, F17, F18, F20, F21, F26, F35)
1. **Dashboard Tab (`admin/lib/screens/dashboard_tab.dart` & `admin/lib/main.dart`) — F16, F20, F35**
   - At `dashboard_tab.dart:272-291`, wire the three Service Integration Health cards to real server metrics:
     - **FCM Push:** Read `metrics['push_provider']` (`configured` and `available`). Show green only when `available == true`, amber when `configured && !available`, and neutral/red when unconfigured.
     - **SMS Gateway:** Read `sms_provider_configured` (expose it in `/ops/metrics` if currently only in `/ops/support-diagnostic`). **Delete** the fabricated `'API Balance: $48.50 • 2,420 Credits'` string.
     - **TURN Relay:** Read `metrics['turn']` (`configured`, `url_count`, `live_reachability`) and display `url_count` in the subtitle.
   - At `dashboard_tab.dart:53`, remove the hardcoded `'Android, iOS, Windows'` subtitle.
   - At `dashboard_tab.dart:57-63`, remove the hardcoded `'↑ 12% this week'` subtitle.
   - At `dashboard_tab.dart:8, 159` and `main.dart:118, 475, 516`, remove the fallback latency literals (`23` and `18`). Render `'Latency: —'` when latency has not been measured.
   - **[STOP & ASK USER] (`dashboard_tab.dart:80` — `quarantine_events`):** The dashboard reads `tblCounts['quarantine_events']`, which does not exist in the backend. Ask the user whether to remove the "Quarantined Security Events" stat card or bind it to another metric (e.g., open abuse reports or rate-limiter rejections).
2. **Ops → Audit Sub-Tab (`admin/lib/screens/ops_tab.dart`) — F17, F35**
   - Delete `_defaultAuditEvents` (`:51-85`) and the `if (_auditEvents.isEmpty) { _auditEvents = _defaultAuditEvents; }` assignment (`:119-121`).
   - In the `catch` block at `:116`, capture the error into state and render an error banner instead of swallowing it.
   - When `_auditEvents.isEmpty` and there is no error, render a genuine `"No audit events recorded yet"` empty state.
   - At `:131`, remove `?? DateTime.now().millisecondsSinceEpoch`; if `timestamp` is null, display `'—'`.
3. **Logs Tab (`admin/lib/screens/logs_tab.dart`) — F18**
   - Delete `_sampleLogs` (`:78-84`).
   - Change `:94-96` to `baseLines = const <String>[];` so empty logs naturally reach `_buildEmptyState` (`:239`) and display the server's `ServerLogs.message`, `source`, and `filePath`.
4. **Config Tab & Main Shell (`admin/lib/screens/config_tab.dart`, `admin/lib/main.dart`, `admin/lib/widgets/server_name_card.dart`) — F20, F26, F35**
   - In `config_tab.dart:92-112`, remove the fake fallbacks `'Private Server #9608'`, `'srv_alpha_90b1'`, and `'pub_9b14c381a4b92c8e'`. When `server_id` or `server_public_key` is `'unknown'` or null, display `'Not available'` and disable the copy-to-clipboard buttons (`:102`, `:107`).
   - Remove the hardcoded `'https://helix.agiletechbd.com'` fallback at `config_tab.dart:88` and clear `_defaultServerUrl` at `main.dart:72, 108` so the login URL field starts empty.
   - Remove the dead `_config?['name']` fallback at `main.dart:744` (use `_config?['server_name']`) and replace the `'Careless'` fallback strings at `main.dart:744` and `server_name_card.dart:49, 59` with `'Helix Server'`.
5. **Invites Tab (`admin/lib/screens/invites_tab.dart`) — F21**
   - At `:371-374`, add `final isExpired = status == 'EXPIRED';`.
   - Read `invite['expires_at']` (already sent by `operability.dart:1222`) and compute the actual remaining time or expired status instead of the hardcoded `'Expires in 6 days'` at `:429-434`.

### Step 1.4: Fix Admin Mutation Status Checks, Premature Toasts & Live Log Stream (Fixes F23, F24, F25, F27)
1. **Premature Toasts in Users Tab (`admin/lib/screens/users_tab.dart:91-105, 124-134`) — F23**
   - Move the `'Account suspended successfully'` and `'Account restored successfully'` `SnackBar` calls inside the `try` block **after** `await widget.client.suspendUser(accountId)` / `unsuspendUser(accountId)`.
   - Guard both actions with `_busyAccountId = accountId` (cleared in `finally`) to prevent double taps.
2. **Unchecked Report Resolution & Demo Fallback (`admin/lib/admin_client.dart:470-483` & `admin/lib/screens/reports_tab.dart`) — F1, F24, F27**
   - In `admin_client.dart:470-483`, check `if (response.statusCode != 200)` in both `resolveReport` and `dismissReport` and throw `AdminRequestException`, matching the rest of `AdminClient`.
   - In `reports_tab.dart`, delete `_demoReports` (`:21-49`).
   - In `reports_tab.dart:111-125` and `:141-154`, move the local status update and success `SnackBar` into the `try` block after the `await`. In the `catch` block, set `_error = e.toString()` and show an error `SnackBar` so failed requests are never masked as successes.
   - Also set `_error` when `getReports` fails in `_loadReports` (`:96`) so the error card at `:224-234` renders, and wire `offset` pagination into `getReports(limit: 50, offset: _offset)`.
3. **Live Log Stream Lifecycle (`admin/lib/admin_client.dart:503-517`, `admin/lib/main.dart:315-351`, `admin/lib/screens/logs_tab.dart:160-224`) — F25**
   - Update `AdminClient.streamLogs()` so the caller can close the underlying `WebSocketChannel.sink` when pausing or disposing.
   - Add an `onDone:` handler to `_logStreamSub` in `main.dart:315-332` that updates streaming state and starts the fallback poll timer if auto-refresh is still desired.
   - Prevent the 50-line duplicate burst on connect (either skip `_refreshLogs()` immediately before opening the stream or deduplicate incoming tail lines).
   - Add a manual **Refresh** button in `logs_tab.dart:160-224` wired to `widget.onRefresh`.

**Phase 1 Verification:**
- Run `dart test` in `backend` (add a unit test for `_truncate` with a 600-char string and a test confirming `getDevices` returns `[]` for a new account without inserting a fake row).
- Run `flutter analyze` in `admin`.

---

## PHASE 2 — Core Cross-Repo Pipelines (`helix-remote` ↔ `backend` ↔ `helix-admin`)
**Objective:** Connect all broken client-to-server pipelines where the backend endpoints/events already exist but the app drops or fails to send them.

### Step 2.1: Register All 11 Missing Outbox Operations (Fixes F3)
1. **`app/lib/app/remote_sync_gateway.dart:186-322`**
   - Add the 11 missing operation entries to `RemoteOutboundOperation.values` so `RemoteOutboundOperationRegistry.require(type)` no longer throws `StateError`:
     - `group_set_add_policy` → `POST /api/v1/groups/set-add-policy`
     - `group_create_join_link` → `POST /api/v1/groups/create-join-link`
     - `group_revoke_join_link` → `POST /api/v1/groups/revoke-join-link`
     - `group_approve_join_request` → `POST /api/v1/groups/approve-join-request`
     - `group_transfer_ownership` → `POST /api/v1/groups/transfer-ownership`
     - `group_block_member` → `POST /api/v1/groups/block-member`
     - `group_join_via_link` → `POST /api/v1/groups/join-via-link`
     - `group_admin_delete_message` → `POST /api/v1/groups/admin-delete-message`
     - `EVENT_RSVP` → match backend messaging/event RSVP route
     - `LIVE_LOCATION_UPDATE` → match backend live location route
     - `POLL_VOTE` → match backend poll vote route
   - Verify the exact JSON keys expected by `backend/lib/src/modules/groups.dart:132-142` and `packages/helix_remote_groups/lib/src/group_service.dart` so the request bodies match 1:1.
2. **Add Regression Test:**
   - Write a unit test in `app/test/` asserting that every operation type string passed to `outbox.enqueue(...)` across `group_service.dart` and `remote_messaging_service/` has a registered entry in `RemoteOutboundOperation.valuesByType`.

### Step 2.2: Wire Inbound Device Lifecycle Events, Group Join Requests & Mention Badges (Fixes F5, F6, F32)
1. **Device Lifecycle Events (`packages/helix_remote_sync/lib/src/sync_engine.dart:501-556, 575-623`) — F5, F32**
   - Add inbound event parsing and dispatch cases for:
     - `pending_device_link`
     - `device_linked`
     - `device_revoked`
     - `DEVICE_REVOKED`
   - Update `_changeFor` (`sync_engine.dart:501-556`) to emit `RemoteSyncChangeArea.devices` for these events so listeners in `device_management_screen.dart:36` and `conversation_list_screen.dart:83` fire.
   - When `device_revoked` / `DEVICE_REVOKED` targets the current local device, trigger the local credential/session purge hook and route the user back to onboarding.
   - In `app/lib/screens/device_management_screen.dart`, display incoming `pending_device_link` requests so the user can approve/pair a new device without manually typing a raw Link ID.
2. **Group Join Requests (`sync_engine.dart:575-623` & `group_service.dart:465`) — F6**
   - Add a `group_join_requested` case in `sync_engine.dart:575-623` that invokes `RemoteGroupService.recordJoinRequest(...)` and emits `RemoteSyncChangeArea.groups`.
   - Verify that `groups_screen.dart:127-161` ("Join Requests" section) now renders pending requests and can approve them via `group_approve_join_request` (wired in Step 2.1).
3. **Group Mention Badge (`packages/helix_remote_sync` & `group_service.dart:576, 597`) — F32**
   - Call `RemoteGroupService.indexMention` during group message ingestion when a decrypted message mentions the local account, and call `markMentionRead` when the user opens/reads the group conversation, making `unreadMentionCount` in `groups_screen.dart:91-102` live.

### Step 2.3: Wire the App-to-Admin Abuse / Safety Reporting Pipeline (Fixes F1)
1. **`app/lib/app/remote_endpoints.dart` & `app/lib/app/remote_rest_client.dart`**
   - Add the `POST /api/v1/contacts/reports/action` endpoint and a `submitReport({required String subjectAccountId, required String reason, String? details, String? action})` method on `HelixRemoteRestClient` matching the exact schema read by `_safetyActionHandler` in `backend/lib/src/modules/contacts.dart:660-670`.
2. **`app/lib/screens/conversation/app_bars.dart:287-294`**
   - Replace the `'report'` fall-through to `_showPlaceholder` with a dedicated `case 'report':` handler.
   - Present a clean, light-themed dialog allowing the user to select a report reason, enter optional details, and submit via `submitReport(...)`, showing a confirmation or error `SnackBar` after the call completes.

### Step 2.4: Wire Telemetry Consent & Non-Federation Feature Flags (Fixes F7, F11)
1. **Backend (`backend/lib/src/modules/operability.dart:187`) — F7**
   - In `_reportCrash`, check `featureFlags.isEnabled('crash_reporting_upload')`. If disabled, increment `_crashReportsRejected` and return early.
   - *(Note: Skip `federation_directory_v2` per Section 0, Rule 2).*
2. **App (`app/lib/screens/settings/` & `app/lib/services/telemetry_reporter.dart`) — F11**
   - Add a "Privacy & Telemetry" section in Settings with toggles for **Crash Reporting** and **Minimal Analytics**.
   - Wire the toggles to `await const TelemetryConsentStore().write(consent)` and `TelemetryReporter.instance.configure(consent: consent)`.
3. **Admin (`admin/lib/admin_client.dart`, `admin/lib/screens/config_tab.dart`, `admin/lib/screens/dashboard_tab.dart`) — F7, F11**
   - Add `getFeatureFlags()` and `setFeatureFlag(String name, bool enabled)` to `AdminClient`.
   - Render switches for `crash_reporting_upload` and `minimal_analytics` in `ConfigTab` (hide `federation_directory_v2`).
   - Display `metrics['telemetry']` (`crash_reports_accepted`, `crash_reports_rejected`, `last_crash_report_at`) on the Admin Dashboard.

**Phase 2 Verification:**
- Run `flutter test` in `packages/helix_remote_sync`, `packages/helix_remote_groups`, and `app`.
- Verify all 11 outbox operations pass the new registry completeness test.

---

## PHASE 3 — `helix-admin` Controls, Light Theme Enforcement & Navigation Cleanup
**Objective:** Enforce the light/colorful theme across `helix-admin`, resolve stray tabs from the admin redesign, and wire the stubbed Config/Ops controls to real backend operations.

### Step 3.1: Enforce Light & Colorful Theme in `helix-admin` (Rule 3 — Overrides F15)
1. **`admin/lib/main.dart` & `admin/lib/theme/app_theme.dart`**
   - Set `themeMode: ThemeMode.light` unconditionally in `admin/lib/main.dart`.
   - Remove `_isDarkMode` state and `onDarkModeChanged` callbacks from `main.dart` and `settings_tab.dart`.
   - In `admin/lib/theme/app_theme.dart:132`, remove the dark branch (`Color(0xFF0B0B12)`) in `AppColorsX.sunkenSurface` and ensure all surfaces use light, colorful palette tokens.

### Step 3.2: `[STOP & ASK USER]` — Redesigned Admin Navigation & Stray Tabs (Fixes F14)
- **Context:** `admin/lib/main.dart:687-693` and `:753-759` use the redesigned 4-tab layout (`dashboard`, `users`, `invites`, `ops`), leaving `BackupTab`, `SettingsTab`, `GuideWizard`, and several `_getTabWidget()` cases (`'config'`, `'logs'`, `'reports'`, `'backup'`, `'guide'`, `'settings'`) unreachable.
- **Action Required Before Coding:** Pause and ask the user:
  1. *Should `BackupTab` and `GuideWizard` ("Self-Hosting Guide") be merged into the `Ops -> Config` sub-tab, exposed via header action buttons, or deleted as leftover screens from the old admin design?*
  2. *Should `SettingsTab` and the unreachable top-level switch cases in `_getTabWidget()` (`'config'`, `'logs'`, `'reports'`, `'backup'`, `'guide'`, `'settings'`) be deleted now that `Config`, `Logs`, and `Reports` live inside `OpsTab`?*

### Step 3.3: Wire `ConfigTab` Stub Buttons, Maintenance Mode, App Lock & Support Diagnostic (Fixes F13, F19, F22)
1. **App Lock Switch Wiring (`admin/lib/screens/ops_tab.dart:213-230` & `admin/lib/screens/config_tab.dart:18-19, 255-262`) — F22**
   - Change `this.appLockEnabled = false` default in `ConfigTab` (`config_tab.dart:18`) and initialize `_appLockEnabled = widget.appLockEnabled` in `initState` / `didUpdateWidget`.
   - Pass `appLockEnabled` and `onAppLockChanged` from `main.dart` through `OpsTab` into the reachable `ConfigTab` instance at `ops_tab.dart:213-230`.
2. **Operational Controls (`backend/lib/src/modules/operability.dart`, `admin/lib/admin_client.dart`, `admin/lib/screens/config_tab.dart`) — F13, F19**
   - **Maintenance Mode (`config_tab.dart:463-468`):**
     - Backend: Add `POST /api/v1/ops/maintenance` (`{enabled: bool}`) persisting `server_configuration.maintenance_mode`, and enforce a 503 middleware guard for non-admin/non-health routes when enabled. Include `maintenance_mode` in `GET /ops/config`.
     - Admin: Add `AdminClient.setMaintenanceMode(bool enabled)` and wire the switch in `ConfigTab`, updating state only after the request succeeds.
   - **Change Admin PIN/Password (`config_tab.dart:302-311`):**
     - Backend: Add `POST /api/v1/ops/admin-pin` (`{current_password, new_password}`) updating the stored admin password hash/salt.
     - Admin: Open a light-themed dialog prompting for current and new PIN/password, call `AdminClient.changeAdminPin(...)`, and show a real success/error `SnackBar`.
   - **Backup & Restore DB (`config_tab.dart:413-422`):**
     - Wire a "Trigger Backup" action calling the existing `AdminClient.triggerBackup()` (`POST /ops/backup`).
     - For **Restore DB**, either wire a real `POST /ops/backup/restore` endpoint accepting a valid snapshot path or ask the user if Restore DB should be hidden in the web/desktop admin console.
   - **Purge Data (`config_tab.dart:508-517`):**
     - Backend: Add `POST /api/v1/ops/purge` that deletes expired `attachment_references`, old `DLQ` outbox items, and expired tokens.
     - Admin: Add `AdminClient.purgeData()` and await it before showing the success `SnackBar`.
   - **Support Diagnostic (`operability.dart:248` / F13):**
     - Add `AdminClient.getSupportDiagnostic()` hitting `GET /api/v1/ops/support-diagnostic` and add a "Copy Support Bundle" button in `OpsTab` / `ConfigTab`.

### Step 3.4: Admin Pairing Codes & Minor Orphaned Client Cleanup (Fixes F8, F27)
1. **`[STOP & ASK USER]` — Admin Pairing Codes (F8):**
   - Ask the user whether they want to expose a "Pair with Code" flow on the redesigned `admin/lib/screens/login_screen.dart` (wiring `admin_pairing_codes` via `POST /api/v1/ops/admin-pairing-codes` and `POST /api/v1/admin/pair`), or keep the current password login flow and clean up `admin_pairing_repository.dart`.
2. **Minor `AdminClient` & UI Polish (F27):**
   - Wire the `accountId` filter parameter in `Ops -> Audit` to `widget.client.getAuditLogs(accountId: ...)` (`admin_client.dart:487`).
   - Surface any error from `_checkSetupStatus` (`main.dart:150`) instead of silently ignoring it.
   - Remove unused dead methods/fields in `AdminClient` and `AdminPreferences` (`introShown`, `ServerNameCard.serverHost`) once confirmed unused.

**Phase 3 Verification:**
- Run `dart analyze` and `dart test` in `backend`.
- Run `flutter analyze` in `admin`.

---

## PHASE 4 — `helix-remote` App Completeness, Welcome Screen Safety & Light UI
**Objective:** Complete unfinished client features in `helix-remote` while protecting the redesigned Welcome/Onboarding screens and enforcing the light-only theme and deferred Bengali localization rules.

### Step 4.1: Enforce Light & Colorful UI + Defer Bengali Localization in `helix-remote` (Rules 3 & 4 — Overrides F35, F36)
1. **Light & Colorful UI Only (Rule 3):**
   - Audit `app/lib` theme configuration and screens to ensure `ThemeMode.light` is enforced and no dark mode or black screen surfaces remain.
   - In `app/lib/screens/settings/actions.dart:128-135`, remove the stubbed `Appearance: 'System'` dark-mode row (or, if desired by the user, wire it strictly to light/colorful accent themes via `saveThemePreference`—never dark mode).
2. **Defer Bengali Localization (Rule 4 — F36):**
   - Remove `Locale('bn')` from `app/lib/l10n/helix_localizations.dart:96-98` and any language picker UI so Bengali is not selectable until translations are scheduled.

### Step 4.2: `[STOP & ASK USER]` — Redesigned Welcome / Onboarding Screens (Fixes F33, F35)
1. **Remove Hardcoded Production OTP & Invite Fallbacks (`app/lib/screens/setup/state/onboarding_notifier.dart` & `app/lib/app/bootstrap.dart`) — F33**
   - In `onboarding_notifier.dart:651-653` and `bootstrap.dart:165-167`, remove the `'123456'` fallback so submitting an empty OTP fails validation with a clear error message.
   - In `onboarding_notifier.dart:645-647`, remove the `'INV-GLOBAL'` fallback so an empty invite code fails validation when an invite is required.
   - *(If a developer bypass is needed for local testing without SMS, gate it strictly behind `kDebugMode` and set `otpIsPlaceholder = true` so the notice banner is truthful).*
2. **Country Code Picker (`app/lib/widgets/country_code_picker.dart`) — F35**
   - **`[STOP & ASK USER]`:** Remember that the `helix-remote` welcome screens (`global_phone_step.dart` and `personal_verify_step.dart`) were recently redesigned. Before replacing the inline country dropdowns (`global_phone_step.dart:24-34`, `personal_verify_step.dart:56-63`) with `country_code_picker.dart`, **ask the user** whether they want the full ~100-country list from `country_code_picker.dart` integrated into the new welcome screen UI or if the current inline design was intentional.

### Step 4.3: Wire Group Moderation, Contact Requests & Pending Calls (Fixes F31, F35)
1. **Group Moderation (`app/lib/screens/groups_screen.dart` & `group_service.dart`)**
   - Wire the existing `RemoteGroupService` methods into `groups_screen.dart`:
     - `updateGroupInfo` (`:231`)
     - `changeMemberRole` (`:265`)
     - `removeMember` (`:304`)
     - `adminDeleteMessage` (`:534`) and `isMessageModerated` (`:552`)
2. **Contact Requests (`app/lib/screens/contacts/`)**
   - Wire `POST /contacts/requests/reject`, `POST /contacts/requests/cancel`, and `DELETE /contacts/remove` (`contacts.dart:47-50`) to reject/cancel/remove actions in the Contacts UI.
3. **Pending Calls (`app/lib/app/composition_root/runtime.dart:47-85` & `remote_rest_client.dart:674-682`)**
   - Route incoming pending calls through `acceptPendingCall` and `declinePendingCall` so declining a call immediately notifies the server instead of waiting for TTL expiration.
4. **Call History Fabricated Size (`app/lib/screens/calls_tab_screen.dart:679-686`) — F35**
   - Remove the synthetic `seconds * (isVideo ? 220*1024 : 32*1024)` byte calculation and display call duration only (unless real byte metrics are present).
5. **Endpoint Constants Cleanup (`app/lib/app/remote_endpoints.dart`)**
   - Refactor `HelixRemoteRestClient` to use `RemoteApiEndpoints` getters consistently, or remove unused duplicate getters.

### Step 4.4: Privacy Controls Enforcement — View-Once, App Lock & Chat Lock (Fixes F34)
1. **View-Once Media Consumption (`app/lib/screens/conversation/` & `history_receipts.dart:432`)**
   - When a user opens a view-once message/attachment, invoke `consumeViewOnceMessage` (`history_receipts.dart:432`) and `db.markViewOnceOpened` (`privacy_repository.dart:327`) so it cannot be reopened indefinitely.
2. **App Lock & Chat Lock (`app/lib/screens/settings/privacy_screen.dart`, `helix_remote_app_shell.dart`, `ConversationScreen`)**
   - Wire `RemoteAppLockSettings` to a real light-themed PIN / lock screen gate in `helix_remote_app_shell.dart` (similar to `admin/lib/screens/lock_screen.dart`), and allow the user to set a PIN when toggling App Lock on in `privacy_screen.dart:159-171`.
   - When `setConversationLocked` is enabled for a chat (`conversation_list_view_model.dart:36-40`), either pass `hidden: true` so it moves to the Locked Chats view (`privacy_screen.dart:410-434`) or gate entry to `ConversationScreen` behind the lock prompt.

### Step 4.5: `[STOP & ASK USER]` — Group Calls, Epoch Encryption & Rich Content Screens (Fixes F4, F28, F29, F30)
1. **Inbound Group Call & Epoch Key Wiring (Backend-to-Service plumbing — safe to wire now, F30):**
   - In `packages/helix_remote_sync/lib/src/sync_engine.dart:575-623`, add handlers for the 8 dropped backend events:
     - `participant_joined`, `room_ended`, `participant_left`, `participant_kicked`, `screen_sharing_changed`, `scheduled_call_invite`, `scheduled_call_cancelled` → route to `RemoteGroupCallService.processRoomEvent` (`remote_group_call_service.dart:192`).
     - `group_epoch_key` → route to `RemoteGroupService.recordEpochKeyDelivery` (`group_service.dart:620`).
   - In `app/lib/app/composition_root/lifecycle.dart:223-241` and `message_sending.dart:38-43`, replace the random-bytes stub `encryptionKeyProvider` with `GroupSenderChain` (`packages/helix_remote_crypto/lib/src/group_encryption.dart:4`) so group messages use real epoch keys.
2. **Render Incoming Rich Messages (`app/lib/screens/conversation/message_tile.dart:219-280`) — F29:**
   - Add rendering branches in `_buildMessageBody` for `poll`, `event`, `location`, and `sticker` on `RemoteDecryptedMessage` (e.g., tappable poll options wired to `castPollVote` at `message_sending.dart:348`).
3. **`[STOP & ASK USER]` Before Exposing Stray / Unreferenced UI Screens (F4, F28, F29, F35):**
   - Pause and ask the user which of the following unreferenced UI features should be exposed in the current UI vs. kept hidden/removed:
     - **Group Calls & Call Links (F4):** `GroupCallScreen` (`group_call_screen.dart`), `CallLinkSheet` (`call_link_sheet.dart`), and `ScheduledCallsScreen` create/join/RSVP dialogs (`calls_tab_screen.dart:610-632`).
     - **Rich Content Composers (F29):** Composer buttons for creating Polls, Events, Static/Live Locations, and Stickers.
     - **Multi-Account & Proxy Registry (F28):** `app/lib/app/account_runtime_registry.dart` (wire into `composition_root.dart` + Settings, or delete as unused).
     - **Placeholder Menu Items (F35):** Overflow/action items currently showing `"not available yet"` (Voice notes, Archive chat, Mark as unread, Export chat, Storage and data).

---

## DEFERRED - Group Calls & Group Epoch-Key Distribution

**Decision (user, 2026-09-26):** group calls are deferred. Do not expose the UI.
Recorded here because both are backend gaps, not client wiring, and the reason
is not visible from the client code.

### 1. Group calls cannot carry media (F4)

`RemoteGroupCallService` and `GroupCallScreen` are complete, and the server
tracks rooms, participants and room keys. What does not exist is the relay that
carries SDP and ICE between participants:

- The only signalling route is `POST /calls/signal`
  (`backend/lib/src/modules/calls/signaling.dart:14`).
- Its validator (`calls/validation.dart:13-18`) requires a one-to-one
  `call_id` and a `signal_type` from `{offer, answer, ice, ...}`, and
  `_routeOffer` (`signaling.dart:148-166`) resolves it against a **pending
  1:1 call session**.
- `RemoteGroupCallService` emits `{type: 'offer', sdp: ..., room_id: ...}`
  (`remote_group_call_service.dart:263`), which that validator rejects on both
  counts.
- The group-calls router (`group_calls.dart:37-55`) has 15 routes and none
  relay media.

So a room can be created, joined and populated, but no two devices exchange
audio or video. Exposing `GroupCallScreen` would ship a call UI that silently
carries nothing.

**Unblocking work (backend, needs its own review):** a room-scoped signalling
route that verifies the sender is a JOINED participant of the named room,
reuses the media-policy enforcement and the per-account/device/IP rate limits
from `calls/validation.dart`, and delivers to the target device only.

### 2. Group epoch keys are minted but never distributed (F30)

Half the sender-key chain is missing, and the two halves are on opposite sides:

- **Server has it:** `POST /groups/epoch-key/deliver` (`groups.dart:142`,
  handler `groups/epoch_keys.dart:14`) distributes pairwise-wrapped keys and
  emits a `group_epoch_key` frame per device.
- **Client never calls it.** `RemoteGroupService` has no distribution method -
  the backend handler's own doc comment points at one
  (`epoch_keys.dart:3-4`) that was never written.
- The inbound half now works: the `group_epoch_key` frame is recognised and
  persisted (`sync_engine.dart`, `_GroupEpochKeyEvent`), but nothing unwraps it
  and nothing produces one.

Meanwhile `composition_root/lifecycle.dart` supplies
`encryptionKeyProvider: groupKeyProvider`, which mints a **random 32-byte key
per device** and stores it locally. Two devices in the same group therefore
hold different keys for the same epoch, so a message encrypted on one device
cannot be read on the other. This is the most severe finding in the plan: a
shipped silent failure, not a missing feature.

**Interim state:** do not present group message encryption as working. The mint
stays in place because removing it would break membership changes
(`_rotateEpoch` is called from `leaveGroup`, `removeMember` and invite accept),
and a group with no local key cannot even send.

**Unblocking work (client, needs a crypto decision):** fetch each member
device's agreement public key (`getPreKeyBundle` already returns them), wrap
the epoch key per device, deliver through the outbox, and on receipt unwrap
with the device's agreement private key before storing. The wrapping scheme has
to be chosen and reviewed - it is the same decision `group_calls.dart` already
documents for room keys.

### What *was* done for F30

`group_epoch_key`, `group_join_request_resolved`, `group_add_policy_changed`,
`membership_changed_admin`, `scheduled_call_invite` and
`scheduled_call_cancelled` are now in the envelope gate and have handlers. See
"Envelope gate parity" below - all of them were unreachable before.

---

## Envelope gate parity (new finding, fixed in Phase 4)

`RemoteRealtimeEnvelope.fromJson` flags any type missing from its
`supportedTypes` set as `isUnrecognized`, and that flag makes the sync engine's
`tryParse` return `null` **before** reaching the handler written for that type.

Seven types the backend emits were missing, so their handlers existed and were
dead: `pending_device_link`, `device_linked`, `device_revoked`,
`group_join_requested`, `group_epoch_key`, `group_add_policy_changed` and
`group_join_request_resolved`. That is why Phase 2's device-pairing banner
never appeared in a real build. The sync tests missed it because they build
envelopes directly and never pass through the gate.

Fixed in `helix_remote_api/lib/api/realtime_envelope.dart`, with a test
(`serialization_test.dart`) that mirrors the backend's emissions by source file
so the next omission is caught.

**Phase 4 Verification:**
- Run `flutter analyze` and `flutter test` across `app` and all `packages/*`.

---

## PHASE 5 — Test Suite Modernization & Regression Coverage (Fixes F37)
**Objective:** Update the broken test suite so it matches the redesigned light/colorful UI and guards all newly completed features against regression.

### Step 5.1: Rewrite Stale `helix-admin` Widget Tests (`admin/test/`)
Update the 6 test files that assert against pre-redesign widgets and labels:
1. **`admin/test/users_tab_test.dart`:** Update button finders to match current labels (`'Suspend'`, `'Restore'`, `'Delete Data'`, `'Permanent Block Phone'`), test the new `"No connected devices"` empty state (F9), and verify that Suspend/Restore toasts only appear after the HTTP call succeeds (F23).
2. **`admin/test/invites_tab_test.dart`:** Update `'Generate Invite'` finder to match the `'Create Invite'` `IconButton` (`invites_tab.dart:171-192`), update Cancel button finders, and add a test verifying real `expires_at` and `EXPIRED` status rendering (F21).
3. **`admin/test/logs_tab_test.dart`:** Update finders to match the redesigned `LogsTab`, verify the new manual **Refresh** button (F25), and verify that an empty log response renders `ServerLogs.message` instead of `_sampleLogs` (F18).
4. **`admin/test/guide_wizard_test.dart`:** Update text expectations (`'🌐 Self-Hosting Guide'`, `'STEP N OF 8'`) or remove/adjust based on the user's decision in Step 3.2.
5. **`admin/test/server_name_card_test.dart`:** Update button text (`'Save Name'`) and error string (`"Couldn't reach server."`) assertions.
6. **`admin/test/widget_test.dart`:** Replace legacy sidebar assertions (`'Helix Panel'`, `Key('sidebar_sign_out_button')`) with assertions against the redesigned top navigation bar and light theme.

### Step 5.2: Add New Admin & Cross-Repo Regression Tests
1. Add widget/unit tests for:
   - `reports_tab.dart`: Verify error state rendering when `getReports` throws, and verify `resolveReport` / `dismissReport` surface errors on non-200 responses instead of mutating local state (F1, F24).
   - `ops_tab.dart`: Verify empty audit logs render the empty state instead of `_defaultAuditEvents` (F17).
   - `dashboard_tab.dart`: Verify integration health cards reflect `metrics.push_provider` and `metrics.turn` (F16).
   - Contract test: Verify every response key read by `AdminClient` and admin tabs exists in the corresponding backend handler in `operability.dart` (F20).

### Step 5.3: Clean Up `helix-remote` Golden Failure Artifacts
1. Remove the 12 committed failure images under `app/test/failures/`.
2. Update or regenerate the baseline goldens in `app/test/phase5_responsive_screenshot_test.dart` so the test suite runs clean.

**Phase 5 Verification:**
- Run full test suites across `backend`, `packages/*`, `app`, and `admin` (`flutter test` / `dart test`) and confirm **0 analyzer warnings and 0 failing tests**.
