# Target Project Structure

Status: Stage 2 target, documentation only.

No files are moved in Stage 2. This document describes the destination shape for
later refactor stages.

## Target Layout

```text
lib/
  app/                         # Bootstrap, router, theme, lifecycle
  core/                        # Shared constants, enums, utilities
  domain/                      # Pure Dart entities and repository ports
    peer/
    conversation/
    session/
    transfer/
    group/
    call/
    trust/
  protocol/                    # Frame definitions, codecs, versioning
    envelope/
    discovery/
    identity/
    session/
    messaging/
    transfers/
    groups/
    calls/
    errors/
    codecs/
    versioning/
  crypto/                      # Identity, key agreement, cipher, ratchet
    identity/
    key_agreement/
    authentication/
    session_keys/
    message_cipher/
    ratchet/
    replay_protection/
    trust/
    key_storage/
    test_vectors/
  transport/                   # TCP/TLS connection, frame I/O, keepalive
  infrastructure/              # Concrete adapters
    discovery/
    storage/
    platform/
    notifications/
  application/                 # Use cases, coordinators, state machines
    messaging/
    connections/
    groups/
    transfers/
    calls/
    discovery/
    profile/
    trust/
  features/                    # Presentation, feature-first
    discovery/
    connection_requests/
    conversations/
    calls/
    transfers/
    groups/
    profile/
    trust/
    settings/
    diagnostics/
  shared/                      # Cross-feature widgets and providers
    widgets/
    presentation/
    providers/
```

## Dependency Direction

- `features` depend on `application`, `domain`, and shared presentation.
- `application` depends on `domain` and ports, not concrete infrastructure.
- `infrastructure` implements ports and may depend on platform/plugins.
- `transport`, `protocol`, and `crypto` are separate security-sensitive seams.
- `domain` must eventually be pure Dart with no Flutter, Riverpod, SQLite,
  platform channels, crypto implementation packages, or `dart:io`.
- `protocol` must not depend on UI, storage, platform, or transport sockets.

## Migration Notes

- Stage 3 splits protocol first because it is the easiest stable seam to test
  with fixtures.
- Stages 4 and 5 split transport, crypto, and application services after
  protocol contracts are pinned.
- Stage 7 extracts stable folders into internal packages only after imports are
  acyclic and public contracts are documented.
