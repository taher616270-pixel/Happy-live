-- The production database already has last_seen_at (introduced before this
-- migration was tracked). Keep this migration safe on both existing and
-- freshly synchronized databases; do not attempt to add the column twice.
UPDATE room_chat_visits
SET last_seen_at = entered_at
WHERE last_seen_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_room_chat_visits_presence
  ON room_chat_visits(room_id, exited_at, last_seen_at);
