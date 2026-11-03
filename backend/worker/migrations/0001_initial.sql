-- Happy Live initial D1 schema.
-- Authentication secrets are stored only as strong hashes; never store plaintext passwords or OTPs.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT,
  auth_provider TEXT NOT NULL DEFAULT 'email'
    CHECK (auth_provider IN ('email', 'google', 'apple')),
  auth_subject TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'suspended', 'deleted')),
  email_verified_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (auth_provider, auth_subject)
);

CREATE TABLE IF NOT EXISTS user_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expiry ON user_sessions(expires_at);

CREATE TABLE IF NOT EXISTS password_reset_otps (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_password_reset_user_created
  ON password_reset_otps(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS profiles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT '',
  gabo_id TEXT UNIQUE,
  avatar_key TEXT,
  cover_key TEXT,
  bio TEXT NOT NULL DEFAULT '',
  country_code TEXT,
  country_name TEXT,
  country_flag TEXT,
  gender TEXT CHECK (gender IN ('male', 'female') OR gender IS NULL),
  birthday TEXT,
  is_private INTEGER NOT NULL DEFAULT 0 CHECK (is_private IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS admin_roles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'moderator')),
  granted_by TEXT REFERENCES users(id),
  granted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id TEXT PRIMARY KEY,
  actor_user_id TEXT REFERENCES users(id),
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_logs(created_at DESC);
