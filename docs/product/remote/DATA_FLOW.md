# Helix Remote Data Flow

This document maps the network and data pathways of Helix Remote.

## 1. Registration & Session Sync
```mermaid
sequenceDiagram
    participant Client (App)
    participant Server (REST)
    participant DB (PostgreSQL)

    Client->>Server: POST /auth/register (username, identity keys)
    Server->>DB: Store credentials & public prekeys
    Server-->>Client: Auth token (JWT)
```

## 2. E2EE Messaging Flow
```mermaid
sequenceDiagram
    participant Alice
    participant Server (WebSocket)
    participant S3 Storage
    participant Bob (Offline/Online)

    Note over Alice: Encrypts file with random key K
    Alice->>S3 Storage: Upload encrypted payload
    Alice->>Server: Send envelope (to: Bob, S3 link, ciphertext encrypted with K)
    Note over Server: Purges envelope upon Bob delivery acknowledgment
    Server->>Bob: Forward envelope
    Note over Bob: Decrypts envelope, downloads attachment from S3, decrypts payload with K
```
