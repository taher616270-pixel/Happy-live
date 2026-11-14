CREATE TABLE IF NOT EXISTS game_session_app_bindings (
  game_session_id TEXT PRIMARY KEY REFERENCES game_sessions(id) ON DELETE CASCADE,
  app_session_id TEXT NOT NULL REFERENCES user_sessions(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_game_session_app_bindings_parent
ON game_session_app_bindings(app_session_id, created_at);
