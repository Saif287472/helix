# Helix Local Data Flow

This document maps the network and data pathways of Helix Local.

## 1. Discovery Flow (mDNS & UDP Broadcast)
```mermaid
sequenceDiagram
    participant Alice (App)
    participant LAN (Multicast)
    participant Bob (App)

    Alice->>LAN: mDNS announce: _helix._tcp.local (fingerprint, suffix)
    Bob->>LAN: mDNS listen
    Note over Bob: Discovers Alice's IP, port, & fingerprint
    Bob-->>Alice: Resolve TCP connection
```

## 2. Secure Session Establishment
```mermaid
sequenceDiagram
    participant Alice (Client)
    participant Bob (Server)

    Alice->>Bob: TCP Connect
    Alice->>Bob: TLS Handshake (Advertises capabilities: file, calls)
    Note over Alice, Bob: Verify certificates pin static fingerprints
    Alice->>Bob: Exch: displayName, deviceSuffix, sessionID
    Note over Alice, Bob: Session marked Active. Messages kept in RAM.
```

## 3. Ephemeral Media / File Flow
- **Private Media**: Split into chunks -> Encoded in CBOR -> Streamed over secure channel -> Reassembled directly in RAM.
- **Files**: Probed (metadata, size) -> Resumed (chunk index) -> Streamed to `.part` file -> User confirms export -> Moved to OS files -> `.part` deleted.
