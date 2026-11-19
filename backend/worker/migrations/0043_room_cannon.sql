PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS cannon_settings (
  id TEXT PRIMARY KEY CHECK (id = 'current'),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  banner_enabled INTEGER NOT NULL DEFAULT 1 CHECK (banner_enabled IN (0,1)),
  banner_image_url TEXT NOT NULL DEFAULT '',
  frame_image_url TEXT NOT NULL DEFAULT '',
  levels_json TEXT NOT NULL,
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO cannon_settings
  (id, enabled, banner_enabled, banner_image_url, frame_image_url, levels_json, updated_at)
VALUES
  ('current', 1, 1, '', '', '[{"level":1,"need":90000,"prizes":[{"key":"frame_l1","name":"إطار المستوى الأول","type":"frame","value":"frame_l1","icon":"","top1":true,"weight":0},{"key":"bubble_l1","name":"فقاعة نادرة","type":"bubble","value":"bubble_l1","icon":"","top1":false,"weight":10,"rare":true},{"key":"coins_l1","name":"500 عملة","type":"coins","value":"500","icon":"","top1":false,"weight":60},{"key":"gift_l1_a","name":"هدية مميزة","type":"gift","value":"gift_l1_a","icon":"","top1":false,"weight":20},{"key":"gift_l1_b","name":"هدية إضافية","type":"gift","value":"gift_l1_b","icon":"","top1":false,"weight":20}]},{"level":2,"need":900000,"prizes":[{"key":"entry_l2","name":"دخول مميز","type":"entry","value":"entry_l2","icon":"","top1":true,"weight":0},{"key":"frame_l2","name":"إطار نادر","type":"frame","value":"frame_l2","icon":"","top1":false,"weight":10,"rare":true},{"key":"coins_l2","name":"5,000 عملة","type":"coins","value":"5000","icon":"","top1":false,"weight":60},{"key":"gift_l2","name":"هدية المستوى الثاني","type":"gift","value":"gift_l2","icon":"","top1":false,"weight":20},{"key":"badge_l2","name":"شارة المستوى الثاني","type":"badge","value":"badge_l2","icon":"","top1":false,"weight":15}]},{"level":3,"need":5000000,"prizes":[{"key":"entry_l3","name":"دخول فاخر","type":"entry","value":"entry_l3","icon":"","top1":true,"weight":0},{"key":"frame_l3","name":"إطار أزرق","type":"frame","value":"frame_l3","icon":"","top1":false,"weight":10,"rare":true},{"key":"coins_l3","name":"25,000 عملة","type":"coins","value":"25000","icon":"","top1":false,"weight":60},{"key":"gift_l3","name":"هدية المستوى الثالث","type":"gift","value":"gift_l3","icon":"","top1":false,"weight":20},{"key":"badge_l3","name":"شارة المستوى الثالث","type":"badge","value":"badge_l3","icon":"","top1":false,"weight":15}]},{"level":4,"need":14000000,"prizes":[{"key":"entry_l4","name":"دخول ملكي","type":"entry","value":"entry_l4","icon":"","top1":true,"weight":0},{"key":"coins_l4","name":"100,000 عملة","type":"coins","value":"100000","icon":"","top1":false,"weight":60},{"key":"badge_l4","name":"شارة المستوى الرابع","type":"badge","value":"badge_l4","icon":"","top1":false,"weight":15},{"key":"wave_l4","name":"موجة ملكية","type":"wave","value":"wave_l4","icon":"","top1":false,"weight":15}]}]', strftime('%Y-%m-%dT%H:%M:%fZ','now'));

CREATE TABLE IF NOT EXISTS cannon_rooms (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
  progress INTEGER NOT NULL DEFAULT 0 CHECK (progress >= 0),
  launching_until INTEGER NOT NULL DEFAULT 0,
  last_launch_id TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (room_id, day)
);
CREATE INDEX IF NOT EXISTS idx_cannon_rooms_day_progress ON cannon_rooms(day, progress DESC);

CREATE TABLE IF NOT EXISTS cannon_presence (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seen_at INTEGER NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_cannon_presence_seen ON cannon_presence(room_id, seen_at DESC);

CREATE TABLE IF NOT EXISTS cannon_energy_transactions (
  transaction_id TEXT PRIMARY KEY REFERENCES gift_transactions(id) ON DELETE RESTRICT,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  coin_cost INTEGER NOT NULL CHECK (coin_cost > 0),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cannon_energy_room_created ON cannon_energy_transactions(room_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cannon_contrib (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level INTEGER NOT NULL,
  amount INTEGER NOT NULL DEFAULT 0 CHECK (amount >= 0),
  PRIMARY KEY (room_id, day, user_id, level)
);
CREATE INDEX IF NOT EXISTS idx_cannon_contrib_leaderboard ON cannon_contrib(room_id, day, level, amount DESC);

CREATE TABLE IF NOT EXISTS cannon_launches (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  level INTEGER NOT NULL,
  day TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cannon_launches_room_day ON cannon_launches(room_id, day, created_at DESC);

CREATE TABLE IF NOT EXISTS cannon_claims (
  id TEXT PRIMARY KEY,
  launch_id TEXT NOT NULL REFERENCES cannon_launches(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reward_key TEXT NOT NULL,
  reward_type TEXT NOT NULL,
  reward_value TEXT NOT NULL,
  reward_name TEXT NOT NULL,
  claimed INTEGER NOT NULL DEFAULT 0 CHECK (claimed IN (0,1)),
  created_at TEXT NOT NULL,
  claimed_at TEXT,
  UNIQUE (launch_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_cannon_claims_user ON cannon_claims(room_id, user_id, claimed, created_at);

CREATE TABLE IF NOT EXISTS cannon_user_items (
  id TEXT PRIMARY KEY,
  claim_id TEXT NOT NULL UNIQUE REFERENCES cannon_claims(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL,
  item_name TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cannon_user_items_user ON cannon_user_items(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cannon_wallet_ledger (
  id TEXT PRIMARY KEY,
  claim_id TEXT NOT NULL UNIQUE REFERENCES cannon_claims(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  balance_after INTEGER NOT NULL CHECK (balance_after >= 0),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cannon_wallet_ledger_user ON cannon_wallet_ledger(user_id, created_at DESC);
