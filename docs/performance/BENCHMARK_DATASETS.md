# Phase 10 Benchmark Datasets

The Phase 10 benchmark suite uses deterministic seed names instead of
production-derived content. Generated rows must use opaque ciphertext markers
and synthetic account/device IDs only.

| Dataset | Rows | Purpose |
|---|---:|---|
| `remote_messages_10k` | 10,000 messages | Scroll, pagination, query-plan, and sync cursor timing |
| `remote_messages_100k` | 100,000 messages | Large-mailbox soak and memory ceiling checks |
| `remote_outbox_10k` | 10,000 queue entries | Retention purge, queue-depth metrics, and DLQ alert tests |
| `remote_attachments_1k` | 1,000 metadata rows | Object-store outage and attachment listing checks |

Seed policy:

- Use stable IDs such as `acct_bench_0001`, `dev_bench_0001`, and
  `msg_bench_000001`.
- Use ciphertext placeholders such as `ciphertext_bench_<n>`; never copy real
  message text, filenames, tokens, private keys, or fingerprints into fixtures.
- Record every baseline with `tool/benchmark_baseline.dart` and commit only the
  summarized artifact needed for release comparison.
