-- Store one authoritative named-food totals object on each shared round.
ALTER TABLE food_wheel_rounds ADD COLUMN totals_json TEXT NOT NULL DEFAULT '{"chicken":0,"corn":0,"tomato":0,"goat":0,"chili":0,"fish":0,"carrot":0,"shrimp":0}';

-- Backfill historical rounds once; subsequent accepted bets increment only the selected food key.
UPDATE food_wheel_rounds
SET totals_json = (
  SELECT json_object(
    'chicken', COALESCE(SUM(CASE WHEN slot = 0 THEN stake ELSE 0 END), 0),
    'corn', COALESCE(SUM(CASE WHEN slot = 1 THEN stake ELSE 0 END), 0),
    'tomato', COALESCE(SUM(CASE WHEN slot = 2 THEN stake ELSE 0 END), 0),
    'goat', COALESCE(SUM(CASE WHEN slot = 3 THEN stake ELSE 0 END), 0),
    'chili', COALESCE(SUM(CASE WHEN slot = 4 THEN stake ELSE 0 END), 0),
    'fish', COALESCE(SUM(CASE WHEN slot = 5 THEN stake ELSE 0 END), 0),
    'carrot', COALESCE(SUM(CASE WHEN slot = 6 THEN stake ELSE 0 END), 0),
    'shrimp', COALESCE(SUM(CASE WHEN slot = 7 THEN stake ELSE 0 END), 0)
  )
  FROM food_wheel_bets
  WHERE round_id = food_wheel_rounds.id AND status IN ('accepted', 'settled')
);
