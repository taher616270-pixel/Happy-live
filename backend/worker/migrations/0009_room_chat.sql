-- Persistent text and image messages scoped to each active voice room.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_messages (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL DEFAULT '' CHECK (length(message) <= 1000),
  image_url TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (length(message) > 0 OR image_url IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_room_messages_room_created
  ON room_messages(room_id, created_at DESC);
