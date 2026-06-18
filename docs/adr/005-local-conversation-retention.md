# ADR 005: Local Conversation and Message Retention

Status: accepted  
Date: 2026-06-19  

## Context
The product specification for Helix Local mandates that conversation data does not persist long-term on the device. However, current database tables are written to SQLite, persisting threads and messages across restarts.

## Decision
Helix Local will keep chat threads, messages, group history, drafts, and one-way inbox data in **RAM only**:
- Database persistence is retired for chat contents in Helix Local.
- SQLite is restricted to non-content metadata (such as profile settings, favorite flags, and trusted fingerprints).
- All message histories are wiped automatically when the app is closed or restarted.

## Consequences
- Guarantees ephemerality of Local communications.
- Eliminates risk of forensic extraction of local database files for messages.
