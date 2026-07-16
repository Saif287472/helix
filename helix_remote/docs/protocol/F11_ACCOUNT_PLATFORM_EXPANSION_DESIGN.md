# F11 Account And Platform Expansion Design

F11 adds the local contract for running Helix Remote across multiple account
contexts and platform families without sharing runtime state. The phase does
not replace packaging infrastructure; it gives the app, storage, diagnostics,
and future platform shells a single source of truth for account isolation and
capability gating.

## Account Runtime Containers

Each account runtime descriptor owns distinct values for:

- database path
- secure storage namespace
- token key prefix
- key material prefix
- attachment cache path
- notification channel and namespace
- sync task namespace
- call task namespace
- share target namespace
- clipboard namespace
- server base URL

The registry rejects descriptors that reuse another account's database path,
secure storage namespace, attachment cache path, or notification channel. Account
switches clear the previous active flag before enabling the next account.

Runtime rows are stored in local schema v23. Deleted account runtimes can be
purged together with their proxy rows. Runtime rows and proxy rows are excluded
from encrypted backup snapshots because they contain device-local execution
state, paths, and secret references rather than portable conversation data.

## Active Account Indicators

Every UI surface can ask the registry for an account-bound context. The returned
context includes the active account id, display name, notification channel, and
surface name for navigation, composer, notification, share target, and call UI
indicators. It also returns the account-scoped namespaces needed by background
tasks and platform integrations.

## Proxy And Connectivity Diagnostics

Proxy settings are account-scoped and cover REST, WebSocket, attachment
transfer, and call signaling. TURN/media proxying remains separate because media
relay policy is negotiated through ICE/TURN configuration rather than the
general HTTP/WebSocket transport path.

Diagnostics redact secrets. They expose whether a username or password reference
exists, but never emit the credential or encrypted password reference itself.
Certificate validation cannot be disabled for Remote traffic.

## Platform Capability Flags

F11 defines platform capability profiles for Windows, macOS, tablet layouts,
mobile, Linux, and deferred constrained platforms. UI and platform integration
code should check feature flags before showing controls for notifications,
tray/background sync, deep links, drag and drop, file associations, call
windows, auto updates, crash recovery, camera, microphone, screen sharing, and
two-pane chat.

Windows is marked as the complete desktop target for installer/signing,
single-instance deep links, notifications, tray/background sync, drag and drop,
file associations, call windows, updates, and crash recovery. macOS is present
as a gated capability set to be completed after Windows behavior is stable.
Smartwatch, constrained OS, and OS-default messaging integration remain hidden
or unavailable until the core account/sync APIs are stable enough for companion
clients.

## Verification

Focused tests cover account isolation, explicit switching, inactive-account
cleanup, proxy validation and redacted diagnostics, platform capability gating,
schema v23 creation, and the backup schema gate.
