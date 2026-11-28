-- Allow the two bottom group-bet keys while keeping the eight wheel foods at slots 0..7.
-- Pizza group = slot 8; Salad group = slot 9. Neither is a wheel outcome.
CREATE TABLE food_wheel_bets_v2 (
  id TEXT PRIMARY KEY,
  round_id TEXT NOT NULL REFERENCES food_wheel_rounds(id) ON DELETE RESTRICT,
  game_round_id TEXT NOT NULL REFERENCES game_rounds(id) ON DELETE RESTRICT,
  game_bet_id TEXT NOT NULL UNIQUE REFERENCES game_bets(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  slot INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 9),
  stake INTEGER NOT NULL CHECK (stake > 0),
  payout INTEGER NOT NULL DEFAULT 0 CHECK (payout >= 0),
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'accepted', 'settled')),
  created_at TEXT NOT NULL,
  settled_at TEXT
);

INSERT INTO food_wheel_bets_v2
  (id, round_id, game_round_id, game_bet_id, user_id, slot, stake, payout, status, created_at, settled_at)
SELECT id, round_id, game_round_id, game_bet_id, user_id, slot, stake, payout, status, created_at, settled_at
FROM food_wheel_bets;

DROP TABLE food_wheel_bets;
ALTER TABLE food_wheel_bets_v2 RENAME TO food_wheel_bets;

CREATE INDEX idx_food_wheel_bets_round_slot
  ON food_wheel_bets(round_id, slot, status);
CREATE INDEX idx_food_wheel_bets_round_user
  ON food_wheel_bets(round_id, user_id, status);
CREATE INDEX idx_food_wheel_bets_user_created
  ON food_wheel_bets(user_id, created_at DESC);

-- Add named group totals to existing and future rounds without touching food totals.
UPDATE food_wheel_rounds
SET totals_json = json_set(
  totals_json,
  '$.pizza_group', COALESCE(json_extract(totals_json, '$.pizza_group'), 0),
  '$.salad_group', COALESCE(json_extract(totals_json, '$.salad_group'), 0)
);
