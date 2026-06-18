# ADR 012: Remote E2EE Protocol Selection Process

Status: accepted  
Date: 2026-06-19  

## Context
Writing custom cryptographic protocols is highly risky and prone to implementation flaws. Helix Remote must use a verified, mature E2EE protocol.

## Decision
Helix Remote will adopt a proven end-to-end encryption standard:
- We will select a mature E2EE protocol (e.g., Double Ratchet / Signal Protocol).
- We must use a peer-reviewed, widely deployed open-source library implementation.
- Custom extensions or modifications to the cryptographic primitives are strictly prohibited.
- Cryptographic vectors and downgrade scenarios must be fully covered by automated test fixtures.

## Consequences
- Reduces security risk and establishes a reliable trust profile.
- Restricts development of home-grown cryptographic messaging loops.
