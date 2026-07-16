# File Transfer

## Intended Behavior

Standard files stream from/to disk through bounded protocol frames. Private media
uses the ephemeral media path and remains RAM-only.

## Invariants

- File IDs and message IDs are separate.
- Probe/resume/complete/cancel states are explicit.
- Resume uses verified byte offset.
- Completion verifies SHA-256 before finalizing.
- Cancel cleans temporary state on both peers.

## Failure Handling

- Hash mismatch marks transfer failed and removes unsafe output.
- Missing partial data resumes from offset zero.
- Disk quota failures stop the transfer cleanly.

## Verification

- `test/phase0_test.dart`
- Protocol fixture tests for file frames.
- Large-file interrupt/resume manual check before release.
