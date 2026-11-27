-- Global server-owned Food Wheel rounds. Additive only; existing wallet tables and rules are unchanged.
CREATE TABLE IF NOT EXISTS food_wheel_rounds (
  round_no INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('betting', 'result', 'settled')),
  started_at TEXT NOT NULL,
  betting_ends_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  result_slot INTEGER CHECK (result_slot IS NULL OR result_slot BETWEEN 0 AND 7),
  result_chosen_at TEXT,
  settled_at TEXT,
  created_at TEXT NOT NULL,
  CHECK (betting_ends_at > started_at),
  CHECK (ends_at > betting_ends_at)
);

-- Enforce one shared active round even if two bootstrap requests race.
CREATE UNIQUE INDEX IF NOT EXISTS idx_food_wheel_one_active_round
  ON food_wheel_rounds((1))
  WHERE status IN ('betting', 'result');

CREATE INDEX IF NOT EXISTS idx_food_wheel_rounds_status_end
  ON food_wheel_rounds(status, ends_at);

CREATE TABLE IF NOT EXISTS food_wheel_bets (
  id TEXT PRIMARY KEY,
  round_id TEXT NOT NULL REFERENCES food_wheel_rounds(id) ON DELETE RESTRICT,
  game_round_id TEXT NOT NULL REFERENCES game_rounds(id) ON DELETE RESTRICT,
  game_bet_id TEXT NOT NULL UNIQUE REFERENCES game_bets(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  slot INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 7),
  stake INTEGER NOT NULL CHECK (stake > 0),
  payout INTEGER NOT NULL DEFAULT 0 CHECK (payout >= 0),
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'accepted', 'settled')),
  created_at TEXT NOT NULL,
  settled_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_food_wheel_bets_round_slot
  ON food_wheel_bets(round_id, slot, status);

CREATE INDEX IF NOT EXISTS idx_food_wheel_bets_round_user
  ON food_wheel_bets(round_id, user_id, status);

CREATE INDEX IF NOT EXISTS idx_food_wheel_bets_user_created
  ON food_wheel_bets(user_id, created_at DESC);
