import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Schema `identity`. Foreign keys only inside this schema (ADR-026).
const identityMigrations = [Migration(1, 'identity_baseline', _baseline)];

String _baseline(String s) =>
    '''
CREATE TABLE $s.accounts (
  id uuid PRIMARY KEY,
  identity_key bytea NOT NULL,
  identity_key_changed_at timestamptz,
  phone_hash bytea UNIQUE,
  discovery_hash text UNIQUE,
  phone_last4 text,
  helix_name text UNIQUE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.devices (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES $s.accounts (id) ON DELETE CASCADE,
  name text NOT NULL,
  platform text NOT NULL,
  identity_key bytea NOT NULL,
  signing_key bytea NOT NULL,
  certificate bytea NOT NULL,
  certificate_created_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  tokens_valid_after timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_on date,
  revoked_at timestamptz,
  revoke_reason text
);
CREATE INDEX devices_active ON $s.devices (account_id) WHERE status = 'active';

CREATE TABLE $s.push_tokens (
  device_id uuid PRIMARY KEY REFERENCES $s.devices (id) ON DELETE CASCADE,
  kind text NOT NULL,
  token text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.refresh_tokens (
  id uuid PRIMARY KEY,
  device_id uuid NOT NULL REFERENCES $s.devices (id) ON DELETE CASCADE,
  secret_hash bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  revoked_at timestamptz
);
CREATE INDEX refresh_tokens_device ON $s.refresh_tokens (device_id);
CREATE INDEX refresh_tokens_expires ON $s.refresh_tokens (expires_at);

CREATE TABLE $s.passwords (
  account_id uuid PRIMARY KEY REFERENCES $s.accounts (id) ON DELETE CASCADE,
  kdf jsonb NOT NULL,
  salt bytea NOT NULL,
  verifier_salt bytea NOT NULL,
  verifier bytea NOT NULL,
  wrapped_identity_key jsonb NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.invites (
  id uuid PRIMARY KEY,
  code_hash bytea NOT NULL UNIQUE,
  issuer text NOT NULL CHECK (issuer IN ('admin', 'self')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  redeemed_at timestamptz,
  redeemed_by uuid,
  cancelled_at timestamptz
);

CREATE TABLE $s.recovery_codes (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES $s.accounts (id) ON DELETE CASCADE,
  code_hash bytea NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz
);

CREATE TABLE $s.phone_challenges (
  id uuid PRIMARY KEY,
  phone_hash bytea NOT NULL,
  purpose text NOT NULL,
  code_hash bytea NOT NULL,
  discovery_hash text NOT NULL,
  last4 text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);
CREATE INDEX phone_challenges_phone ON $s.phone_challenges (phone_hash, created_at DESC);

CREATE TABLE $s.banned_phones (
  phone_hash bytea PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.security_events (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES $s.accounts (id) ON DELETE CASCADE,
  kind text NOT NULL,
  device_id uuid,
  device_name text,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX security_events_account ON $s.security_events (account_id, id DESC);

CREATE TABLE $s.settings (
  key text PRIMARY KEY,
  value bytea NOT NULL
);
''';
