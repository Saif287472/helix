# Data Inventory and Retention Table

| Data Class | Helix Local Lifetime | Helix Local Storage | Helix Remote Lifetime | Helix Remote Storage |
| :--- | :--- | :--- | :--- | :--- |
| **User Name / Nickname** | Until profile reset | Secure storage | Until profile edit/account delete | SQL DB + Server registry |
| **Identity Keys** | Until profile reset/wipe | Secure storage | Until account deletion | Secure storage + Server prekeys |
| **Chat Threads** | Active runtime session only | RAM only | Until user manual deletion | Encrypted SQL DB |
| **Text Messages** | Active runtime session only | RAM only | Until user manual deletion | Local SQLite database; SQLCipher encryption remains BLOCKED |
| **Private Media Cache** | Active runtime session only | RAM only | Cache evicts automatically; server copy until message delete | App cache directory |
| **File Transfers** | Cleaned on transfer complete | `.part` file in app-temp | Persistent object storage until references are gone | Encrypted object payloads plus server metadata |
| **Audit Logs** | Redacted; cleared on close | Memory buffer | Operational retention; account rows deleted on account deletion | Server audit table with redacted IP/user-agent |
| **Contacts List** | Not applicable | Not applicable | Until manually removed | SQL DB + Server sync registry |
| **Device Registers** | Not applicable | Not applicable | Until device revoked | SQL DB + Server registry |
| **Backups** | Not applicable | Not applicable | Until replaced or account deletion | Opaque encrypted payload + version/KDF metadata; server never receives backup key |
| **Abuse Reports** | Not applicable | Not applicable | Until resolved retention policy or account deletion | Reason code + optional context hash; no plaintext evidence |
