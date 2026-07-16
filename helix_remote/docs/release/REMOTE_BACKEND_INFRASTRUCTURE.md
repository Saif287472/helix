# Helix Remote Backend Infrastructure & Operations Guide

This document defines the deployment architecture, configuration standards, security scanning, load testing, and operational runbook for the **Helix Remote Backend**.

---

## 1. Staging vs Production Isolation (P10-027, Exit Criteria)

To prevent data leaks, environment pollution, and cross-talk, Staging and Production environments are fully sandboxed.

### Sandboxing Rules
- **No Shared Infrastructure**: Staging and Production run on completely separate hosts/virtual machines with independent virtual private networks (VPCs).
- **Database Separation**: Staging uses a separate database file (e.g., `helix_remote_staging.db`) from Production (`helix_remote_production.db`). 
- **Cryptographic Keys Isolation**: JWT HMAC-SHA256 secrets, signing keys, and WebSocket auth secrets are unique to each environment.
- **Port Mapping**:
  - Staging: Listen port `8081` (internal)
  - Production: Listen port `8080` (internal)

---

## 2. Secret Management & Environment Configuration (P10-028)

Hardcoding secrets in configuration files, source code, or committing them to source control is strictly prohibited.

### Env Variables Configuration
The backend monolith consumes environment variables injected at runtime:
- `HELIX_REMOTE_JWT_SECRET`: Used by the `JwtHelper` to sign and verify session/refresh tokens. Minimum 32 bytes (HMAC-SHA256).
- `HELIX_REMOTE_DB_PATH`: Absolute path to the SQLite storage file (e.g. `/var/lib/helix/db.sqlite`).
- `HELIX_REMOTE_HOST`: Host IP address to bind to (e.g. `127.0.0.1` behind reverse proxy).
- `HELIX_REMOTE_PORT`: Port to listen on (e.g. `8080`).
- `HELIX_REMOTE_DEV_MODE`: Set to `1` only for local development. This permits
  the checked-in development backend command to use the non-secret development
  JWT fallback and local SQLite path.

### Secrets Vault
Production deployments must retrieve variables dynamically at startup using a vault (e.g., AWS Secrets Manager, HashiCorp Vault, or Google Cloud Secret Manager) rather than writing them to persistent disk.

---

## 3. TLS Configuration & Reverse Proxy (P10-029)

The Dart monolithic server must not be exposed directly to the public internet. All public traffic must terminate at a secure reverse proxy (Nginx or Envoy).

The backend entrypoint defaults to `127.0.0.1` so development and reverse-proxy
deployments do not accidentally bind to all interfaces. Binding to a LAN or
public interface must be an explicit operator decision and production still
requires a real `HELIX_REMOTE_JWT_SECRET`.

### Nginx SSL Configuration Checklist
- **TLS Version**: Force TLS 1.3 or TLS 1.2 minimum. Disable TLS 1.0 and 1.1.
- **Cipher Suites**: Enable only secure forward-secret cipher suites:
  ```nginx
  ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
  ssl_prefer_server_ciphers on;
  ```
- **HSTS**: Force HTTP Strict Transport Security:
  ```nginx
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  ```
- **WebSockets Upgrades**: Configure the proxy to pass upgrade headers for real-time channels:
  ```nginx
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "Upgrade";
  ```

---

## 4. Metrics, Logs, and Tracing (P10-030)

Operational observability is critical for monitoring health without compromising user privacy.

### Privacy-Preserving Logging Rules
- **No Ciphertext or Plaintext Content**: Never log ciphertext bytes, decrypted text, attachment content, or user keys.
- **No IP Addresses in Logs**: Anonymize client IP addresses in standard request logging (e.g. mask last octet).
- **Audit Logs**: Store non-sensitive actions (e.g., `DEVICE_LOGIN`, `DEVICE_REVOKED`, `MESSAGE_SENT`) in the SQLite database audit log table with sanitization.

### Observability Stack
- **Metrics**: Export endpoint latency, rate-limiting hits, and database query timings via a Prometheus exporter endpoint.
- **Diagnostics**: Server exits gracefully by flushing memory logs and closing SQLite connections.

---

## 5. Dependency & Container Security Scanning (P10-032)

Automated security checks prevent supply chain attacks and CVE leaks.

### Verification Pipelines
- **Dart Audit**: Runs automatically during code checks via:
  ```powershell
  flutter pub outdated
  ```
- **Container Scanning**: Production images must be scanned during CI/CD using tools like Trivy or Anchore to detect OS/library vulnerabilities before deployment.
- **Code Secrets Scanning**: Automated Git hooks check for high-entropy secret patterns (e.g., JWT secrets, API tokens) before commits.

---

## 6. API Load Test Baseline (P10-033)

Performance benchmarks verify server resilience under heavy load.

### Load Benchmarks
- **Target Baseline**: The monolith must handle 2,000 concurrent WebSocket connections and process 500 message delivery operations per second with latency under 100ms.
- **Testing Tool**: Use `k6` or `Locust` with synthetic client configurations in the Staging environment to run regression load testing.
- **Backpressure Validation**: Ensure that exceeding the mailbox quota (5,000 outstanding messages per device) returns `403 Forbidden` and does not degrade database performance.

---

## 7. Incident Response Runbook (P10-034)

Operational instructions for production anomalies:

### Alerting & Triage

#### Incident: Spike in HTTP 429 Responses
- **Possible Cause**: DDoS attack or aggressive client sync retry loop.
- **Action**: Check IP logs for high volume. Adjust `RateLimiter` values using the reverse proxy if necessary.

#### Incident: High Memory or SQLite DB Locking
- **Possible Cause**: Heavy transactional load or unclosed statements/transactions.
- **Action**: Inspect active database connection handles. Run backup recovery tasks if database file corruption is detected.

#### Incident: Compromised Device Secret / Token Replay
- **Possible Cause**: Leak of user refresh token.
- **Action**: The refresh token rotation engine automatically revokes all sessions on detection of a replayed token. If manually requested, call `db.revokeAllRefreshTokensForDevice` or revoke the device manually.
