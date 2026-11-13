-- PR #39 coalesces repeated taps into aggregated wager amounts.
-- Replace the original chip-only guard while retaining the closed-round invariant.
DROP TRIGGER IF EXISTS cat_greed_bet_guard_insert;

CREATE TRIGGER cat_greed_bet_guard_insert
BEFORE INSERT ON cat_greed_bets
WHEN NEW.amount < 1
  OR NEW.amount > 1000000
  OR NEW.amount != CAST(NEW.amount AS INTEGER)
  OR NOT EXISTS (
    SELECT 1 FROM cat_greed_rounds
    WHERE id=NEW.round_id AND phase='betting' AND julianday(closes_at)>julianday('now')
  )
BEGIN
  SELECT RAISE(ABORT, 'invalid_or_closed_cat_greed_bet');
END;
