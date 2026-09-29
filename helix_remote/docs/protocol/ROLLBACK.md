# Protocol Split Rollback

> **Status: historical, Helix Local only (June 2026 Stage 3 protocol split).** `helix_protocol` and the root `scripts/verify.ps1` refer to the old root layout; this does not apply to Helix Remote.

Stage 3 is intentionally reversible.

## If The Split Regresses

1. Restore imports to `package:helix_protocol/protocol/protocol_messages.dart`
   and its frame exports.
2. Revert protocol-frame files inside
   `packages/helix_protocol/lib/protocol/`.
3. Keep the `helix_protocol` package boundary intact; do not move protocol
   definitions back under the app shell.
4. Run:

   ```powershell
   .\scripts\verify.ps1
   ```

## Compatibility Requirement

Any rollback or re-application must keep Stage 0 fixtures decodable:

```powershell
flutter test test\protocol_fixtures_test.dart
```
