-- Persistent owner-managed voice-room settings and per-action moderator permissions.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_settings (
  room_id TEXT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  settings_json TEXT NOT NULL DEFAULT '{}',
  permissions_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
