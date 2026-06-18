# Current Codebase State — 2026-06-18

This document records the exact baseline environment, configuration parameters, identifiers, and schema versions of the Helix repository prior to the two-app split and refactoring.

## 1. Environment & Tools
- **Flutter Version**: `3.44.2` (stable)
- **Dart SDK Version**: `3.12.2` (stable)
- **Java JDK Version**: `21.0.10`
- **Gradle Wrapper Version**: `9.1.0`
- **Android SDK Path**: `C:\Users\Hasan\AppData\Local\Android\sdk`
- **Compile SDK Version**: `36`
- **Min SDK Version**: (Inherited from flutter engine configs)
- **Target SDK Version**: (Inherited from flutter engine configs)

## 2. Platform Configurations & Identifiers

### Android (Helix Local Base)
- **Application ID / Package Namespace**: `com.helix.helix`
- **MainActivity Class**: `com.helix.helix.MainActivity` (launchMode: `singleTop`)
- **Foreground Service Class**: `com.helix.helix.HelixForegroundService` (foregroundServiceType: `connectedDevice|microphone`)
- **Method Channels**:
  - `com.helix.app/foreground` (foreground service control)
  - `com.helix.app/mdns` (mDNS network service discovery)
  - `com.helix.app/mdns/events` (mDNS event subscription stream)
  - `com.helix.app/multicast_lock` (multicast lock control for Android Wi-Fi)
- **Permissions Declared**:
  - `android.permission.INTERNET`
  - `android.permission.ACCESS_NETWORK_STATE`
  - `android.permission.CHANGE_NETWORK_STATE`
  - `android.permission.ACCESS_WIFI_STATE`
  - `android.permission.CHANGE_WIFI_STATE`
  - `android.permission.CHANGE_WIFI_MULTICAST_STATE`
  - `android.permission.FOREGROUND_SERVICE`
  - `android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE`
  - `android.permission.POST_NOTIFICATIONS`
  - `android.permission.CAMERA`
  - `android.permission.RECORD_AUDIO`
  - `android.permission.MODIFY_AUDIO_SETTINGS`
  - `android.permission.FOREGROUND_SERVICE_MICROPHONE`
  - `android.permission.USE_FULL_SCREEN_INTENT`
  - `android.permission.VIBRATE`
- **App Label**: `helix`
- **Icon**: `@mipmap/ic_launcher`

### Windows (Helix Local Base)
- **App Class / Window Class**: `helix`
- **Window Title**: `helix`
- **AppUserModelId**: `com.helix.app`
- **Stable Notification GUID**: `17b09742-cd2c-45d4-b0fe-52814bfd70ae`
- **Tray Identity**: Configured via `tray_manager` and `window_manager` packages.

## 3. Storage & Persistence
- **Secure Storage Keys**:
  - `identity_cert_pem`
  - `identity_key_pem`
  - `display_name`
  - `secret_code_verifier`
  - `discoverable`
  - `first_run_done`
  - `secret_code`
  - `known_peers`
  - `notify_show_sender`
  - `notify_sound`
  - `theme_mode`
  - `accent_color`
  - `amoled_dark`
  - `copy_enabled`
  - `screenshot_protect`
  - `read_receipts_enabled`
  - `typing_indicators_enabled`
  - `home_welcome_dismissed`
  - `biometric_lock`
  - `lock_after_minutes`
  - `ringtone_asset`
- **Database File**: `helix.db`
- **Database Engine**: SQLite (raw via `package:sqlite3` + `sqlite3_flutter_libs`)
- **WAL Journaling**: Enabled (`PRAGMA journal_mode = WAL`)
- **Foreign Keys**: Enabled (`PRAGMA foreign_keys = ON`)
- **Schema Version (`user_version`)**: `3`

### SQLite Schema

```sql
CREATE TABLE IF NOT EXISTS threads (
  thread_id                  TEXT PRIMARY KEY,
  peer_display_name          TEXT NOT NULL,
  peer_device_suffix         TEXT NOT NULL,
  peer_static_key_fingerprint TEXT NOT NULL,
  peer_session_id            TEXT NOT NULL DEFAULT '',
  peer_host                  TEXT NOT NULL DEFAULT '',
  peer_port                  INTEGER NOT NULL DEFAULT 0,
  status                     INTEGER NOT NULL DEFAULT 0,
  unread_count               INTEGER NOT NULL DEFAULT 0,
  has_new_session_separator   INTEGER NOT NULL DEFAULT 0,
  created_at                 INTEGER NOT NULL,
  updated_at                 INTEGER NOT NULL,
  draft_text                 TEXT NOT NULL DEFAULT '', -- Added in Mig 3
  is_archived                INTEGER NOT NULL DEFAULT 0 -- Added in Mig 3
);

CREATE TABLE IF NOT EXISTS messages (
  message_id      TEXT PRIMARY KEY,
  thread_id       TEXT NOT NULL REFERENCES threads(thread_id) ON DELETE CASCADE,
  origin          INTEGER NOT NULL,
  text            TEXT NOT NULL,
  timestamp       INTEGER NOT NULL,
  delivery_status INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_thread
  ON messages(thread_id, timestamp ASC);

CREATE TABLE IF NOT EXISTS one_way_messages (
  message_id                  TEXT PRIMARY KEY,
  peer_display_name           TEXT NOT NULL,
  peer_device_suffix          TEXT NOT NULL,
  peer_session_id             TEXT NOT NULL,
  peer_static_key_fingerprint TEXT NOT NULL,
  peer_host                   TEXT NOT NULL,
  peer_port                   INTEGER NOT NULL,
  text                        TEXT NOT NULL,
  timestamp                   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS peers_cache (
  session_id     TEXT PRIMARY KEY,
  display_name   TEXT NOT NULL,
  device_suffix  TEXT NOT NULL,
  host           TEXT NOT NULL,
  port           INTEGER NOT NULL,
  source         INTEGER NOT NULL,
  seen_at        INTEGER NOT NULL,
  protocol_major INTEGER NOT NULL,
  protocol_minor INTEGER NOT NULL,
  is_favorite    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pinned_messages (
  thread_id  TEXT NOT NULL,
  message_id TEXT NOT NULL,
  pinned_at  INTEGER NOT NULL,
  PRIMARY KEY (thread_id, message_id),
  FOREIGN KEY (thread_id) REFERENCES threads(thread_id) ON DELETE CASCADE
);
```

## 4. Root Test Artifact Audit
The following root artifacts are confirmed as unused legacy/diagnostic files and are deleted to freeze a clean codebase baseline:
- `test.py`: Simple hello-world python test script (`import sys; print('hello')`).
- `test_mode.txt`: Empty file used historically to flag test-environment overrides.
