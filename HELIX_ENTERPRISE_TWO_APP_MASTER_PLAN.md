# HELIX ENTERPRISE TWO-APP MASTER PLAN

**Status:** Split index. The original monolithic plan was intentionally split to reduce token usage for future agents.
**Split date:** 2026-06-19

## Read This First

- Future implementation agents should read `AGENTS.md` and then `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_2_REMAINING.md`.
- `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_1_COMPLETED.md` is historical reference for completed phases, decisions, deliverables, work log, and externally blocked foundation items.
- `phase_0-11_closure_and_repair_pass.md` and `docs/architecture/PHASE_9_11_CLOSURE.md` remain the detailed closure/audit records for Phases 9-11.

## Current Status

Phases 0-11 are complete for forward development, except for externally blocked items that must remain documented and must constrain claims. Development should continue with Phase 12 without waiting for those external dependencies.

## Plain Formatting Rule

Use plain ASCII punctuation in generated plan scaffolding: `-` instead of em dash, straight quotes instead of smart quotes, and `->` for arrows. Historical copied sections may contain typographic punctuation; preserve them unless a task explicitly asks for cleanup.

## Plan Files

1. `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_1_COMPLETED.md` - completed foundation work, historical decisions, work log, and blocked foundation items.
2. `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_2_REMAINING.md` - Phase 12+ execution plan, remaining tasks, dependencies, acceptance criteria, and operating rules.

## Externally Blocked Items

- Remote database encryption remains BLOCKED until a SQLCipher-capable or equivalent reviewed encrypted database library supports the required Flutter Android and Windows targets.
- Independent external cryptographic/security review remains BLOCKED until an actual independent reviewer evaluates the exact implementation/version.
- Staging deployment remains BLOCKED until real infrastructure and credentials exist; do not fabricate staging evidence.
- Full DH/skipped-key ratchet support remains BLOCKED pending a reviewed implementation. Current symmetric-chain tests prove auth-failure rollback, replay rejection, and honest early out-of-order rejection only.

## Next Normal Action

Begin **Phase 12 - Remote One-to-One Messaging MVP** from Part 2, unless the user explicitly requests a different task.
