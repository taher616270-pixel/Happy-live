-- Each visit gets a private chat-history start time.
-- Existing room members keep their current view; newcomers only see messages
-- created after their own entry. Re-entering creates a fresh visit.
CREATE TABLE IF NOT EXISTS room_chat_visits (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entered_at TEXT NOT NULL,
  exited_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_room_chat_visits_active
  ON room_chat_visits(room_id, user_id, exited_at, entered_at DESC);
