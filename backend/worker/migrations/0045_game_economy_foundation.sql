-- Unified game economy foundation. Additive only; does not modify existing app or Food Wheel wallets.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS game_economy_settings (
  game_id TEXT PRIMARY KEY REFERENCES game_registry(id) ON DELETE CASCADE,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  min_bet INTEGER NOT NULL DEFAULT 1 CHECK (min_bet > 0),
  max_bet INTEGER NOT NULL DEFAULT 100000 CHECK (max_bet >= min_bet),
  max_bets_per_round INTEGER NOT NULL DEFAULT 6 CHECK (max_bets_per_round BETWEEN 1 AND 100),
  max_total_bet INTEGER NOT NULL DEFAULT 600000 CHECK (max_total_bet >= max_bet),
  max_payout_multiplier_bp INTEGER NOT NULL DEFAULT 100000 CHECK (max_payout_multiplier_bp BETWEEN 0 AND 1000000),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS game_rounds (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL REFERENCES game_registry(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'settling', 'settled', 'cancelled')),
  total_stake INTEGER NOT NULL DEFAULT 0 CHECK (total_stake >= 0),
  total_payout INTEGER NOT NULL DEFAULT 0 CHECK (total_payout >= 0),
  result_json TEXT,
  created_at TEXT NOT NULL,
  settled_at TEXT,
  settlement_id TEXT,
  UNIQUE (game_id, user_id, idempotency_key),
  CHECK ((status = 'open' AND settled_at IS NULL) OR (status <> 'open' AND settled_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_game_rounds_user_created
  ON game_rounds(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_rounds_player_created
  ON game_rounds(game_id, user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_rounds_game_status
  ON game_rounds(game_id, status, created_at);

CREATE TABLE IF NOT EXISTS game_bets (
  id TEXT PRIMARY KEY,
  round_id TEXT NOT NULL REFERENCES game_rounds(id) ON DELETE RESTRICT,
  game_id TEXT NOT NULL REFERENCES game_registry(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  stake INTEGER NOT NULL CHECK (stake > 0),
  selection_json TEXT NOT NULL DEFAULT '{}',
  payout INTEGER NOT NULL DEFAULT 0 CHECK (payout >= 0),
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'accepted', 'settled', 'cancelled')),
  created_at TEXT NOT NULL,
  settled_at TEXT,
  UNIQUE (round_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_game_bets_round_created
  ON game_bets(round_id, created_at);
CREATE INDEX IF NOT EXISTS idx_game_bets_user_created
  ON game_bets(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS game_wallet_ledger (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL REFERENCES game_registry(id) ON DELETE RESTRICT,
  round_id TEXT NOT NULL REFERENCES game_rounds(id) ON DELETE RESTRICT,
  bet_id TEXT REFERENCES game_bets(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  entry_type TEXT NOT NULL CHECK (entry_type IN ('bet_debit', 'payout_credit', 'refund_credit')),
  amount INTEGER NOT NULL CHECK (amount <> 0),
  balance_after INTEGER NOT NULL CHECK (balance_after >= 0),
  idempotency_key TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_game_wallet_ledger_user_created
  ON game_wallet_ledger(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_wallet_ledger_game_created
  ON game_wallet_ledger(game_id, created_at DESC);

-- Only a trusted game backend receives this credential. Browser game sessions cannot settle results.
CREATE TABLE IF NOT EXISTS game_server_keys (
  game_id TEXT PRIMARY KEY REFERENCES game_registry(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL UNIQUE,
  key_prefix TEXT NOT NULL,
  created_at TEXT NOT NULL,
  rotated_at TEXT,
  revoked_at TEXT
);
