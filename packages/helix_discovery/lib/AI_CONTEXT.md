# Discovery Context

## Responsibility

Discovery owns local peer discovery through mDNS, UDP broadcast, peer registry
state, and short-lived direct-IP discovery helpers.

## Public Entry Points

- `helix_discovery.dart`
- `discovery_coordinator.dart`
- `mdns_discovery.dart`
- `udp_discovery.dart`
- `peer_registry.dart`

## Dependencies

Discovery may depend on domain peer models, protocol/constants, Flutter method
channels where needed for platform discovery, and `dart:io`. It must not import
UI, providers, storage implementations, trust decisions, or message contents.

## Invariants

- Discovery identifies candidates; it does not establish trust.
- Peer records must expire when stale.
- Broadcast payloads must remain bounded and must not include secrets.
- Direct-IP probes must not bypass request approval or secure-channel setup.

## Required Tests

- `test/discovery_test.dart`
- Request/channel integration tests that cover direct-IP fallback.

## High-Risk Areas

UDP payload validation, stale peer eviction, platform mDNS behavior, duplicate
peer resolution, and keeping discovery metadata separate from trust state.
