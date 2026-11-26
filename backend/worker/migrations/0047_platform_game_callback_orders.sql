-- Preserve the old callback ledger as an archive, then move its rows to a
-- platform-neutral ledger used by Happy Food Wheel. No wallet history is deleted.
ALTER TABLE utd_game_callback_orders RENAME TO legacy_game_callback_orders_archive;
DROP INDEX IF EXISTS idx_utd_callback_orders_user_created;
CREATE TABLE IF NOT EXISTS platform_game_callback_orders (
  order_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  game_id TEXT NOT NULL,
  round_id TEXT NOT NULL,
  delta INTEGER NOT NULL,
  claim_id TEXT NOT NULL UNIQUE,
  applied INTEGER NOT NULL DEFAULT 0 CHECK (applied IN (0, 1)),
  created_at TEXT NOT NULL
);
INSERT OR IGNORE INTO platform_game_callback_orders
  (order_id,user_id,game_id,round_id,delta,claim_id,applied,created_at)
SELECT order_id,user_id,game_id,round_id,delta,claim_id,applied,created_at
FROM legacy_game_callback_orders_archive;
CREATE INDEX IF NOT EXISTS idx_platform_game_orders_user_created
  ON platform_game_callback_orders(user_id,created_at DESC);
