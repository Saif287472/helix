# Helix Global legal documents

The documents in this directory are the product-specific Terms of Service and
Privacy Policy shipped for the Helix Global deployment.

- [Terms of Service](terms_of_service.md)
- [Privacy Policy](privacy_policy.md)
- Runtime copy: `packages/helix_remote_domain/lib/domain/legal_documents.dart`

The current version is `2026-09-25` (effective September 25, 2026). The Flutter
client shows the runtime copy; the server keeps its own copy in
`packages/helix_remote_protocol/lib/src/legal.dart` and serves it at
`GET /v1/server/legal`, and registration must name the current terms version.
Keep the two copies and their versions in step when the documents change.

These documents are an operator-ready starting point, not a substitute for
review by qualified counsel. Before public launch, the Helix Global operator
should confirm the contact addresses, governing-law language, retention
commitments, and any jurisdiction-specific requirements.
