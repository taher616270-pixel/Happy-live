-- Permanently remove the legacy Food Wheel game schema and all game-owned records.
-- Shared user_wallets balances and generic wallet_transactions are intentionally preserved.
PRAGMA foreign_keys = ON;

DROP TRIGGER IF EXISTS cat_greed_round_result_consistency_insert;
DROP TRIGGER IF EXISTS cat_greed_round_result_consistency_update;
DROP TRIGGER IF EXISTS cat_greed_bet_guard_insert;

DROP TABLE IF EXISTS cat_greed_ledger;
DROP TABLE IF EXISTS cat_greed_bet_requests;
DROP TABLE IF EXISTS cat_greed_bet_rate_limits;
DROP TABLE IF EXISTS cat_greed_state_rate_limits;
DROP TABLE IF EXISTS cat_greed_payouts;
DROP TABLE IF EXISTS cat_greed_bets;
DROP TABLE IF EXISTS cat_greed_player_controls;
DROP TABLE IF EXISTS cat_greed_admin_audit;
DROP TABLE IF EXISTS cat_greed_symbols;
DROP TABLE IF EXISTS cat_greed_settings;
DROP TABLE IF EXISTS cat_greed_rounds;
