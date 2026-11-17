-- UTD callback idempotency ledger shared by change-balance and make-up-orders.
-- A globally unique order_id prevents a retry through the other callback from minting coins.
CREATE TABLE IF NOT EXISTS utd_game_callback_orders (
  order_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  game_id TEXT NOT NULL,
  round_id TEXT NOT NULL,
  delta INTEGER NOT NULL,
  claim_id TEXT NOT NULL UNIQUE,
  applied INTEGER NOT NULL DEFAULT 0 CHECK (applied IN (0, 1)),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_utd_callback_orders_user_created
  ON utd_game_callback_orders(user_id, created_at DESC);
