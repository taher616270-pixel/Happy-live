-- Expand shared room microphone seats from six to eight.
PRAGMA foreign_keys = ON;

CREATE TABLE room_seats_new (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  seat_number INTEGER NOT NULL CHECK (seat_number BETWEEN 1 AND 8),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  PRIMARY KEY (room_id, seat_number),
  UNIQUE (room_id, user_id)
);

INSERT INTO room_seats_new (room_id, seat_number, user_id, joined_at, updated_at, expires_at)
SELECT room_id, seat_number, user_id, joined_at, updated_at, expires_at
FROM room_seats;

DROP TABLE room_seats;
ALTER TABLE room_seats_new RENAME TO room_seats;

CREATE INDEX IF NOT EXISTS idx_room_seats_expiry
  ON room_seats(room_id, expires_at);
CREATE INDEX IF NOT EXISTS idx_room_seats_user
  ON room_seats(user_id, room_id);
