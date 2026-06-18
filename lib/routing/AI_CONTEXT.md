# Routing Context

## Responsibility

Current routing lives in `lib/ui/app_router.dart`. This directory exists as the
future routing target once app/bootstrap folders are introduced.

## Public Entry Points

- Current: `lib/ui/app_router.dart`
- Target: `lib/app/router/` or `lib/routing/`

## Dependencies

Routing may depend on presentation screens and route guards. It should avoid
business logic and direct transport/service internals.

## Invariants

- Route guards must preserve setup, lock, and session expectations.
- Navigation changes must not bypass trust or setup flows.

## Error Handling

Unknown routes should fail to a safe screen, not a blank app.

## Required Tests

Widget smoke tests and targeted route tests when route guards change.

## High-Risk Areas

Setup flow, lock screen, chat route parameters, and request/QR entry points.
