import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Tables the platform itself owns (schema `platform`). Short-lived tables
/// are UNLOGGED: losing them in a crash only resets rate limits, presence
/// and pending challenges, which is safe, and they cost no WAL.
const platformMigrations = MigrationSet(
  module: 'platform',
  migrations: [
    Migration(1, 'platform_baseline', _baseline),
    Migration(2, 'rate_bucket_full_at', _rateBucketFullAt),
    Migration(3, 'jobs_dedupe_live', _jobsDedupeLive),
    Migration(4, 'idempotency_claim', _idempotencyClaim),
    Migration(5, 'ephemeral_key_pattern', _ephemeralKeyPattern),
  ],
);

/// `scan(prefix)` is `key LIKE 'prefix%'`, and Postgres can only use a btree
/// for a prefix `LIKE` when the index is `text_pattern_ops` or the column is
/// `"C"`-collated: the primary key is neither, and this database is created
/// with the host locale, so every scan walked all the live ephemeral rows
/// (AUD-1b-4). Additive: the planner simply gains a choice, and equality
/// lookups keep using the primary key.
String _ephemeralKeyPattern(String s) =>
    '''
CREATE INDEX ephemeral_key_pattern ON $s.ephemeral (key text_pattern_ops);
''';

/// A key is now claimed *before* its handler runs, so a concurrent duplicate
/// is turned away instead of acting twice (AUD-1a-3) and a retry whose answer
/// was lost waits or replays instead of repeating the side effect
/// (AUD-11a-2). `state` says whether a row is a claim or an answer;
/// `taken_at` is when the claim was taken, so a handler that died with its
/// node cannot burn the key past the lease.
///
/// Expand-only, and the default is what every existing row already is: a
/// finished answer. A node still running the old code keeps writing `done`
/// rows it can replay, and one claim row it reads is a status it never
/// answers - so a rolling deploy, or a rollback, costs at most the claim
/// state and never a stored answer or a crash.
String _idempotencyClaim(String s) =>
    '''
ALTER TABLE $s.idempotency
  ADD COLUMN state text NOT NULL DEFAULT 'done' CHECK (state IN ('pending', 'done')),
  ADD COLUMN taken_at timestamptz;
''';

/// Dedupe is a lock on the *pending* job with that key, not on the key
/// forever: a job that ran out of attempts stays as a `dead` row for the
/// operator, and the table-wide `UNIQUE` used to mean that the key was spent
/// for good - one dead `push:call:<device>` or `gdev:<group>:<account>`
/// silenced that wake-up or relay for ever (AUD-1b-1). Both statements are in
/// one migration, so no node can be left with neither constraint nor index;
/// the constraint is dropped rather than kept for a release because keeping it
/// keeps the bug.
String _jobsDedupeLive(String s) =>
    '''
ALTER TABLE $s.jobs DROP CONSTRAINT jobs_dedupe_key_key;
CREATE UNIQUE INDEX jobs_dedupe_live ON $s.jobs (dedupe_key)
  WHERE dedupe_key IS NOT NULL AND status = 'pending';
''';

/// When a bucket is certainly full again (one policy window after its last
/// hit), so the sweep drops it then and not after a fixed hour: an hour reset
/// a day-long budget (the SMS budget, groups created, distinct people read)
/// to full whenever its key paused for an hour. The default fills existing
/// rows (and any writer that does not set it) with "now", the old reset.
String _rateBucketFullAt(String s) =>
    '''
ALTER TABLE $s.rate_buckets ADD COLUMN full_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX rate_buckets_full ON $s.rate_buckets (full_at);
DROP INDEX $s.rate_buckets_updated;
''';

String _baseline(String s) =>
    '''
CREATE UNLOGGED TABLE $s.ephemeral (
  key text PRIMARY KEY,
  value text NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE INDEX ephemeral_expires ON $s.ephemeral (expires_at);

CREATE UNLOGGED TABLE $s.rate_buckets (
  key text PRIMARY KEY,
  tokens double precision NOT NULL,
  updated_at timestamptz NOT NULL,
  allowed boolean NOT NULL
);
CREATE INDEX rate_buckets_updated ON $s.rate_buckets (updated_at);

CREATE TABLE $s.jobs (
  id uuid PRIMARY KEY,
  kind text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'dead')),
  run_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL,
  locked_until timestamptz,
  locked_by text,
  last_error text,
  dedupe_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX jobs_ready ON $s.jobs (run_at) WHERE status = 'pending';

CREATE TABLE $s.periodic_jobs (
  name text PRIMARY KEY,
  last_run_at timestamptz,
  locked_until timestamptz,
  locked_by text
);

CREATE TABLE $s.idempotency (
  principal text NOT NULL,
  key text NOT NULL,
  request_hash text NOT NULL,
  status integer NOT NULL,
  response text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (principal, key)
);
CREATE INDEX idempotency_created ON $s.idempotency (created_at);
''';
