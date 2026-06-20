# Incident On-Call Runbooks

Each incident uses the ownership map in `ownership-blast-radius.yaml`, records a
timeline, preserves evidence, and avoids logging secrets or plaintext content.

| Incident | First Response | Owner |
|---|---|---|
| Auth outage | Freeze rollout, check `/health/ready`, inspect auth error rate and token rotation logs | remote-team |
| Sync backlog | Halt rollout, inspect outbox/DLQ, queue depth, realtime reconnects, and cursor gaps | remote-team |
| Corrupt migration | Stop deploy, restore backup, run `quick_check`, compare schema version and migration checksum | remote-team |
| Key/prekey incident | Disable affected device/account operations, rotate exposed server config, preserve crypto evidence | security-team |
| Privacy request failure | Stop deletion/export worker, preserve request ID, verify no plaintext export, notify privacy owner | privacy-team |
| TURN outage | Disable call rollout flag, verify relay health, fall back to documented outage messaging | remote-team |
| Data-loss suspicion | Freeze writes if needed, snapshot DB/object store, compare backup and outbox sequence evidence | incident-commander |
| Security incident | Activate security response, rotate secrets, preserve logs with redaction, block public claims | security-team |

Escalation:

- Critical/High auth, crypto, storage, sync, wipe, deletion, or authorization
  findings block release.
- External communications must not claim independent review, production
  readiness, or full E2EE properties unless the evidence packet contains signed
  review output.
