-- Temporary kick records, separate from permanent room bans.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_kicks (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kicked_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kicked_until TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_kicks_expiry ON room_kicks(room_id, kicked_until);
