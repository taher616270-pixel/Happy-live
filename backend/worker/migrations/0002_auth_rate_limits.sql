-- Authentication endpoint abuse protection and consent timestamp.
ALTER TABLE users ADD COLUMN terms_accepted_at TEXT;

CREATE TABLE IF NOT EXISTS auth_rate_limits (
  ip TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0
);
