# Backend load testing

Run the checked-in smoke harness against staging before a release:

```bash
cd helix_remote/backend
dart run tool/load_smoke.dart --url=https://staging.example/health --clients=32 --requests=20 --max-p95-ms=1000
```

Record the emitted request count, client concurrency, failures, p50, and p95 in the release evidence. Increase `--clients` until the p95 budget or error-rate budget fails; the highest preceding successful value is the current documented SQLite concurrency ceiling.

The harness contains no credentials. Authenticated send/receive and attachment workloads belong in the protected staging runner, using its ephemeral test accounts.
