# ADR 011: Contract-First Remote APIs

Status: accepted  

> Status note (Phase X): superseded by ADR-028. The OpenAPI and JSON-Schema files named here were deleted; the contract is the Dart route catalog in `packages/helix_remote_protocol` plus `docs/protocol/v2/REST_V2.md`, kept in step by tests (route parity, documentation coverage, golden fixtures in `contracts/v2/fixtures/`).
Date: 2026-06-19  

## Context
Client and server development will happen in parallel. Ad-hoc API changes risk client compatibility errors and network communication bugs.

## Decision
All Helix Remote client-server communication will use **Contract-First design**:
- REST endpoints are defined in OpenAPI specifications under `contracts/remote-rest-openapi/`.
- Realtime WebSocket envelopes are defined in JSON-Schema/Protobuf schemas under `contracts/remote-realtime/`.
- Changes must pass a backward-compatibility audit before landing.
- Enforce versioned endpoints (e.g., `/api/v1/`).

## Consequences
- Guarantees backward/forward compatibility.
- Client types can be safely generated from contract specs.
