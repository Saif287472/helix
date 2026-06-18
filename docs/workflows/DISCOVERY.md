# Peer Discovery

## Intended Behavior

Peers discover each other on LAN through mDNS where available and UDP broadcast
as fallback. Direct-IP peers can be introduced by QR payloads.

## Invariants

- Discovery advertises session presence, not private identity material.
- mDNS and UDP inputs normalize into the same peer registry.
- Stale peers expire.
- Off-grid LAN operation must not depend on internet access.

## Failure Handling

- Socket bind failures are reported through diagnostics.
- Discovery failure must not wipe existing secure threads.

## Verification

- `test/discovery_test.dart`
- Diagnostics smoke tests.
- Offline LAN manual check before release.
