-- Production-only Chicken Road. Uses the existing Happy Live user wallet and game ledger.
PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO game_registry
  (id, name, game_url, icon_url, description, category, enabled, sort_order, created_by_admin_id, created_at, updated_at)
VALUES
  ('f21d2c7a-8f1b-4d72-9a63-5c8f7e1d4b90', 'عبور الدجاجة', 'https://happy-live.pages.dev/games/chicken-road/client/index.html',
   NULL, 'اعبر الطريق واجمع المضاعفات مع رصيد Happy Live الحقيقي.', 'ألعاب', 1, 31, NULL,
   strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

INSERT INTO game_registry_lifecycle (game_id, status, updated_at)
VALUES ('f21d2c7a-8f1b-4d72-9a63-5c8f7e1d4b90', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
ON CONFLICT(game_id) DO UPDATE SET status = 'active', updated_at = excluded.updated_at;

CREATE TABLE IF NOT EXISTS chicken_road_round_state (
  round_id TEXT PRIMARY KEY REFERENCES game_rounds(id) ON DELETE RESTRICT,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  crash_step INTEGER NOT NULL CHECK (crash_step BETWEEN 1 AND 26),
  seed TEXT NOT NULL,
  commit_hash TEXT NOT NULL,
  current_step INTEGER NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 25),
  last_step_at INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'dead', 'cashed')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_chicken_road_round_state_status
  ON chicken_road_round_state(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chicken_road_rounds_user
  ON game_rounds(game_id, user_id, status, created_at DESC);
