# Integration journeys

These suites use `IntegrationTestWidgetsFlutterBinding`, which drives a **real
app on a real device**. `flutter test integration_test` therefore needs a
connected device or emulator; without one Flutter reports:

```
No supported devices connected.
...
Linux (desktop) • linux  • linux-x64      • Ubuntu 24.04
Chrome (web)    • chrome • web-javascript • Google Chrome
```

The project targets **android** and **windows**, so neither of the platforms a
plain Linux runner offers is usable.

## Why CI does not run these

It used to try. The steps were added with the Phase 8 work and failed on every
run from the day they landed — and because they sat ahead of the coverage
ratchet in the same job, the ratchet was skipped every time too. A step that
has never passed is not coverage; it is a red build that trains people to
ignore the build.

They were removed rather than made to pass, because making them pass honestly
needs two things this repository does not have yet:

1. **An emulator in the job** — `reactivecircus/android-emulator-runner` or
   equivalent, which costs roughly ten minutes of runner time per run.
2. **Journeys worth that time.** What is here today is one pumped widget per
   file. The audit's Phase 8 asks for registration, send/receive, attachment
   round-trip, call setup, backup/restore, and device linking — none of which
   these two files touch.

Until then, `docs/operations/ENTERPRISE_READINESS_AUDIT_2026-08-06.md` records
Phase 8 as partly done, and the substantive end-to-end coverage is
`backend/test/phase4_e2e_harness_test.dart`: twelve scenarios over a real
server with real X3DH, real Ed25519/X25519 keys and real AES-GCM — registration,
send/receive, and multi-device fan-out included. It runs on every CI run because
it needs no device.

## Running them locally

With a device attached or an emulator booted:

```sh
cd helix_remote/app
flutter devices          # confirm one is listed
flutter test integration_test
```

## Adding a real journey

Add the emulator step to the `verify-linux` job in `.github/workflows/ci.yml`
in the same change that adds the journey — not before. A step that runs nothing
is worse than no step, because it reads as coverage in a review.
