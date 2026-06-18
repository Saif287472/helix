# Rollback Phase 2 - Workspace Restructuring

This document describes how to reverse the Phase 2 monorepo workspace restructuring and restore the codebase back to the single-app root configuration if needed.

## Rollback Steps

### 1. Revert Git Workspace Commit
If you have not committed other changes on top, the easiest rollback is to perform a git reset or checkout:
```powershell
git reset --hard baseline
```

### 2. Manual Directory Restoration (Without Git Reset)
If you need to manually move files back:

1. Move all folders under `apps/helix_local/` back to the repository root:
   ```powershell
   Move-Item -Path apps/helix_local/lib -Destination .
   Move-Item -Path apps/helix_local/test -Destination .
   Move-Item -Path apps/helix_local/android -Destination .
   Move-Item -Path apps/helix_local/windows -Destination .
   Move-Item -Path apps/helix_local/assets -Destination .
   ```

2. Revert the root `pubspec.yaml` to the original application configuration:
   - Copy `apps/helix_local/pubspec.yaml` to the root `pubspec.yaml`.
   - Update path dependencies in the root `pubspec.yaml` to remove one level of parent folder traversal (i.e., replace `../../packages/` with `packages/`).

3. Remove the workspace subdirectories:
   ```powershell
   Remove-Item -Recurse -Force apps/
   ```

4. Restore verification paths in `scripts/verify.ps1`:
   - Change `flutter test` command to run at root: `flutter test`
   - Change formatting targets back if needed.
