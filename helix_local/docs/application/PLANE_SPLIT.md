# Control, Transfer, and Media Planes

Status: Stage 5 foundation.

## Control Plane

TCP/TLS plus CBOR carries handshakes, chat signaling, receipts, group state, and
future call signaling.

## Transfer Plane

Standard files and resumable chunks should move toward dedicated transfer
gateways/coordinators. Stage 4 keeps frame I/O separate so this can happen
without changing protocol DTOs.

## Media Plane

Future Phase 5 calls use WebRTC only for media. Signaling remains on the
authenticated control plane.
