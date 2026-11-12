-- Cat Greed abuse protection: idempotent bet requests and per-user burst limits.
CREATE TABLE IF NOT EXISTS cat_greed_bet_requests (
  idempotency_key TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  round_id TEXT NOT NULL REFERENCES cat_greed_rounds(id) ON DELETE CASCADE,
  slot INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 7),
  amount INTEGER NOT NULL CHECK (amount IN (10, 500, 6000, 30000, 100000)),
  bet_id TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cat_greed_bet_requests_user_round
  ON cat_greed_bet_requests(user_id, round_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cat_greed_bet_rate_limits (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL CHECK (request_count >= 0)
);

CREATE TABLE IF NOT EXISTS cat_greed_state_rate_limits (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL CHECK (request_count >= 0)
);

-- Safer defaults for a new, disabled game. These settings keep the maximum
-- theoretical gross return for any single-symbol bet below 100% under the
-- current salad/pizza category payout rules. Preserve any owner-customized config.
UPDATE cat_greed_settings
SET salad_weight_bp = 30, pizza_weight_bp = 30, updated_at = CURRENT_TIMESTAMP
WHERE id = 'current' AND enabled = 0 AND updated_by_admin_id IS NULL
  AND salad_weight_bp = 600 AND pizza_weight_bp = 600;

UPDATE cat_greed_symbols
SET weight = CASE slot
  WHEN 0 THEN 192
  WHEN 1 THEN 1988
  WHEN 2 THEN 648
  WHEN 3 THEN 1988
  WHEN 4 THEN 372
  WHEN 5 THEN 1988
  WHEN 6 THEN 972
  WHEN 7 THEN 1988
  ELSE weight
END,
updated_at = CURRENT_TIMESTAMP
WHERE (SELECT COUNT(*) FROM cat_greed_symbols) = 8
  AND (SELECT COUNT(*) FROM cat_greed_symbols WHERE
    (slot = 0 AND weight = 1) OR (slot = 1 AND weight = 20) OR
    (slot = 2 AND weight = 7) OR (slot = 3 AND weight = 20) OR
    (slot = 4 AND weight = 4) OR (slot = 5 AND weight = 20) OR
    (slot = 6 AND weight = 10) OR (slot = 7 AND weight = 20)) = 8;

-- Query-path indexes for payout reads, player history, and audit review.
CREATE INDEX IF NOT EXISTS idx_cat_greed_payouts_user_paid
  ON cat_greed_payouts(user_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS idx_cat_greed_bets_round_user_slot
  ON cat_greed_bets(round_id, user_id, slot);
CREATE INDEX IF NOT EXISTS idx_cat_greed_admin_audit_created
  ON cat_greed_admin_audit(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_greed_payout_transaction
  ON cat_greed_payouts(transaction_id) WHERE transaction_id IS NOT NULL;

-- Defense in depth: a settled normal round must have one slot; a special
-- round must have no slot. A betting round must not expose a result.
CREATE TRIGGER IF NOT EXISTS cat_greed_round_result_consistency_insert
BEFORE INSERT ON cat_greed_rounds
WHEN NOT (
  (NEW.phase='betting' AND NEW.result_slot IS NULL AND NEW.special IS NULL) OR
  (NEW.phase='result' AND (
    (NEW.special IS NULL AND NEW.result_slot BETWEEN 0 AND 7) OR
    (NEW.special IN ('salad','pizza') AND NEW.result_slot IS NULL)
  ))
)
BEGIN
  SELECT RAISE(ABORT, 'invalid_cat_greed_round_result');
END;

CREATE TRIGGER IF NOT EXISTS cat_greed_round_result_consistency_update
BEFORE UPDATE OF phase, result_slot, special ON cat_greed_rounds
WHEN NOT (
  (NEW.phase='betting' AND NEW.result_slot IS NULL AND NEW.special IS NULL) OR
  (NEW.phase='result' AND (
    (NEW.special IS NULL AND NEW.result_slot BETWEEN 0 AND 7) OR
    (NEW.special IN ('salad','pizza') AND NEW.result_slot IS NULL)
  ))
)
BEGIN
  SELECT RAISE(ABORT, 'invalid_cat_greed_round_result');
END;
