# ADR 010: Remote Backend Modular Monolith

Status: accepted  
Date: 2026-06-19  

## Context
A microservices backend architecture would introduce premature scaling complexity, making Solo maintenance difficult and raising operational failures during prototype cycles.

## Decision
The Remote backend starts as a **Modular Monolith**:
- Single deployed executable/container.
- Clean directory separation representing bounded contexts (accounts, devices, keys, messaging, attachments).
- Cross-module operations use strictly typed internal interfaces.
- Separate transactional boundaries per module where possible.

## Consequences
- Single database deployment simplifies migrations.
- Eases local development and deployment.
- Modules can be separated into microservices in the future if scale warrants it.
