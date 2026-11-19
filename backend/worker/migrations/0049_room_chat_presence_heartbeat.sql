-- Add the heartbeat timestamp required by room audience presence queries.
ALTER TABLE room_chat_visits ADD COLUMN last_seen_at TEXT;
UPDATE room_chat_visits
SET last_seen_at = entered_at
WHERE last_seen_at IS NULL;
