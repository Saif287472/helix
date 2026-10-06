# ADR 029: Architecture guardrails for v2

Status: accepted (2026-09-30).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§8, §11, §12).

## Context

v1 drifted because its boundaries were conventions. The "modular" backend
shares one database class, screens call the database directly, and tables
were added ahead of the features that needed them. v2 is meant to last
without another redesign, so the boundaries must be enforced mechanically.

## Decision

- **`helix_remote_architecture_rules`** (dev-only package): a small rule
  engine that scans Dart sources for `import`, `export` and `part` directives
  and checks them against declared rules. Each v2 package and the server has
  an `architecture_test.dart` that applies the rules for its layer:
  - package dependency direction (plan §6.1)
  - server modules import only other modules' `api.dart`
  - presentation imports no db, api, crypto or engine
  - no `sqlite3`/`drift` outside `helix_remote_db`
  - no v1 packages (`helix_remote_storage`, `helix_remote_sync`,
    `helix_remote_groups`, `helix_remote_backend`) in v2 code
- **Snapshot tests** for security-relevant surfaces, starting with the list of
  public (unauthenticated) routes.
- **Plan discipline:**
  - Work only on the next unfinished phase in the plan tracker.
  - Update the tracker (status, date, commit, test counts) at the end of each
    phase.
  - Any change to the target architecture needs a new ADR plus a change-log
    entry approved by the user in chat.
- **Phase gate:** analyzers clean, all suites green, `dart format` on changed
  files, docs updated in the same commit, and one commit per phase on branch
  `architecture-v2`.
- **Scope:** `helix_remote/` only. Nothing under `helix_local/` changes.

## Consequences

- Breaking a boundary fails CI instead of passing review unnoticed.
- The rule engine uses regex directive scanning rather than the analyzer
  package. That is enough for directives, which are line-oriented. Revisit
  only if a rule needs type information.
