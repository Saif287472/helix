# Helix Local Threat Model

## 1. Trust Assumptions
- The local network (Wi-Fi/hotspot) is assumed hostile. Sniffing and packet injection are active threats.
- Nearby devices are untrusted until authenticated.
- Peer verification relies on direct out-of-band fingerprint exchange (QR, verification phrase).

## 2. Threat Scopes & Mitigation Strategies

### T-1: Passive LAN Sniffing
- **Description**: Adversaries capturing raw network packets on the shared Wi-Fi network.
- **Mitigation**: All communications use TLS (for control/signaling) and DTLS-SRTP (for calls). Static fingerprints anchor identity.

### T-2: Active LAN Impersonation (MitM)
- **Description**: Malicious node claiming to be a trusted peer.
- **Mitigation**: TLS certificate validation pins the peer's static key fingerprint. Verification phrases reveal mismatches.

### T-3: Physical Device Capture
- **Description**: Adversary gaining physical access to a user's device.
- **Mitigation**: Zero message history resides on disk. Biometric application lock blocks raw UI access. Panic wipe destroys identity keys.

### T-4: Forensic File Analysis
- **Description**: Extracting remnants of deleted chats from flash storage.
- **Mitigation**: Chat contents never touch SQLite. SQLite journal is kept in WAL mode and fully truncated.
