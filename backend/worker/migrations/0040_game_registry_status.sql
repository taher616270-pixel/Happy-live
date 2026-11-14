CREATE TABLE IF NOT EXISTS game_registry_lifecycle (
  game_id TEXT PRIMARY KEY REFERENCES game_registry(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK(status IN ('development', 'disabled', 'active')),
  updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO game_registry_lifecycle (game_id, status, updated_at)
SELECT id, CASE WHEN enabled = 1 THEN 'active' ELSE 'disabled' END, updated_at
FROM game_registry;

CREATE INDEX IF NOT EXISTS idx_game_registry_lifecycle_status
ON game_registry_lifecycle(status, updated_at);
