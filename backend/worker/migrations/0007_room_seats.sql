-- Shared, exclusive microphone seats for active rooms.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS room_seats (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  seat_number INTEGER NOT NULL CHECK (seat_number BETWEEN 1 AND 6),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  PRIMARY KEY (room_id, seat_number),
  UNIQUE (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_room_seats_expiry
  ON room_seats(room_id, expires_at);
CREATE INDEX IF NOT EXISTS idx_room_seats_user
  ON room_seats(user_id, room_id);
