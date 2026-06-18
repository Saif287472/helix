# ADR 003: Existing Code Classified as Local-Specific by Default

Status: accepted  
Date: 2026-06-19  

## Context
Helix currently exists as a single-app project. Evolving this into two products requires a strategy to prevent Local assumptions (such as LAN-only protocols, ephemeral keys, and discovery ports) from leaking into the Remote application.

## Decision
All pre-existing packages, code folders, and configurations in the repository are classified as **Local-specific by default**. 
No code or model will be promoted to the `shared/` directory unless it has undergone a deliberate extraction review showing that it carries no Local-specific runtime or retention assumptions.

## Consequences
- Prevents Remote from accidentally inheriting Local LAN architectures.
- Promotes clean decoupling and enforces explicit dependency pathways.
