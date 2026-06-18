# Product Independence & Acceptance Criteria

This sheet details the verification criteria that define successful isolation and product delivery in the monorepo.

## 1. "Independently Installable" Criteria
- Local and Remote build separate binaries (e.g. `com.helix.local` APK and `com.helix.remote` APK).
- A single test device (Android or Windows) can install and run both apps concurrently.
- No shared database locks or file access exceptions occur during simultaneous active runs.
- Clearing/uninstalling one app has zero impact on the other's storage directory or secure keychain.

## 2. "Local Works Fully Offline" Criteria
- Helix Local compiles, runs, discovers peers, and operates messages/calls without any internet connection.
- No HTTP/HTTPS endpoints pointing to Remote servers are compiled into the Local shell.
- System functions correctly if the Remote backend monolith is completely offline.

## 3. "Remote Persists Until Deletion" Criteria
- Chats and attachments survive app close, restart, and device power cycles.
- Server purges message mailboxes only after recipient device sends an explicit ACK response.
- Complete user account deletion permanently wipes server records.
