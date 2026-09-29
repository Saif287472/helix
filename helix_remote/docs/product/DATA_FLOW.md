# Helix Remote Data Flow

This document maps the network and data pathways of Helix Remote.

## 1. Registration & Session Sync
```mermaid
sequenceDiagram
    participant Client (App)
    participant Server (REST)
    participant DB (SQLite)

    Client->>Server: POST /api/v1/accounts/phone/otp/request (phone_hash, phone_number)
    Server->>SMS gateway: Send code to phone_number (not stored)
    Client->>Server: POST /api/v1/accounts/register (phone_hash, otp_code, invite_code on personal servers, identity + device public keys, signatures)
    Server->>DB: Store account, device, hashed refresh token
    Server-->>Client: Access token (1 h) + refresh token (60 days, rotated on refresh)
    Client->>Server: POST /api/v1/accounts/password (Argon2id params/salt, auth_key, wrapped_identity_key)
    Server->>DB: Store salted hash of auth_key + wrapped identity key
    Client->>Server: POST /api/v1/prekeys/publish (signed prekey, one-time prekeys)
```

Every account must set a password before using the app. The raw phone number
reaches the server only in the OTP request and is forwarded to the SMS gateway.

## 1a. Password Sign-In On Another Device
```mermaid
sequenceDiagram
    participant New device
    participant Server (REST)
    participant Other devices

    New device->>Server: POST /api/v1/accounts/password/params (phone_hash)
    Server-->>New device: Argon2id salt + cost
    Note over New device: Argon2id + HKDF -> auth_key, wrap_key
    New device->>Server: POST /api/v1/accounts/password/login (phone_hash, auth_key, device keys, signature)
    Server-->>New device: Session + wrapped_identity_key
    Server->>Other devices: device event + new_sign_in push
    Note over New device: Unwraps identity key with wrap_key
    New device->>Server: GET /api/v1/backups/history
    Note over New device: Decrypts and merges text history
```

## 2. E2EE Messaging Flow
```mermaid
sequenceDiagram
    participant Alice
    participant Server (WebSocket)
    participant Local Storage
    participant Bob (Offline/Online)

    Note over Alice: Encrypts file with random key K
    Alice->>Local Storage: Upload encrypted payload
    Alice->>Server: Send envelope (to: Bob, storage link, ciphertext encrypted with K)
    Note over Server: Purges envelope upon Bob delivery acknowledgment
    Server->>Bob: Forward envelope
    Note over Bob: Decrypts envelope, downloads attachment, decrypts payload with K
```
