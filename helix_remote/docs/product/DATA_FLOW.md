# Helix Remote Data Flow

Status: rewritten at Phase X (2026-10) for the v2 server. Routes are from the route catalog
(`packages/helix_remote_protocol/lib/src/routes.dart`); the formats are in
`docs/protocol/v2/` (REST_V2, REALTIME_V2, CONTENT_V2, CRYPTO_V2). What the server keeps is in
`METADATA_INVENTORY.md`.

This document maps the network and data pathways of Helix Remote.

## 1. Registration and session

```mermaid
sequenceDiagram
    participant Client (App)
    participant Server (REST)
    participant DB (Postgres)

    Client->>Server: POST /v1/auth/phone/challenges (phone number)
    Server->>SMS gateway: Send the code (the number is not stored)
    Client->>Server: POST /v1/auth/phone/verify (challenge, code)
    Server-->>Client: Single-use verification token
    Client->>Server: POST /v1/auth/register (verification token, terms version, account identity key, device keys, AIK-signed device certificate, proof of the device key)
    Server->>DB: Store account (phone hash), device, hashed refresh token
    Server-->>Client: Access token (15 minutes) + refresh token (60 days, rotated on every use)
    Client->>Server: PUT /v1/keys/signed-prekey, POST /v1/keys/one-time-prekeys
    Note over Client: Optional: set a password (POST /v1/account/password)
```

The raw phone number reaches the server only in the code request, where it is hashed and
forwarded to the SMS gateway. A personal server registers by invite instead of by SMS.

## 1a. Password sign-in on another device

```mermaid
sequenceDiagram
    participant New device
    participant Server (REST)
    participant Other devices

    New device->>Server: POST /v1/auth/password/params (phone number)
    Server-->>New device: Argon2id salt and cost (decoys for unknown numbers)
    Note over New device: Argon2id + HKDF -> auth key, wrap key
    New device->>Server: POST /v1/auth/password/sign-in (auth key, device keys, certificate)
    Server-->>New device: Session + the password-wrapped identity key
    Server->>Other devices: security event + device_list_change signal
    Note over New device: Unwraps the identity key with the wrap key
    New device->>Server: GET /v1/backups/history
    Note over New device: Decrypts and restores the text history
```

QR linking is the other way to add a device: the new device shows a code, an existing device
approves it (`POST /v1/devices/links/{link_id}/approve`), and the provisioning data travels
through the server sealed.

## 2. End-to-end encrypted messaging

```mermaid
sequenceDiagram
    participant Alice
    participant Server (REST + WebSocket)
    participant Object storage
    participant Bob (offline or online)

    Alice->>Server: GET /v1/keys/{bob} (once, to start a session)
    Note over Alice: Encrypts any file with a random key K and uploads the ciphertext
    Alice->>Object storage: PUT /v1/media/{id}/content (or a presigned PUT)
    Note over Alice: One sealed envelope per recipient device and per own other device
    Alice->>Server: POST /v1/messages (envelopes, idempotency key, device list)
    Note over Server: Stale device list: 409 device_list_stale. Otherwise one mailbox row per device
    Server-->>Bob: Live frame on the WebSocket, or a data-only push wake-up
    Bob->>Server: GET /v1/mailbox (or the socket replay)
    Note over Bob: Decrypts once into local rows; downloads and decrypts the attachment with K
    Bob->>Server: POST /v1/mailbox/ack (cumulative)
    Note over Server: Deletes the acknowledged mailbox rows
```

Reactions, receipts, edits, deletes, replies, typing, view-once and disappearing timers travel
as encrypted content inside the same envelopes, so the server cannot tell them from messages.
Group messages use Sender Keys: a sender key is distributed over the pairwise sessions, then
`POST /v1/groups/{group_id}/messages` sends one ciphertext that the server fans out per member
device.

## 3. Calls

```mermaid
sequenceDiagram
    participant Caller
    participant Server
    participant Callee (offline or online)
    participant coturn

    Caller->>Server: GET /v1/calls/turn
    Server-->>Caller: Time-limited TURN credentials (HMAC of the shared secret)
    Caller->>Server: POST /v1/calls/{id}/signals (sealed offer, one per callee device)
    Server-->>Callee: Live call_signal, or a pending call plus a call push
    Callee->>Server: POST /v1/calls/{id}/signals (sealed answer, ICE)
    Caller->>coturn: Relayed, DTLS-SRTP encrypted media (relay-only)
```
