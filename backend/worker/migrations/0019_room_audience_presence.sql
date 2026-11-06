-- Track the last confirmed presence heartbeat for each room visit.
-- The last_seen_at column already exists in the production D1 database.
UPDATE room_chat_visits SET last_seen_at = entered_at WHERE last_seen_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_room_chat_visits_presence
  ON room_chat_visits(room_id, exited_at, last_seen_at);
