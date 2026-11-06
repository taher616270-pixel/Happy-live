-- Room-scoped moderator assignments, moderation state, and room bans.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_moderators (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  assigned_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_moderators_user ON room_moderators(user_id, room_id);

CREATE TABLE IF NOT EXISTS room_user_controls (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_muted INTEGER NOT NULL DEFAULT 0 CHECK (is_muted IN (0, 1)),
  muted_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS room_bans (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  banned_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_bans_user ON room_bans(user_id, room_id);
