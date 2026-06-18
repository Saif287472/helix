# Protocol Compatibility Matrix

Status: Stage 3 baseline.

Stage 3 moves protocol code into `lib/protocol/` without changing the wire
format. Current protocol version remains `2.2`.

## Version 2.2 Frames

| Type | Hex | Frame | Required behavior |
|---|---:|---|---|
| request | `0x01` | `RequestFrame` | Required |
| accept | `0x02` | `AcceptFrame` | Required |
| reject | `0x03` | `RejectFrame` | Required |
| cancel | `0x04` | `CancelFrame` | Required |
| identity | `0x05` | `IdentityFrame` | Required |
| identity_ack | `0x06` | `IdentityAckFrame` | Required |
| capability | `0x07` | `CapabilityFrame` | Required |
| chat_message | `0x08` | `ChatMessageFrame` | Required |
| chat_ack | `0x09` | `ChatAckFrame` | Optional |
| keepalive | `0x0A` | `KeepaliveFrame` | Required |
| close | `0x0B` | `CloseFrame` | Required |
| profile_update | `0x0C` | `ProfileUpdateFrame` | Optional |
| busy | `0x0D` | `BusyFrame` | Required |
| version_mismatch | `0x0E` | `VersionMismatchFrame` | Required |
| typing_indicator | `0x10` | `TypingIndicatorFrame` | Optional |
| read_receipt | `0x11` | `ReadReceiptFrame` | Optional |
| reaction | `0x12` | `ReactionFrame` | Optional |
| file_transfer | `0x13` | `FileTransferFrame` | Capability-gated |
| edit_message | `0x14` | `EditMessageFrame` | Optional |
| delete_message | `0x15` | `DeleteMessageFrame` | Optional |
| wipe | `0x16` | `WipeFrame` | Required |
| file_probe | `0x17` | `FileProbeFrame` | Capability-gated |
| file_resume | `0x18` | `FileResumeFrame` | Capability-gated |
| file_complete | `0x19` | `FileCompleteFrame` | Capability-gated |
| file_cancel | `0x1A` | `FileCancelFrame` | Capability-gated |
| ephemeral_media | `0x1B` | `EphemeralMediaFrame` | Capability-gated |
| group_control | `0x1C` | `GroupControlFrame` | Capability-gated |
| group_message | `0x1D` | `GroupMessageFrame` | Capability-gated |

## Unknown-Frame Behavior

- Unknown optional frames may be ignored only after a redacted diagnostic event
  exists for that path.
- Unknown required or critical frames must reject the operation/session with a
  protocol error.
- Current legacy decoder fails closed on unknown frame type with
  `ProtocolException`.

## Upgrade Policy

- Bump minor for backward-compatible optional frame additions.
- Bump major for incompatible decoding or semantic changes.
- Envelope support requires capability negotiation and a dual-codec migration.
