# Helix Workspace

Helix is a privacy-focused peer-to-peer encrypted messenger family. The codebase is organized as a Dart/Flutter monorepo workspace containing two applications:

- **Helix Local** (`apps/helix_local`): LAN-only, ephemeral, peer-to-peer messenger with local discovery, zero persistence, and real-time audio/video calls.
- **Helix Remote** (`apps/helix_remote`): Cross-network, persistent, end-to-end encrypted (E2EE) messenger.

## Workspace Structure

- `apps/`
  - `helix_local/`: Local app shell (Flutter)
  - `helix_remote/`: Remote app shell (Flutter)
- `packages/`: Shared packages containing protocol, storage, cryptography, calls, and networking logic.
- `tool/`: Workspace tooling (boundary checking, security scanning).

## Development

Get all dependencies and run verification across the workspace:

```powershell
# Get all dependencies
flutter pub get

# Run formatting, analysis, boundaries, secrets, and tests across all packages
.\scripts\verify.ps1
```

To run tests or builds for a specific app, navigate to its directory under `apps/` and use standard flutter commands:

```sh
cd apps/helix_local
flutter test
flutter run
```

