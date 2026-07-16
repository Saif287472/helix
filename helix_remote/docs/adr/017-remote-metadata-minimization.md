# ADR 017: Remote Metadata Minimization and Privacy Logging

Status: accepted  
Date: 2026-06-19  

## Context
Centralized messaging backends are vulnerable to target tracking and data leaks. Minimizing the metadata stored on servers is key to protecting user privacy.

## Decision
Enforce strict server-side metadata minimization:
- The server stores only active mailboxes for offline delivery; once a message is delivered and acknowledged, it is purged from the server queue.
- IP addresses, connection logs, and message routing paths must not be logged permanently.
- Production server logs must pass a redaction filter preventing plaintext content, usernames, and key fingerprints from appearing in traces.

## Consequences
- Protects users from server-compromise leaks.
- Aligns backend development with high-privacy guidelines.
