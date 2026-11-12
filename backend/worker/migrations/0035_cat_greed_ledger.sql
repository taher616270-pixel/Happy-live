CREATE TABLE IF NOT EXISTS cat_greed_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  round_id TEXT NOT NULL REFERENCES cat_greed_rounds(id) ON DELETE RESTRICT,
  amount INTEGER NOT NULL CHECK (amount <> 0),
  balance_after INTEGER NOT NULL CHECK (balance_after >= 0),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('bet', 'payout')),
  description TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cat_greed_ledger_user_created
  ON cat_greed_ledger(user_id, created_at DESC);
