# Log Redaction Policy

Production logs and diagnostic exports must not contain decrypted protocol
payloads or sensitive identity material.

## Always Redact

- Message text and private media bytes.
- Secret sentences and passphrases.
- Private keys, session keys, proofs, access tokens, and API keys.
- Full peer fingerprints. Show at most a short suffix when needed.
- File names for private media.
- Raw QR/group invitation payloads.

## Safe Fields

- Protocol major/minor version.
- Capability bitmask names.
- Thread or peer pseudonyms when they cannot be reversed to identities.
- Error categories without sensitive values.

## Diagnostic Export

Diagnostic export must require explicit user action and should prefer structured
events with redacted identifiers over raw logs.
