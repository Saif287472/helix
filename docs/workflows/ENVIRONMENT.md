# Environment Configuration

## Intended Behavior

Helix is local-first and should run without production service credentials.
Optional local development settings belong in environment files that are never
committed.

## Invariants

- `.env.example` contains placeholders only.
- Real `.env*` files are ignored.
- Startup should fail fast when a required future config value is missing.
- Production URLs or credentials must not be hardcoded.

## Failure Handling

- Invalid config should produce an actionable local error.
- Missing optional config should fall back to local-only behavior.

## Verification

- Secret scan.
- Manual review for config or dependency changes.
