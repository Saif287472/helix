# Package: helix_remote_domain

Status: current, and nearly empty on purpose. Phase X deleted the v1 entities,
status transition tables and message-content types (nothing in v2 used them:
v2 wire types live in `helix_remote_protocol`, stored rows in
`helix_remote_db`, UI value objects in `helix_remote_ui`).

## Purpose

Shared value types that belong to no other layer. Today that is one file:
`HelixLegalDocuments` (the versioned terms and privacy text the sign-in page
shows). The server keeps its own copy in `helix_remote_protocol`
(`lib/src/legal.dart`) so it can serve `GET /v1/server/legal`; keep the two
texts and versions in step when the documents change
(`docs/legal/`).

## Public surface

`lib/models.dart` exports `domain/legal_documents.dart`.

## Who may depend on this

The app (sign-in legal sheet). It may grow again if a type is needed by both
the engine and the UI and by no wire format; folding it into
`helix_remote_protocol` is the alternative if it never does.

## What this may depend on

Nothing. No dependencies at all, not even `meta`.
