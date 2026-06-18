# ADR 013: Multi-Device-Ready Data Model from Day One

Status: accepted  
Date: 2026-06-19  

## Context
Adding multi-device support later in a messaging app requires painful database schema migrations and E2EE envelope refactoring. 

## Decision
All Helix Remote database schemas, backend APIs, and E2EE models must incorporate multi-device assumptions from day one:
- Devices are distinct registered resources linked to a single account ID.
- Message delivery is modeled as a fan-out queue targeting individual device IDs.
- Cursors, tombstones, and message statuses are tracked per-device.
- Key directories support publishing multiple prekey bundles per user.

## Consequences
- Prevents database re-writes when deploying multi-device support.
- Initial single-device deployment will seamlessly transition to multi-device.
