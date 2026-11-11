-- Independent room progression. This is deliberately separate from room_levels,
-- which remains exclusively responsible for paid "فعّال" room upgrades.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_progression (
  room_id TEXT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  level INTEGER NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 1000),
  experience INTEGER NOT NULL DEFAULT 0 CHECK (experience >= 0),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

INSERT OR IGNORE INTO room_progression (room_id, level, experience, updated_at)
SELECT id, 1, 0, updated_at FROM rooms WHERE status <> 'deleted';

CREATE TABLE IF NOT EXISTS room_progression_events (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  experience_delta INTEGER NOT NULL DEFAULT 0,
  source_ref TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE(event_type, source_ref)
);

CREATE INDEX IF NOT EXISTS idx_room_progression_events_room_created
  ON room_progression_events(room_id, created_at DESC);
