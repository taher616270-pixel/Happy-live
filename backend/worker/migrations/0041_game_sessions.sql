CREATE TABLE IF NOT EXISTS game_sessions (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL REFERENCES game_registry(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app_session_id TEXT NOT NULL REFERENCES user_sessions(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  permissions_json TEXT NOT NULL,
  game_origin TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  rate_window_started_at INTEGER NOT NULL DEFAULT 0,
  request_count INTEGER NOT NULL DEFAULT 0 CHECK(request_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_game_sessions_user_game
ON game_sessions(user_id, game_id, created_at);

CREATE INDEX IF NOT EXISTS idx_game_sessions_app_session
ON game_sessions(app_session_id, revoked_at, expires_at);

CREATE INDEX IF NOT EXISTS idx_game_sessions_expiry
ON game_sessions(expires_at, revoked_at);

CREATE INDEX IF NOT EXISTS idx_game_sessions_game
ON game_sessions(game_id, created_at);
