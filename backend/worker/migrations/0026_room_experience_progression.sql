-- Persistent room experience progression, separate from paid room tier upgrades.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_experience (
  room_id TEXT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  total_exp INTEGER NOT NULL DEFAULT 0 CHECK (total_exp >= 0),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS room_exp_activity (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_awarded_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS room_exp_daily (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day_key TEXT NOT NULL,
  points INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0 AND points <= 3000000),
  PRIMARY KEY (user_id, day_key)
);

CREATE INDEX IF NOT EXISTS idx_room_exp_daily_day
  ON room_exp_daily(day_key, user_id);

CREATE TABLE IF NOT EXISTS room_exp_awards (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day_key TEXT NOT NULL,
  points INTEGER NOT NULL CHECK (points > 0 AND points <= 600),
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_room_exp_awards_user_day
  ON room_exp_awards(user_id, day_key);
