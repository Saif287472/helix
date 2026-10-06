import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Tables the platform itself owns (schema `platform`). Short-lived tables
/// are UNLOGGED: losing them in a crash only resets rate limits, presence
/// and pending challenges, which is safe, and they cost no WAL.
const platformMigrations = MigrationSet(
  module: 'platform',
  migrations: [Migration(1, 'platform_baseline', _baseline)],
);

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
