# Data Inventory and Retention Table

| Data Class | Helix Local Lifetime | Helix Local Storage | Helix Remote Lifetime | Helix Remote Storage |
| :--- | :--- | :--- | :--- | :--- |
| **User Name / Nickname** | Until profile reset | Secure storage | Until profile edit/account delete | SQL DB + Server registry |
| **Identity Keys** | Until profile reset/wipe | Secure storage | Until account deletion or identity rotation | Secure storage + Server prekeys; password-wrapped identity private key in server `account_passwords` |
| **Chat Threads** | Active runtime session only | RAM only | Until user manual deletion | Encrypted SQL DB |
| **Text Messages** | Active runtime session only | RAM only | Until user manual deletion | Local SQLCipher database |
| **Private Media Cache** | Active runtime session only | RAM only | Cache evicts automatically; server copy until message delete | App cache directory |
| **File Transfers** | Cleaned on transfer complete | `.part` file in app-temp | Server filesystem storage until references are gone | Encrypted blobs on the server's local disk plus server metadata |
| **Audit Logs** | Redacted; cleared on close | Memory buffer | Operational retention; account rows deleted on account deletion | Server audit table with redacted IP/user-agent |
| **Contacts List** | Not applicable | Not applicable | Until manually removed | SQL DB + Server sync registry |
| **Device Registers** | Not applicable | Not applicable | Until device revoked | SQL DB + Server registry |
| **Backups** | Not applicable | Not applicable | Until replaced or account deletion | Opaque encrypted payload + version/KDF metadata; server never receives backup key |
| **Chat History Backup (text only)** | Not applicable | Not applicable | Replaced on each upload; deleted on identity rotation or account deletion | Server `history_backups`: one AES-GCM blob per account, keyed from the identity key; no media |
| **Account Password Verifier** | Not applicable | Not applicable | Until changed, identity rotation, or account deletion | Server `account_passwords`: Argon2id params and salt, salted hash of the derived auth key, failure/lockout counters; the password itself is never sent |
| **Abuse Reports** | Not applicable | Not applicable | Until resolved retention policy or account deletion | Reason code + optional context hash; no plaintext evidence |
