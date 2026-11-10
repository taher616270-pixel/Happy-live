-- Keep the oldest active room for each account and close duplicates without deleting room data.
WITH ranked_active_rooms AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY owner_user_id
      ORDER BY created_at ASC, id ASC
    ) AS room_rank
  FROM rooms
  WHERE status = 'active'
)
UPDATE rooms
SET
  status = 'closed',
  updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id IN (
  SELECT id
  FROM ranked_active_rooms
  WHERE room_rank > 1
);

-- The API also treats a closed/deleted room as the account's permanent room.
-- This index is the concurrency guard for simultaneous room-creation requests.
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_one_active_per_owner
  ON rooms(owner_user_id)
  WHERE status = 'active';
