import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const api = await readFile(new URL("src/games_api.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");
const migration = await readFile(new URL("migrations/0041_game_sessions.sql", root), "utf8");
const bindingMigration = await readFile(new URL("migrations/0042_game_session_app_binding.sql", root), "utf8");
const happyIdMigration = await readFile(new URL("migrations/0043_rename_gabo_id_to_happy_id.sql", root), "utf8");
const economyMigration = await readFile(new URL("migrations/0045_game_economy_foundation.sql", root), "utf8");

test("temporary game sessions are isolated, expiring, revocable, and indexed", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS game_sessions/);
  assert.match(migration, /game_id TEXT NOT NULL REFERENCES game_registry\(id\)/);
  assert.match(migration, /user_id TEXT NOT NULL REFERENCES users\(id\)/);
  assert.match(bindingMigration, /CREATE TABLE IF NOT EXISTS game_session_app_bindings/);
  assert.match(bindingMigration, /app_session_id TEXT NOT NULL REFERENCES user_sessions\(id\)/);
  assert.match(bindingMigration, /game_session_id TEXT PRIMARY KEY REFERENCES game_sessions\(id\)/);
  assert.match(migration, /token_hash TEXT NOT NULL UNIQUE/);
  assert.match(migration, /expires_at TEXT NOT NULL/);
  assert.match(migration, /revoked_at TEXT/);
  assert.match(migration, /idx_game_sessions_expiry/);
  assert.doesNotMatch(migration, /DROP TABLE|DELETE FROM|UPDATE user_wallets|wallet_transactions/i);
});

test("game token exchange requires a real authenticated player and an active registered game", () => {
  assert.match(api, /authenticateUser\(request, db\)/);
  assert.match(api, /game\.status !== "active" \|\| game\.enabled !== 1/);
  assert.match(api, /GAME_SESSION_TTL_SECONDS = 15 \* 60/);
  assert.match(api, /await sha256\(sessionToken\)/);
  assert.match(api, /sessionToken,/);
});

test("game session refresh safely extends the existing token session", () => {
  assert.match(api, /\/api\/v1\/game\/session\/refresh/);
  assert.match(api, /if \(isRefresh\)/);
  assert.match(api, /UPDATE game_sessions SET expires_at = \?, last_seen_at = \?/);
  assert.match(api, /app\.revoked_at IS NULL AND app\.expires_at > \?/);
  assert.match(api, /game_session_refresh_denied/);
  assert.match(api, /refreshed\.meta\?\.changes/);
  assert.match(api, /expiresIn: GAME_SESSION_TTL_SECONDS/);
  assert.doesNotMatch(api, /INSERT INTO game_sessions .*SELECT \?, old\.game_id/);
});

test("game tokens are bound to one player, one game, and the registered game origin", () => {
  assert.match(api, /g\.id = s\.game_id/);
  assert.match(api, /u\.id = s\.user_id/);
  assert.match(api, /origin !== session\.gameOrigin/);
  assert.match(api, /game_origin/);
  assert.match(api, /INNER JOIN game_session_app_bindings app_binding/);
  assert.match(api, /INNER JOIN user_sessions app/);
  assert.match(api, /app.revoked_at IS NULL/);
  assert.match(api, /game_session_expired_or_invalid/);
  assert.match(api, /game_or_player_unavailable/);
});

test("game API scopes profile and wallet reads and limits each game session", () => {
  assert.match(api, /\["session\.read", "profile\.read", "wallet\.read", "round\.create", "round\.read", "bets\.place"\]/);
  assert.match(api, /GAME_SESSION_RATE_MAX_REQUESTS = 120/);
  assert.match(api, /profile\.read/);
  assert.match(api, /wallet\.read/);
});

test("worker routes the unified game API and only trusts registered HTTPS game origins", () => {
  assert.match(worker, /handleGamesApiRequest/);
  assert.match(worker, /isRegisteredGameOrigin/);
});

test("temporary game tokens are invalidated after a game URL origin change", () => {
  assert.match(api, /const currentGameOrigin = await gameOriginForId\(db, session\.gameId\)/);
  assert.match(api, /currentGameOrigin !== session\.gameOrigin/);
});

test("web game launcher exchanges the app session and never puts the game token in its URL", async () => {
  const widget = await readFile(new URL("../../../frontend/lib/widgets/dynamic_games_list.dart", import.meta.url), "utf8");
  const launcher = await readFile(new URL("../../../frontend/lib/services/game_link_launcher_web.dart", import.meta.url), "utf8");
  assert.match(widget, /SessionTokenStore\.read\(\)/);
  assert.match(widget, /\/game\/auth/);
  assert.match(widget, /launchExternalGame\(context, url/);
  assert.match(launcher, /postMessage/);
  assert.match(launcher, /HtmlElementView/);
  assert.match(launcher, /frame.contentWindow/);
  assert.match(launcher, /referrerpolicy/);
  assert.doesNotMatch(launcher, /window.open/);
  assert.match(launcher, /parsed\.origin/);
  assert.doesNotMatch(launcher, /searchParams\.set|\.fragment\b|\.queryParameters\b/);
});

test("game auth and profile expose only the player's public identity and verify active account status", () => {
  assert.match(api, /playerProfile = await db\.prepare/);
  assert.match(api, /id: publicPlayerId/);
  assert.match(api, /userCode: publicPlayerId/);
  assert.match(api, /avatarUrl: playerProfile\?\.avatarUrl/);
  assert.match(api, /accountStatus: "active"/);
  assert.match(api, /u\.status AS accountStatus/);
  assert.match(api, /profile\.accountStatus !== "active"/);
  assert.match(api, /player_account_unavailable/);
  assert.doesNotMatch(api, /id: user\.id/);
});


test("public player identifier is renamed to happy_id without changing existing IDs", () => {
  assert.match(happyIdMigration, /ALTER TABLE profiles RENAME COLUMN gabo_id TO happy_id/i);
  assert.match(api, /happy_id/);
  assert.match(worker, /happy_id/);
  assert.doesNotMatch(api, /gabo_id/);
  assert.doesNotMatch(worker, /gabo_id/);
});


test("game economy schema is additive and isolated from the legacy Food Wheel ledger", () => {
  assert.match(economyMigration, /CREATE TABLE IF NOT EXISTS game_economy_settings/);
  assert.match(economyMigration, /CREATE TABLE IF NOT EXISTS game_rounds/);
  assert.match(economyMigration, /CREATE TABLE IF NOT EXISTS game_bets/);
  assert.match(economyMigration, /UNIQUE \(game_id, user_id, idempotency_key\)/);
  assert.match(economyMigration, /UNIQUE \(round_id, idempotency_key\)/);
  assert.match(economyMigration, /CREATE TABLE IF NOT EXISTS game_wallet_ledger/);
  assert.match(economyMigration, /CREATE TABLE IF NOT EXISTS game_server_keys/);
  assert.match(economyMigration, /key_hash TEXT NOT NULL UNIQUE/);
  assert.doesNotMatch(economyMigration, /DROP TABLE|DELETE FROM|cat_greed_|food_wheel|wallet_transactions/i);
  assert.doesNotMatch(economyMigration, /UPDATE user_wallets|INSERT INTO user_wallets/i);
});

test("game bets debit the canonical wallet once and append a separate game ledger entry", () => {
  assert.match(api, /INSERT OR IGNORE INTO game_bets/);
  assert.match(api, /UPDATE user_wallets SET balance = balance - \?/);
  assert.match(api, /changes\(\) = 1/);
  assert.match(api, /INSERT INTO game_wallet_ledger/);
  assert.match(api, /"bet:" \+ betId/);
  assert.match(api, /insufficient_balance/);
  assert.match(api, /max_bets_per_round/);
  assert.match(api, /max_total_bet/);
});

test("only a game-server credential can settle a round and payouts are capped", () => {
  assert.match(api, /X-Happy-Live-Game-Key/);
  assert.match(api, /server_to_server_only/);
  assert.match(api, /key_hash = \?/);
  assert.match(api, /settlement_bet_set_mismatch/);
  assert.match(api, /settlement_payout_limit_exceeded/);
  assert.match(api, /status = 'settling'/);
  assert.match(api, /payout_credit/);
  assert.match(api, /payout:" \+ roundId/);
  assert.match(api, /acceptedStakeTotal !== round\.totalStake/);
  assert.match(api, /total_stake = \? AND \(SELECT COALESCE\(SUM\(stake\), 0\) FROM game_bets WHERE round_id = \? AND status = 'accepted'\) = \?/);
});

test("admin economy activation requires an active game and a provisioned server key", () => {
  assert.match(api, /authenticateAdmin\(request, db\)/);
  assert.match(api, /game_must_be_active_before_economy/);
  assert.match(api, /game_server_key_required_before_economy/);
  assert.match(api, /games\.economy\.update/);
  assert.match(api, /games\.server_key\.rotate/);
  assert.match(api, /VALUES \(\?, NULL, 'games\.server_key\.rotate'/);
  assert.match(api, /await sha256\(serverKey\)/);
  assert.match(worker, /authenticatedUser, json, authenticatedAdmin/);
});

test("trusted game backend can cancel an aborted round and refund exact accepted stakes", () => {
  assert.match(api, /serverCancelMatch = path\.match/);
  assert.match(api, /game_round_ledger_mismatch/);
  assert.match(api, /refund_credit/);
  assert.match(api, /"refund:" \+ roundId/);
  assert.match(api, /status = 'cancelled'/);
  assert.match(api, /total_stake = \? AND \(SELECT COALESCE\(SUM\(stake\), 0\) FROM game_bets WHERE round_id = \? AND status = 'accepted'\) = \?/);
  assert.match(api, /SELECT COUNT\(\*\) FROM game_bets WHERE round_id = \? AND status = 'accepted'/);
  assert.match(api, /\? = 0 OR EXISTS \(SELECT 1 FROM user_wallets WHERE user_id = \?\)/);
});


test("players can retrieve a bounded history of their own game rounds", () => {
  assert.match(api, /isListRounds/);
  assert.match(api, /WHERE game_id = \? AND user_id = \? ORDER BY created_at DESC LIMIT 50/);
  assert.match(api, /round\.read/);
});


test("admin round history is scoped to one game and exposes public player identifiers only", () => {
  assert.match(api, /adminRoundsMatch/);
  assert.match(api, /ORDER BY r\.created_at DESC LIMIT 100/);
  assert.match(api, /COALESCE\(p\.happy_id, ''\) AS userCode/);
  assert.doesNotMatch(api, /SELECT r\.user_id/);
});

test("concurrent bet idempotency-key reuse cannot acknowledge a different stake or selection", () => {
  assert.match(api, /accepted\.stake !== Number\(stake\) \|\| accepted\.selectionJson !== selectionJson/);
  assert.match(api, /error: "idempotency_key_reused"/);
});
