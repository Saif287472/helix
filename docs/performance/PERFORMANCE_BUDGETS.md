# Helix Performance Budgets and Baseline Measurements

**Phase:** 10 — Performance, scalability, observability, and backend evolution  
**Created:** 2026-06-20  
**Policy:** No performance-sensitive change is accepted without before/after evidence against these budgets.

---

## 1. Client performance budgets

### 1.1 Startup and navigation

| Metric | Budget | Measurement method |
|---|---|---|
| Cold start to usable Home (Local, Android release) | ≤ 2 500 ms | Flutter DevTools timeline; frame render trace |
| Cold start to usable Home (Remote, Android release) | ≤ 3 000 ms | Flutter DevTools timeline |
| Warm start (app foregrounded) | ≤ 800 ms | DevTools timeline, frame begin to first paint |
| Time to first synced state (Remote, WiFi) | ≤ 4 000 ms | `RemoteRuntimeCoordinator` `ready` event timestamp |
| Navigation route transition frame time | ≤ 16 ms (p99) | Flutter frame timing |

### 1.2 Message list scroll performance

| Metric | Budget | Measurement method |
|---|---|---|
| List frame time at 100 messages | ≤ 16 ms (p99) | `flutter drive --profile` with custom driver |
| List frame time at 1 000 messages | ≤ 16 ms (p99) | Same driver with seeded DB |
| List frame time at 10 000 messages | ≤ 20 ms (p99) | Benchmark with `Helix10kScrollBenchmark` |
| Jank frame rate (> 16 ms) at 1 000 messages | ≤ 1 % | Flutter frame timing |

### 1.3 Cryptographic operations

| Metric | Budget | Measurement method |
|---|---|---|
| X3DH initiate (main isolate) | ≤ 50 ms | `HelixIsolateCompute.benchmark()` |
| X3DH initiate (worker isolate via `HelixIsolateCompute`) | ≤ 50 ms | Same |
| AES-GCM encrypt 1 MB attachment chunk | ≤ 100 ms | `HelixIsolateCompute.benchmark()` |
| PBKDF2 key derive (backup KDF) | ≤ 500 ms | `HelixIsolateCompute.benchmark()` |
| DB export serialization, 10 MB | ≤ 1 000 ms | Isolated benchmark |

### 1.4 Memory

| Metric | Budget | Measurement method |
|---|---|---|
| Idle (home screen, no open chat) | ≤ 80 MB RSS | `flutter run --profile` memory chart |
| Active chat (1 000 messages in view) | ≤ 120 MB RSS | Memory chart + custom driver |
| Active call (audio only) | ≤ 150 MB RSS | Memory chart during call |
| Large file transfer (100 MB) | ≤ 200 MB RSS peak | Memory chart during transfer |
| Memory growth per 1 000 navigations | ≤ 5 MB | Leak-detection driver |

### 1.5 Network and battery

| Metric | Budget | Measurement method |
|---|---|---|
| Message send-to-local-ack (WiFi) | ≤ 300 ms | Instrumented timestamp in `RemoteRuntimeCoordinator` |
| Message send-to-delivery (WiFi, both online) | ≤ 1 000 ms | E2E test with event timestamps |
| WebSocket reconnect time after 10 s gap | ≤ 5 000 ms | `RemoteRuntimeCoordinator` reconnect test |
| Battery drain idle background (Android) | ≤ 2 % per hour | Android Battery Historian |
| Mobile data usage per 1 000 messages (text) | ≤ 500 KB | Network profiler |

### 1.6 Package size

| Metric | Budget | Measurement method |
|---|---|---|
| Local APK (release, arm64) | ≤ 25 MB | `flutter build apk --release --target-platform android-arm64` |
| Remote APK (release, arm64) | ≤ 15 MB | Same |
| Local Windows MSIX/installer | ≤ 40 MB | `flutter build windows --release` |
| Asset bundle (sounds + wordlist + logo) | ≤ 10 MB | `tool/check_asset_sizes.dart` |

---

## 2. Backend performance budgets (SLO targets)

### 2.1 API latency (per-endpoint p-values, 100 concurrent clients)

| Endpoint | p50 | p95 | p99 |
|---|---|---|---|
| POST /api/v1/accounts/register | ≤ 100 ms | ≤ 300 ms | ≤ 500 ms |
| POST /api/v1/accounts/login | ≤ 80 ms | ≤ 200 ms | ≤ 400 ms |
| GET /api/v1/messages | ≤ 50 ms | ≤ 150 ms | ≤ 300 ms |
| POST /api/v1/messages | ≤ 80 ms | ≤ 200 ms | ≤ 400 ms |
| GET /api/v1/attachments/:id (cache hit) | ≤ 30 ms | ≤ 100 ms | ≤ 200 ms |
| POST /api/v1/attachments (10 MB upload) | ≤ 500 ms | ≤ 2 000 ms | ≤ 5 000 ms |
| GET /api/v1/health/ready | ≤ 10 ms | ≤ 30 ms | ≤ 50 ms |

### 2.2 Throughput targets (single-node SQLite)

| Metric | Target |
|---|---|
| Concurrent WebSocket connections | ≥ 500 |
| Message enqueues per second | ≥ 200 |
| Outbox drain events per second | ≥ 50 |
| Concurrent REST requests (p99 ≤ 400 ms) | ≥ 100 |

### 2.3 Backend reliability

| Metric | Target |
|---|---|
| Monthly availability | ≥ 99.5 % |
| 5-minute API success rate | ≥ 99.0 % |
| Outbox DLQ items at any time | 0 (alert at > 10) |
| Push outbox age p95 | ≤ 30 s |
| DB quick_check failure | Immediate alert + restart |

### 2.4 Disaster recovery

| Metric | Target |
|---|---|
| Recovery point objective (RPO) | ≤ 24 h (daily backup) |
| Recovery time objective (RTO) | ≤ 2 h (restore + verify) |
| Backup restore drill frequency | Monthly |
| Migration rollback time | ≤ 30 min |

---

## 3. Baseline measurements

Baselines must be re-recorded after every release candidate using the commands below.  
**Baseline not yet recorded** — first measurement required before optimization work begins.

### 3.1 How to record baselines

> Status (2026-09): the June commands (`apps/helix_local`, `apps/helix_remote`,
> `tool/benchmark_baseline.dart`, `tool/check_asset_sizes.dart`,
> `phase10_pagination_test.dart`, `phase10_remote_bench_test.dart`,
> `docs/performance/baselines/`) were never built or no longer exist. What
> actually exists today, run from `helix_remote/`:

```powershell
# Budget contract check (CI job `performance-budgets`): verifies the metric
# names in this file are still present
dart tool/check_performance_budgets.dart

# Message-list burst budget on the CI reference runner (CI job `performance-budgets`)
flutter test app/test/phase4_performance_budget_test.dart

# Isolate compute and backend scalability tests
flutter test app/test/phase10_isolate_compute_test.dart
cd backend; dart test test/phase10_scalability_test.dart; cd ..

# Backend load smoke (see helix_remote/docs/operations/LOAD_TESTING.md)
cd backend; dart run tool/load_smoke.dart --url=http://127.0.0.1:8080/api/v1/health/ready --clients=32 --requests=20 --max-p95-ms=1000
```

There is no baseline recorder and no asset-size checker; record results by hand
in the table below. Helix Local has no benchmark tooling in `helix_local/`.

### 3.2 Recorded baselines

| Date | Commit | Local startup | Remote startup | APK size | Notes |
|---|---|---|---|---|---|
| *(not yet recorded)* | — | — | — | — | First baseline pending CI integration |

---

## 4. Budget enforcement

### 4.1 CI gates

> Status (2026-09): only `dart tool/check_performance_budgets.dart` and
> `app/test/phase4_performance_budget_test.dart` run in CI (job
> `performance-budgets` in `.github/workflows/ci.yml`). The other rows name
> tools and tests that do not exist yet.

| Gate | Failure action |
|---|---|
| `tool/check_asset_sizes.dart` exceeds budget | PR blocked |
| Backend unit test latency regression > 2× | PR flagged |
| Frame time regression in `phase10_pagination_test.dart` | PR flagged |
| DLQ count > 0 in `phase10_dr_drill_test.dart` | PR blocked |

### 4.2 Release gates

Before tagging a release (items naming `check_asset_sizes.dart` or
`phase10_dr_drill_test.dart` need those tools written first):

- [ ] All client startup budgets met on physical Android device (release build).
- [ ] All backend p50/p95/p99 budgets met under the load tool with 100 clients.
- [ ] `check_asset_sizes.dart` reports total asset bundle ≤ 10 MB.
- [ ] DR drill completed within RTO/RPO.
- [ ] Memory leak test shows ≤ 5 MB growth per 1 000 navigations.
- [ ] No DLQ items after reconnect-storm drill (`phase10_dr_drill_test.dart`).
