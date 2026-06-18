# Composition Root

Status: Stage 5 foundation.

`lib/app/composition_root.dart` introduces the target location for binding
repositories, gateways, stores, and engines. Current Riverpod providers remain
the runtime wiring until adapters are migrated.

## Rule

Concrete infrastructure should eventually be constructed in one place and
exposed through application/domain interfaces.

## Migration Order

1. Add interfaces and state machines.
2. Wrap existing services with adapter implementations.
3. Move provider construction to composition root.
4. Switch UI providers to expose application interfaces.
5. Remove direct UI/provider access to infrastructure.
