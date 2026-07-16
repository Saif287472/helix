# Persistence Policy

Status: Stage 5 foundation.

## Conversations

Current text-message behavior remains RAM-oriented. The target composition root
will choose between `EphemeralConversationRepository` and a future
`PersistentConversationRepository`.

## Drafts

Drafts must survive app restart and therefore require persistent local storage.

## Trust

Trust records are security-sensitive and must use protected storage, not plain
SQLite without encryption.

## Groups

Group metadata may persist locally. Session-only bans remain non-persistent by
the V4 decision unless that product decision changes.
