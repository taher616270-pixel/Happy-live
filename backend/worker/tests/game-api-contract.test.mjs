import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const api = await readFile(new URL("src/games_api.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");
const migration = await readFile(new URL("migrations/0041_game_sessions.sql", root), "utf8");
const bindingMigration = await readFile(new URL("migrations/0042_game_session_app_binding.sql", root), "utf8");

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
  assert.match(api, /UPDATE game_sessions SET revoked_at = \?/);
  assert.match(api, /INSERT INTO game_sessions .*SELECT \?, old\.game_id, old\.user_id/);
  assert.match(api, /INSERT INTO game_session_app_bindings .*SELECT \?, app_session_id/);
  assert.match(api, /app\.revoked_at IS NULL AND app\.expires_at > \?/);
  assert.match(api, /game_session_refresh_denied/);
  assert.match(api, /expiresIn: GAME_SESSION_TTL_SECONDS/);
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

test("game API grants read-only profile and wallet scopes with per-session rate limiting", () => {
  assert.match(api, /\["session\.read", "profile\.read", "wallet\.read"\]/);
  assert.match(api, /GAME_SESSION_RATE_MAX_REQUESTS = 120/);
  assert.match(api, /profile\.read/);
  assert.match(api, /wallet\.read/);
  assert.doesNotMatch(api, /UPDATE user_wallets|INSERT INTO wallet_transactions|DELETE FROM user_wallets/);
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
  assert.match(launcher, /postMessage/);
  assert.match(launcher, /parsed\.origin/);
  assert.doesNotMatch(launcher, /searchParams\.set|\.fragment\b|\.queryParameters\b/);
});
