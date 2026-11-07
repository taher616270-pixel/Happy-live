-- One-time bootstrap guard for the independent primary administrator.
-- The setup nonce prevents concurrent first-run requests from both changing the owner password.
CREATE TABLE IF NOT EXISTS admin_setup_state (
  id TEXT PRIMARY KEY CHECK (id = 'primary-owner'),
  setup_nonce TEXT NOT NULL UNIQUE,
  completed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
