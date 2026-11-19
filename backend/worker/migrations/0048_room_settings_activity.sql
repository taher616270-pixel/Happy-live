-- Audit trail for room owner settings and moderation actions.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_settings_logs (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  actor_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_room_settings_logs_room_created
  ON room_settings_logs(room_id, created_at DESC);
