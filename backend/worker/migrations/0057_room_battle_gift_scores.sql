-- Persist PK gift points by the team of the recipient's microphone at send time.
ALTER TABLE room_battles ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 300;
ALTER TABLE room_battles ADD COLUMN expires_at TEXT;

CREATE TABLE IF NOT EXISTS room_battle_gift_scores (
  id TEXT PRIMARY KEY,
  gift_transaction_id TEXT NOT NULL UNIQUE REFERENCES gift_transactions(id) ON DELETE RESTRICT,
  battle_id TEXT NOT NULL REFERENCES room_battles(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  team TEXT NOT NULL CHECK (team IN ('blue', 'red')),
  seat_number INTEGER NOT NULL CHECK (seat_number BETWEEN 1 AND 12),
  points INTEGER NOT NULL CHECK (points > 0),
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_room_battle_gift_scores_battle_team
  ON room_battle_gift_scores(battle_id, team);
CREATE INDEX IF NOT EXISTS idx_room_battle_gift_scores_battle_user
  ON room_battle_gift_scores(battle_id, user_id);
