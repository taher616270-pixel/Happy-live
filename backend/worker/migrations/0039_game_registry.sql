CREATE TABLE IF NOT EXISTS game_registry (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK(length(name) BETWEEN 2 AND 80),
  game_url TEXT NOT NULL CHECK(length(game_url) BETWEEN 12 AND 2048),
  icon_url TEXT,
  description TEXT NOT NULL DEFAULT '' CHECK(length(description) <= 240),
  category TEXT NOT NULL DEFAULT 'عام' CHECK(length(category) BETWEEN 1 AND 40),
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by_admin_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_game_registry_public ON game_registry(enabled, sort_order, created_at);
