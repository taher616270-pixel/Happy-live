PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS cannon_box_rounds (
  id TEXT PRIMARY KEY,
  launch_id TEXT NOT NULL REFERENCES cannon_launches(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  starts_at_ms INTEGER NOT NULL,
  ends_at_ms INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (launch_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_cannon_box_rounds_user ON cannon_box_rounds(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cannon_box_openings (
  id TEXT PRIMARY KEY,
  round_id TEXT NOT NULL REFERENCES cannon_box_rounds(id) ON DELETE CASCADE,
  box_index INTEGER NOT NULL CHECK (box_index >= 0 AND box_index < 50),
  reward_key TEXT NOT NULL,
  reward_type TEXT NOT NULL,
  reward_value TEXT NOT NULL,
  reward_name TEXT NOT NULL,
  reward_icon TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  UNIQUE (round_id, box_index)
);
CREATE INDEX IF NOT EXISTS idx_cannon_box_openings_round ON cannon_box_openings(round_id, box_index);

CREATE TABLE IF NOT EXISTS cannon_box_wallet_ledger (
  id TEXT PRIMARY KEY,
  opening_id TEXT NOT NULL UNIQUE REFERENCES cannon_box_openings(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cannon_box_inventory (
  id TEXT PRIMARY KEY,
  opening_id TEXT NOT NULL UNIQUE REFERENCES cannon_box_openings(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL,
  item_name TEXT NOT NULL,
  item_type TEXT NOT NULL,
  icon_url TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cannon_box_inventory_user ON cannon_box_inventory(user_id, created_at DESC);
