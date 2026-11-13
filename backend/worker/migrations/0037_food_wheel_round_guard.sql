-- Additional database-level guard for bets created after the original protection migration.
-- Kept as a new migration so already-applied 0036 remains immutable.
CREATE TRIGGER IF NOT EXISTS cat_greed_bet_guard_insert
BEFORE INSERT ON cat_greed_bets
WHEN NEW.amount NOT IN (10, 500, 6000, 30000, 100000)
  OR NOT EXISTS (
    SELECT 1 FROM cat_greed_rounds
    WHERE id=NEW.round_id AND phase='betting' AND julianday(closes_at)>julianday('now')
  )
BEGIN
  SELECT RAISE(ABORT, 'invalid_or_closed_cat_greed_bet');
END;
