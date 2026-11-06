-- Store room announcements separately so the migration is safe to re-run.
CREATE TABLE IF NOT EXISTS room_announcements (
  room_id TEXT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  announcement TEXT NOT NULL DEFAULT '' CHECK (length(announcement) <= 200),
  updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO room_announcements (room_id, announcement, updated_at)
SELECT id, description, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM rooms;
