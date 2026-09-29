# Push Wake Setup (Helix Remote)

What makes an incoming call ring on a phone whose app is closed.

Without it, the server enqueues a wake notification, finds no push token for
the device, and completes the outbox entry silently (`outbox_worker.dart`).
The call reaches a device that never rings, and the caller sees the ring time
out. Nothing errors — which is why it went unnoticed.

Both halves must be configured. Either one alone does nothing.

---

## What the payload carries

Only a wake hint. `enqueueOutbox` **rejects** payloads containing content keys
(`plaintext`, `message_text`, `body`, …) — there is a test for it. The
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

Helix Global runs on the user's PC (Caddy + `dart run bin/server.dart` in
`helix_remote/backend`), not a VPS or Docker. Set in
`helix_remote/backend/.env` (the server loads it itself at startup; process
environment variables override it):

```ini
HELIX_REMOTE_FCM_PROJECT_ID=your-firebase-project-id
HELIX_REMOTE_FCM_SERVICE_ACCOUNT=C:/path/outside/the/repo/fcm-service-account.json
```

The project ID plus **exactly one** credential is an all-or-nothing group: set
the project ID alone and the server refuses to boot (`startup_env.dart`),
deliberately.

**Use the service account, not `HELIX_REMOTE_FCM_ACCESS_TOKEN`.** A static
access token expires after an hour and this server cannot renew it — it prints
that warning itself at startup. The token variable exists for local testing.

`HELIX_REMOTE_FCM_SERVICE_ACCOUNT` accepts a path *or* inline JSON, decided by
whether the value starts with `{` (`readFcmServiceAccount` in
`backend/lib/src/fcm_access_token.dart`). **Use the path.** The
service-account `private_key` contains embedded newlines, which a one-line
`.env` value does not carry reliably. Keep the key file outside the repository
and never commit it.

Restart the backend after changing either value; env is read once, at boot.
(`docker-compose.yml` and a `secrets/` bind mount are only for a Docker
deployment, which is not what Helix Global uses.)

The key is parsed **before** the server starts listening, so a wrong path or
the wrong kind of credential is reported at startup rather than at the first
missed call. Expect a named error: file not found, invalid JSON, or
`missing "client_email" — is this a service account key file?` if an OAuth
client key was grabbed by mistake.

## 3. Verify

```sh
curl -s https://<host>/api/v1/health/ready | python3 -m json.tool | grep push
```

`"push_ready": true` means the *server* is configured. It does **not** mean any
device has registered — that requires a client build with
`google-services.json` that has signed in at least once.

End to end: sign in on a phone, force-close the app, and call it from another
device. It should ring.

The same push path carries the other wake hints the backend enqueues:
`new_message`, `group_invite`, and `new_sign_in` (sent to an account's other
devices when a new device signs in; it carries no device name).

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `push_ready: false` | Server env not set, or the backend was not restarted after editing `.env` |
| `push_ready: true`, still no ring | No device has registered a token — client build has no `google-services.json`, or has not signed in since gaining it |
| Server refuses to boot | Project ID set without a credential, or the key path is wrong. The startup error names which |
| Gradle logs "google-services.json not found" | The file is missing or in the wrong directory — it belongs in `app/android/app/`, not `app/android/` |

Note the app has **no iOS target**, so APNs is not wired. The server accepts
`token_type: APNS` already; the client work does not exist.
