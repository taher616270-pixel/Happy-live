-- Persist a room announcement separately from the room description.
ALTER TABLE rooms ADD COLUMN announcement TEXT NOT NULL DEFAULT '' CHECK (length(announcement) <= 200);

UPDATE rooms
SET announcement = description
WHERE announcement = '' AND description <> '';
