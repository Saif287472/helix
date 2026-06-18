# Storage Context

## Responsibility

Storage owns SQLite access, profile persistence, secure storage adapters,
in-memory repositories used by current controllers, and forward-only database
migrations.

## Public Entry Points

- `data/database.dart`
- `data/database_provider.dart`
- `infrastructure/storage/*`

## Dependencies

Storage may depend on domain repository contracts, SQLite, secure storage, and
Flutter plugin adapters. It must not import UI, providers, transport sockets, or
protocol frame codecs.

## Invariants

- Never persist ephemeral media bytes.
- Never log secrets, private keys, tokens, message contents, or full
  fingerprints.
- Migrations must be numbered, forward-only, and transactional.
- Identity, trust, session, and wipe behavior are security-sensitive.

## Required Tests

- Migration tests.
- Repository tests for trust/session/profile persistence.
- Wipe behavior tests for disconnect and expiry flows.

## High-Risk Areas

Schema migration order, secure-storage key handling, profile reset/wipe paths,
trust record integrity, and any future move from in-memory repositories to
durable message storage.
