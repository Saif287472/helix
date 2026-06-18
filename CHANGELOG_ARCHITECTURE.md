# Architecture Changelog

All major monorepo structure, product isolation, package boundary, and database schema migrations are tracked here.

## [1.0.0] - 2026-06-18

### Added
- Audited codebase and established repository freeze baseline (`baseline` tag).
- Added `CHANGELOG_ARCHITECTURE.md` and `docs/architecture/CURRENT_STATE_2026-06-18.md` for historical auditing.
- Fixed a pre-existing failing test in `test/phase0_test.dart` related to per-thread auto-wipe reconnection timer.
- Deleted unused root test files (`test.py`, `test_mode.txt`).
