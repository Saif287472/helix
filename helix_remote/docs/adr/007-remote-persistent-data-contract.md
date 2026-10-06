# ADR 007: Helix Remote Persistent Data Contract

Status: accepted  

> Status note (Phase X): the client half (a SQLCipher database on the device) still holds, now as drift on SQLite (ADR-027). The server half is superseded: the server uses PostgreSQL (ADR-025).
Date: 2026-06-19  

## Context
Unlike Helix Local, Helix Remote is designed for persistent, cross-network communication. Users expect history, files, contacts, and devices to persist until they choose to delete them.

## Decision
Helix Remote will use a standard SQL database configuration on the client (with SQLite) and server (with SQLite, with PostgreSQL as a future target):
- All local database files for Helix Remote must be encrypted (SQLCipher).
- Messages and attachments are stored persistent locally.
- Server-side storage stores encrypted message envelopes (ciphertext) for delivery, retaining them in mailboxes until retrieved or expired.
- Contacts, devices, and profile settings are synchronized as a persistent database state.

## Consequences
- Supports offline-first chat history browsing.
- Enforces strong E2EE guarantees so the server cannot read persistent records.
