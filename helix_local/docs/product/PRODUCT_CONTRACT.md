# Helix Local Product Contract

Helix Local is a highly private, ephemeral, LAN-only communications tool that does not rely on third-party servers.

## 1. Scope and Target
- **Purpose**: Serverless, zero-registry local area network (Wi-Fi, hotspot) voice/video calls, messaging, and file sharing.
- **Audience**: High-privacy LAN communication contexts (corporate offices, field operations, local team coordination).
- **Offline Mode**: Works fully offline. The software has absolutely no remote cloud dependencies.

## 2. Retention & Persistence Policy
- **Chat history**: Stored exclusively in RAM. No messages or threads survive an application restart.
- **Private Media**: Stored in RAM cache only.
- **File Transfers**: Saved to temporary app-private directories during transfer; once accepted and exported by the user, the app retains no records.
- **Audit Logs**: Strictly redacted in memory; logs are cleared upon app close.

## 3. Cryptographic Identity
- **Install-Scoped Keypair**: Generated on first launch.
- **Trust Anchor**: Local fingerprint exchanges via QR codes or manual verification phrases.
- **Key Rotation**: Wiping the app or resetting the profile completely destroys the keys.
