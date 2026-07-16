# Storage & Wipe

## Intended Behavior

Standard files may be streamed through disk-backed temporary files. Private
media stays RAM-only. Thread wipe removes in-memory thread state and any related
temporary state.

## Invariants

- Per-thread disconnect timers call `wipeThread(threadId)`, never global wipe.
- Private media does not receive a persistent `localFilePath`.
- Standard file `.part` files are cleaned on cancel/failure paths.
- Application wipe and identity reset remove related audit state.

## Failure Handling

- Interrupted file writes remain resumable only when verified bytes are present.
- Failed wipes must surface as errors rather than pretending state is gone.

## Verification

- Auto-wipe tests.
- File transfer resume/cancel/hash tests.
- Manual restart check for private media.
