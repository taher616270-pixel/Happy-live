-- Track the last confirmed presence heartbeat for each room visit.
ALTER TABLE room_chat_visits ADD COLUMN last_seen_at TEXT;
UPDATE room_chat_visits SET last_seen_at = entered_at WHERE last_seen_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_room_chat_visits_presence
  ON room_chat_visits(room_id, exited_at, last_seen_at);
