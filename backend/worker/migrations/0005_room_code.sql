-- Add a stable, unique eight-digit public code to every room.
ALTER TABLE rooms ADD COLUMN room_code TEXT;

UPDATE rooms
SET room_code = printf('%08d', (abs(random()) % 90000000) + 10000000)
WHERE room_code IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_room_code
  ON rooms(room_code);
