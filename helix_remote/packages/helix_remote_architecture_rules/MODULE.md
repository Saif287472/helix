# helix_remote_architecture_rules

Dev-only rule engine for Helix Remote v2 import boundaries (ADR-029,
`docs/architecture/ARCHITECTURE_V2_PLAN.md` §8). Depends on no Helix package.

## What it provides

- `scanDartSources(root)`: reads every `import`/`export`/`part` URI under
  `lib/`, `bin/` and `test/` (conditional URIs included, `part of` and
  comments skipped).
- Rules:
  - `ForbiddenDirectiveRule`: files matching a path predicate must not use
    matching URIs.
  - `InternalDependencyRule`: dependency direction between `helix_remote_*`
    packages.
  - `ModuleBoundaryRule`: a server module reaches another module only through
    its `api.dart`.
- `v2PackageDependencies` / `v2PackageRules(pkg)`: the declared v2 package
  graph (plan §6.1), plus the ban on v1 packages (`v1RetiredPackages`).

## How a package uses it

Add it as a `dev_dependency`, then add `test/architecture_test.dart`:

```dart
final files = scanDartSources(Directory.current.path);
final violations = checkAll(files, v2PackageRules('helix_remote_db'));
expect(violations, isEmpty, reason: describeViolations(violations));
```

A new v2 package must be added to `v2PackageDependencies` in the same change
that creates it. Changing an existing edge is an architecture change: it needs
an ADR and a plan change-log entry.
