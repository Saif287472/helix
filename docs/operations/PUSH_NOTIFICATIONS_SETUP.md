# Push Wake Setup (Helix Remote)

What makes an incoming call ring on a phone whose app is closed.

Without it, the server enqueues a wake notification, finds no push token for
the device, and completes the outbox job silently.
The call reaches a device that never rings, and the caller sees the ring time
out. Nothing errors — which is why it went unnoticed.

Both halves must be configured. Either one alone does nothing.

---

## What the payload carries

Only a wake hint. The v2 server builds a fixed data-only payload (`{t: message|call|call_ended}`
and a call id) in its push provider (`server/lib/src/platform/push/push.dart`), so there is no
content to leak. The
notification exists to bring the app far enough forward to open its own
authenticated connection and fetch the call over the normal path. Google sees
that a device should wake, not what for.

This does add a Google dependency to a privacy-focused product. It is the same
trade Signal makes, and it is a deliberate decision rather than a default: with
no push transport, calls to a closed app cannot ring at all.

---

## 1. Client (Android)

The app is built to run with or without this. When `google-services.json` is
absent, `app/build.gradle.kts` skips the Google Services plugin and
`FirebasePushTokenSource.initialize()` reports push unavailable — the app
behaves exactly as it did before push existed.

1. Create a Firebase project (or use an existing one).
2. Add an Android app to it with package name **`com.helix.remote`** — this
   must match `applicationId` in `app/android/app/build.gradle.kts`.
3. Download `google-services.json` and place it at:
   ```
   helix_remote/app/android/app/google-services.json
   ```
   It is gitignored on purpose: it ties a build to one Firebase project and is
   supplied per deployment.
4. Rebuild. Gradle logs `google-services.json not found …` when it is missing,
   so a silent misplacement is visible in the build output.

Registration is automatic from there: `PushRegistrationService` registers the
token once the runtime can authenticate, re-registers when the SDK rotates it,
and deregisters on sign-out **before** the credentials are purged (the endpoint
is authenticated — afterwards there is no way to reach it).

## 2. Server

Status: updated at Phase X for the v2 server (the v1 `HELIX_REMOTE_FCM_*`
variables and `backend/.env` no longer exist).

Helix Global runs on the user's PC (Caddy + `dart run bin/server.dart` in
`helix_remote/server`), not a VPS or Docker. Set in `helix_remote/server/.env`
(the server loads it itself at startup; process environment variables override
it):

```ini
HELIX_PUSH_PROVIDER=fcm
HELIX_FCM_PROJECT_ID=your-firebase-project-id
HELIX_FCM_SERVICE_ACCOUNT=C:/path/outside/the/repo/fcm-service-account.json
```

With `fcm`, the project ID and the service account are both required: if either
is missing the server refuses to boot (exit 78, naming the variable) rather than
silently dropping wake-ups. With `HELIX_PUSH_PROVIDER=none` (the default) wake-ups
are dropped silently, which is exactly the "call reaches a device that never
rings" failure above, so set it on a real server. There is no static-token
alternative: the server exchanges the service account for short-lived access
tokens itself and refreshes them five minutes early.

`HELIX_FCM_SERVICE_ACCOUNT` accepts a path *or* inline JSON, decided by whether
the value starts with `{`. **Use the path.** The service-account `private_key`
contains embedded newlines, which a one-line `.env` value does not carry
reliably. Keep the key file outside the repository and never commit it. The
Firebase project and key file of the v1 deployment can be reused unchanged.

Restart the server after changing either value; env is read once, at boot.

The key is parsed **before** the server starts listening, so a wrong path or
the wrong kind of credential is reported at startup rather than at the first
missed call. Expect a named error: file not found, invalid JSON, or a missing
`client_email` if an OAuth client key was grabbed by mistake.

## 3. Verify

`GET /v1/health/ready` checks only the database and storage, so v2 has no
`push_ready` flag: nothing on the server tells you a device will ring until you
try one. End to end: sign in on a phone (so it registers a token), force-close
the app, and call it from another device. It should ring. If it does not, look
for dead `messaging.push` or `calls.push` jobs in `/v1/ops/metrics`
(`helix_jobs_dead`) and for token-rejection log lines
(`docs/operations/V2_OPERABILITY.md`, "Jobs").

The push is data-only: `{t: message|call|call_ended}` plus a call id, never
content. The app wakes, fetches and decrypts on its own. A token FCM no longer
knows (HTTP 404) is dropped from the server.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Calls never ring a closed app | `HELIX_PUSH_PROVIDER` is `none` or unset, or the server was not restarted after editing `.env` |
| The server is configured, still no ring | No device has registered a token: the client build has no `google-services.json`, or has not signed in since gaining it |

Note the app has **no iOS target**, so APNs is not wired: the server sends only
`fcm` tokens and ignores other kinds until APNs exists.
