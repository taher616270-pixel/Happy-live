-- Cat Greed wheel: transparent, server-authoritative rounds and wallet ledger.
CREATE TABLE IF NOT EXISTS cat_greed_settings (
  id TEXT PRIMARY KEY CHECK (id = 'current'),
  enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  betting_seconds INTEGER NOT NULL DEFAULT 30 CHECK (betting_seconds BETWEEN 10 AND 120),
  result_seconds INTEGER NOT NULL DEFAULT 8 CHECK (result_seconds BETWEEN 5 AND 30),
  salad_weight_bp INTEGER NOT NULL DEFAULT 600 CHECK (salad_weight_bp BETWEEN 0 AND 5000),
  pizza_weight_bp INTEGER NOT NULL DEFAULT 600 CHECK (pizza_weight_bp BETWEEN 0 AND 5000),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);
INSERT OR IGNORE INTO cat_greed_settings (id, updated_at) VALUES ('current', CURRENT_TIMESTAMP);

CREATE TABLE IF NOT EXISTS cat_greed_symbols (
  slot INTEGER PRIMARY KEY CHECK (slot BETWEEN 0 AND 7),
  emoji TEXT NOT NULL,
  label TEXT NOT NULL,
  multiplier INTEGER NOT NULL CHECK (multiplier BETWEEN 1 AND 100),
  is_vegetable INTEGER NOT NULL CHECK (is_vegetable IN (0, 1)),
  weight INTEGER NOT NULL DEFAULT 1 CHECK (weight BETWEEN 0 AND 100000),
  image_url TEXT,
  updated_at TEXT NOT NULL
);
INSERT OR IGNORE INTO cat_greed_symbols (slot, emoji, label, multiplier, is_vegetable, weight, updated_at) VALUES
  (0, '🐔', 'دجاج', 45, 0, 1, CURRENT_TIMESTAMP),
  (1, '🍅', 'طماطم', 5, 1, 20, CURRENT_TIMESTAMP),
  (2, '🐐', 'ماعز', 15, 0, 7, CURRENT_TIMESTAMP),
  (3, '🌶️', 'فلفل', 5, 1, 20, CURRENT_TIMESTAMP),
  (4, '🐟', 'سمك', 25, 0, 4, CURRENT_TIMESTAMP),
  (5, '🥕', 'جزر', 5, 1, 20, CURRENT_TIMESTAMP),
  (6, '🦐', 'روبيان', 10, 0, 10, CURRENT_TIMESTAMP),
  (7, '🌽', 'ذرة', 5, 1, 20, CURRENT_TIMESTAMP);

CREATE TABLE IF NOT EXISTS cat_greed_rounds (
  id TEXT PRIMARY KEY,
  phase TEXT NOT NULL CHECK (phase IN ('betting', 'result')),
  starts_at TEXT NOT NULL,
  closes_at TEXT NOT NULL,
  result_slot INTEGER,
  special TEXT CHECK (special IN ('salad', 'pizza') OR special IS NULL),
  server_seed TEXT NOT NULL,
  seed_commitment TEXT NOT NULL,
  config_snapshot TEXT NOT NULL,
  created_at TEXT NOT NULL,
  settled_at TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_greed_one_betting_round
  ON cat_greed_rounds(phase) WHERE phase = 'betting';
CREATE INDEX IF NOT EXISTS idx_cat_greed_rounds_created ON cat_greed_rounds(created_at DESC);

CREATE TABLE IF NOT EXISTS cat_greed_bets (
  id TEXT PRIMARY KEY,
  round_id TEXT NOT NULL REFERENCES cat_greed_rounds(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  slot INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 7),
  amount INTEGER NOT NULL CHECK (amount > 0),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cat_greed_bets_round ON cat_greed_bets(round_id, slot);
CREATE INDEX IF NOT EXISTS idx_cat_greed_bets_user ON cat_greed_bets(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cat_greed_payouts (
  round_id TEXT NOT NULL REFERENCES cat_greed_rounds(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  amount INTEGER NOT NULL CHECK (amount > 0),
  created_at TEXT NOT NULL,
  paid_at TEXT,
  transaction_id TEXT,
  PRIMARY KEY (round_id, user_id)
);

CREATE TABLE IF NOT EXISTS cat_greed_player_controls (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  max_bet_per_round INTEGER NOT NULL DEFAULT 1000000 CHECK (max_bet_per_round BETWEEN 10 AND 100000000),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cat_greed_admin_audit (
  id TEXT PRIMARY KEY,
  admin_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target_id TEXT,
  details_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
