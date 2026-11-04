-- Enforce one text message per user per room per second at the API boundary.
CREATE TABLE IF NOT EXISTS room_chat_rate_limits (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_sent_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
