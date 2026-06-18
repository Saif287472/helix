# ADR 016: Release Signing Independence

Status: accepted  
Date: 2026-06-19  

## Context
Sharing signing keys or building release builds with debug configurations poses severe supply-chain security risks.

## Decision
Helix Local and Helix Remote will use entirely separate release signing credentials:
- Release signing keys are stored securely outside the repository.
- CI pipeline injected variables are used during release runs.
- Release configuration builds on CI will fail immediately if debug signing configurations are detected.

## Consequences
- Protects the cryptographic integrity of the application binaries.
- Ensures independent updates and distribution pathways on app stores.
