# ADR 009: Separate Local and Remote Cryptographic Identities

Status: accepted  
Date: 2026-06-19  

## Context
A user may install both Helix Local and Helix Remote on the same device. Using the same key pairs or identities for both presents a severe tracking risk and compromises local-only anonymity assumptions.

## Decision
Helix Local and Helix Remote identities are completely isolated:
- Local identity keys are kept in the Local secure namespace and never uploaded.
- Remote identity keys are registered on the Remote backend directory and linked to an account.
- The same username or nickname across Local and Remote does not imply matching cryptographic keys.

## Consequences
- Prevents cross-app user tracking.
- Guarantees cryptographic isolation.
