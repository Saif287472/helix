# ADR 023: iOS support decision

Status: accepted (2026-08-07)

Helix Remote does not currently ship an iOS target. This is an explicit
product exclusion, not implied support from Flutter dependencies. The release
checklist and public release notes must describe supported platforms as Android
and Windows only.

Adding iOS requires its own implementation/review milestone: secure-storage
and SQLCipher validation, notification/call background behavior, screen-capture
protection, deep links, accessibility, App Store privacy disclosures, release
signing, and the same transport-pinning controls as Android. No iOS artifact
may be published before those controls have test evidence.
