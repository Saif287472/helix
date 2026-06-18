# Providers Context

## Responsibility

Providers compose controllers and package adapters, expose Riverpod state, and
bridge controller change notifications to UI rebuilds.

## Public Entry Points

- `app_providers.dart`
- `session_provider.dart`
- `controllers/*`

## Dependencies

Providers may depend on UI-facing controllers, application use cases, package
exports, data/storage adapters, platform wrappers, and domain models. Internal
packages must not import providers.

## Invariants

- Provider wiring must not change business rules.
- Controller instances should be disposed predictably.
- UI refresh providers must notify after controller mutations.

## Error Handling

Provider initialization errors should surface to UI or diagnostics instead of
failing silently.

## Required Tests

- `test/provider_refresh_test.dart`
- Widget smoke tests for app bootstrap.

## High-Risk Areas

Cross-service bridge wiring, lifecycle disposal, foreground service connection
count, and reconnect hooks.
