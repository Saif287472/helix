# Stage 5 Foundation Checkpoint

Status: in progress
Date: 2026-06-15

Stage 5 is larger than a single safe mechanical move. This checkpoint adds the
typed migration targets and documentation needed before moving runtime
consumers.

## Added Code

- `lib/application/contracts/repositories.dart`
- `lib/application/contracts/gateways.dart`
- `lib/application/contracts/use_cases.dart`
- `lib/application/state_machines/workflow_states.dart`
- `lib/application/state_machines/workflow_transitions.dart`
- `lib/app/composition_root.dart`
- `test/workflow_transitions_test.dart`

## Added Documentation

- `docs/application/SERVICE_MIGRATION_RECORDS.md`
- `docs/application/MODEL_SPLIT_PLAN.md`
- `docs/application/COMPOSITION_ROOT.md`
- `docs/application/PLANE_SPLIT.md`
- `docs/application/PERSISTENCE_POLICY.md`

## Validation

Commands run:

```powershell
flutter test test\workflow_transitions_test.dart
.\scripts\verify.ps1
```

Result:

- Analyzer: no issues found
- Boundary check: passed
- Secret scan: passed
- Full tests: 102 passed
- Canonical verification: passed

## Remaining Stage 5 Work

- Wrap existing services with adapter implementations.
- Move provider construction into the composition root.
- Split `domain/models.dart` by bounded context.
- Add mapper tests for protocol/domain/persistence/presentation boundaries.
- Migrate UI/providers to application use cases and controllers.
- Delete legacy service responsibilities only after consumers are migrated and
  tests stay green.
