# Connection Handshake & Approval

## Intended Behavior

Incoming requests create pending approval cards. Accepted requests establish a
secure channel and attach it to messaging/session state.

## Invariants

- Duplicate pending requests from the same peer replace the older pending card.
- Request approval is explicit unless a future trusted-auto-accept rule is
  documented.
- Secure channel identity exchange occurs before trusted messaging.
- Rejections and cancels are terminal for that request ID.

## Failure Handling

- Busy, rejected, canceled, and version-mismatch states must be visible to the
  caller.
- Failed handshakes clean up partial session state.

## Verification

- `test/request_channel_integration_test.dart`
- Protocol fixture tests for request/accept/reject/cancel frames.
