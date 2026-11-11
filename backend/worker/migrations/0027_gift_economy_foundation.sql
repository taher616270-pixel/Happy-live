-- Gift economy foundation. All values are integer coins/XP; no cash conversion or payout is enabled.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS gift_catalog (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  icon_emoji TEXT NOT NULL DEFAULT '🎁',
  asset_key TEXT NOT NULL DEFAULT '',
  coin_price INTEGER NOT NULL CHECK (coin_price > 0),
  is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_catalog_active_sort
  ON gift_catalog(is_active, sort_order, created_at);

-- Current split is editable only by an authorized owner/admin API.
-- Each successful gift snapshots the percentages so historical transactions never change.
CREATE TABLE IF NOT EXISTS gift_revenue_settings (
  id TEXT PRIMARY KEY CHECK (id = 'current'),
  app_percent INTEGER NOT NULL DEFAULT 30 CHECK (app_percent BETWEEN 0 AND 100),
  recipient_percent INTEGER NOT NULL DEFAULT 70 CHECK (recipient_percent BETWEEN 0 AND 100),
  withdrawals_enabled INTEGER NOT NULL DEFAULT 0 CHECK (withdrawals_enabled IN (0, 1)),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL,
  CHECK (app_percent + recipient_percent = 100)
);
INSERT OR IGNORE INTO gift_revenue_settings
  (id, app_percent, recipient_percent, withdrawals_enabled, updated_at)
VALUES ('current', 30, 70, 0, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

CREATE TABLE IF NOT EXISTS gift_revenue_settings_audit (
  id TEXT PRIMARY KEY,
  admin_id TEXT NOT NULL,
  old_app_percent INTEGER NOT NULL,
  old_recipient_percent INTEGER NOT NULL,
  new_app_percent INTEGER NOT NULL,
  new_recipient_percent INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_settings_audit_created
  ON gift_revenue_settings_audit(created_at DESC);

-- One durable row per accepted send request. Idempotency is scoped to the sender.
CREATE TABLE IF NOT EXISTS gift_transactions (
  id TEXT PRIMARY KEY,
  sender_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  recipient_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  context_type TEXT NOT NULL CHECK (context_type IN ('room', 'private')),
  room_id TEXT REFERENCES rooms(id) ON DELETE RESTRICT,
  gift_id TEXT NOT NULL REFERENCES gift_catalog(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
  coin_cost INTEGER NOT NULL CHECK (coin_cost > 0),
  app_percent_snapshot INTEGER NOT NULL CHECK (app_percent_snapshot BETWEEN 0 AND 100),
  recipient_percent_snapshot INTEGER NOT NULL CHECK (recipient_percent_snapshot BETWEEN 0 AND 100),
  app_coins INTEGER NOT NULL CHECK (app_coins >= 0),
  recipient_coins INTEGER NOT NULL CHECK (recipient_coins >= 0),
  experience_awarded INTEGER NOT NULL DEFAULT 0 CHECK (experience_awarded >= 0),
  experience_multiplier INTEGER NOT NULL DEFAULT 1 CHECK (experience_multiplier IN (1, 2)),
  battle_id TEXT,
  idempotency_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'succeeded' CHECK (status IN ('succeeded', 'reversed')),
  reversed_at TEXT,
  created_at TEXT NOT NULL,
  CHECK (app_percent_snapshot + recipient_percent_snapshot = 100),
  CHECK ((context_type = 'room' AND room_id IS NOT NULL) OR (context_type = 'private' AND room_id IS NULL)),
  CHECK (sender_user_id <> recipient_user_id),
  UNIQUE(sender_user_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_recipient_created
  ON gift_transactions(recipient_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_room_created
  ON gift_transactions(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_sender_created
  ON gift_transactions(sender_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS room_exp_gift_awards (
  id TEXT PRIMARY KEY,
  gift_transaction_id TEXT NOT NULL UNIQUE REFERENCES gift_transactions(id) ON DELETE RESTRICT,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day_key TEXT NOT NULL,
  points INTEGER NOT NULL CHECK (points > 0 AND points <= 3000000),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_room_exp_gift_awards_user_day
  ON room_exp_gift_awards(user_id, day_key);

-- Recipient's 70% is credited to the ordinary coin wallet, but remains tagged.
-- Spending tagged gift coins consumes their future withdrawal eligibility in FIFO order.
CREATE TABLE IF NOT EXISTS gift_earning_lots (
  id TEXT PRIMARY KEY,
  gift_transaction_id TEXT NOT NULL UNIQUE REFERENCES gift_transactions(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  credited_coins INTEGER NOT NULL CHECK (credited_coins >= 0),
  remaining_tagged_coins INTEGER NOT NULL CHECK (remaining_tagged_coins >= 0 AND remaining_tagged_coins <= credited_coins),
  remaining_withdrawable_coins INTEGER NOT NULL CHECK (remaining_withdrawable_coins >= 0 AND remaining_withdrawable_coins <= remaining_tagged_coins),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_earning_lots_user_fifo
  ON gift_earning_lots(user_id, created_at, id);

CREATE TABLE IF NOT EXISTS gift_wallet_ledger (
  id TEXT PRIMARY KEY,
  gift_transaction_id TEXT NOT NULL REFERENCES gift_transactions(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  entry_type TEXT NOT NULL CHECK (entry_type IN ('sender_debit', 'recipient_credit', 'app_share', 'refund_debit', 'refund_credit')),
  amount INTEGER NOT NULL CHECK (amount <> 0),
  balance_after INTEGER,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_wallet_ledger_user_created
  ON gift_wallet_ledger(user_id, created_at DESC);

-- Server-verifiable battle windows. No client-supplied battle flag can grant the 2x multiplier.
CREATE TABLE IF NOT EXISTS room_battles (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('active', 'finished', 'cancelled')),
  started_at TEXT NOT NULL,
  ended_at TEXT,
  created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  CHECK ((status = 'active' AND ended_at IS NULL) OR (status <> 'active' AND ended_at IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_room_battles_one_active_per_room
  ON room_battles(room_id) WHERE status = 'active';

-- Withdrawals are intentionally disabled until agency settlement, KYC and payout rails are approved.
CREATE TABLE IF NOT EXISTS gift_withdrawal_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  agency_id TEXT,
  requested_coins INTEGER NOT NULL CHECK (requested_coins > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'approved', 'rejected', 'paid', 'cancelled')),
  payout_reference TEXT,
  reviewed_by_admin_id TEXT,
  review_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_withdrawals_status_created
  ON gift_withdrawal_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_withdrawals_user_created
  ON gift_withdrawal_requests(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS gift_withdrawal_settings (
  id TEXT PRIMARY KEY CHECK (id = 'current'),
  enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  agency_integration_ready INTEGER NOT NULL DEFAULT 0 CHECK (agency_integration_ready IN (0, 1)),
  minimum_coins INTEGER NOT NULL DEFAULT 0 CHECK (minimum_coins >= 0),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);
INSERT OR IGNORE INTO gift_withdrawal_settings
  (id, enabled, agency_integration_ready, minimum_coins, updated_at)
VALUES ('current', 0, 0, 0, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));


-- Initial premium catalogue. Emoji artwork is self-contained; no missing image paths.
INSERT OR IGNORE INTO gift_catalog (id, name, icon_emoji, asset_key, coin_price, is_active, sort_order, created_at, updated_at)
VALUES
('gift-diamond-rose', 'وردة الألماس', '💎', '', 999, 1, 10, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('gift-golden-palace', 'قصر الذهب', '🏰', '', 4999, 1, 20, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('gift-royal-yacht', 'يخت الملوك', '🛥️', '', 9999, 1, 30, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
