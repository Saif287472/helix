# ADR 022: Production hardening boundaries

Status: accepted (2026-08-07)

## Decision

Helix Remote uses a single-host SQLite deployment as its supported production
baseline until a measured capacity threshold requires the existing Postgres
adapter. The backend rate limiter stores buckets in SQLite with transactional
updates, so throttling survives restart and is shared by every process using
that database. Deployments must remain one host/database writer; they must not
pretend a replicated SQLite volume is a multi-region database.

The capacity ceiling is enforced operationally: one backend host, one SQLite
database volume, and no more than four backend worker processes. Crossing that
ceiling, or observing message-enqueue p95 above 500 ms in the documented load
smoke, requires a Postgres migration ADR, staging rehearsal, and rollback plan
before adding capacity. This is deliberately a conservative ceiling, not an
unverified throughput claim.

JWT rotation uses a JSON key ring and one active `kid`. During the overlap,
verification accepts both the retiring and active keys; only the active key
signs new tokens. Retire a key only after the maximum access/refresh lifetime.

Admin credentials are 12-hour, rotatable, `ops:*` paired credentials. The
issuance ceremony requires a loopback-only terminal action plus a single-use,
10-minute pairing code. `HELIX_REMOTE_ADMIN_TOKEN` remains an explicitly
audited emergency break-glass override and must be removed after recovery.

Feature flags are server-owned, allow-listed, audited through the admin API,
and default off. They are not a permission system.

## Telemetry and diagnostics

Crash reporting and minimal analytics are opt-in and off by default. The app
produces a very small, redacted event envelope only after a user selects a
future consent UI; current builds do not ship an uploader or third-party SDK.
The supported diagnostic path is the existing locally stored, redacted anomaly
log that the user chooses to export. This avoids silently exporting device,
message, contact, token, or network metadata while preserving an actionable
support route.

Certificate validation stays strict for all Remote hosts. Helix Global pin
rotation is owned with the TLS deployment. Android release builds pin the
current Helix Global SPKI in the network-security configuration; the next
release must contain the current and next pins before a certificate key change,
then retain the old pin through the adoption overlap. Windows currently uses
the Dart runtime's strict CA validation because its HTTP client does not expose
the negotiated peer certificate for equivalent post-handshake pinning. A
native Windows transport pinning implementation is therefore a release gate
before treating Windows as pin-enforced.

REST requests propagate a bounded `X-Correlation-Id` from client to backend
and back in the response. The backend replaces malformed values and includes
the result in request logs; this is tracing metadata, never a user identifier.

## Supply chain and release artifacts

CI emits a resolved CycloneDX SBOM and scans dependency lockfiles against OSV.
Android release builds enable R8/minification and resource shrinking. The
release gate requires Dart obfuscation and preserves per-platform symbol maps
next to the build artifacts; those maps are release-sensitive operational
material and must be retained with the release record.

## Consequences

This decision gives a small deployment safe restart behavior and key rotation
without claiming distributed scale it does not have. A future Postgres/Redis
deployment must replace the SQLite rate-limit store atomically and document
its own failure/recovery behavior.
