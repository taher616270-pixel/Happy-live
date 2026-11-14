import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0039_game_registry.sql", import.meta.url), "utf8");
const statusMigration = await readFile(new URL("../migrations/0040_game_registry_status.sql", import.meta.url), "utf8");
const adminUi = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");
const appMain = await readFile(new URL("../../../frontend/lib/main.dart", import.meta.url), "utf8");
const gamesWidget = await readFile(new URL("../../../frontend/lib/widgets/dynamic_games_list.dart", import.meta.url), "utf8");

test("game registry migration is additive and does not touch wallet or existing game ledgers", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS game_registry/);
  assert.match(migration, /id TEXT PRIMARY KEY/);
  assert.match(migration, /game_url TEXT NOT NULL/);
  assert.match(migration, /enabled INTEGER NOT NULL DEFAULT 0/);
  assert.match(migration, /CHECK\(enabled IN \(0,1\)\)/);
  assert.doesNotMatch(migration, /DROP TABLE|DELETE FROM|UPDATE user_wallets|wallet_transactions|cat_greed_/i);
  assert.match(statusMigration, /ADD COLUMN status TEXT NOT NULL DEFAULT 'disabled'/);
  assert.match(statusMigration, /development.*disabled.*active/);
  assert.match(statusMigration, /UPDATE game_registry/);
  assert.doesNotMatch(statusMigration, /DROP TABLE|DELETE FROM|UPDATE user_wallets|wallet_transactions/i);
});

test("public game catalogue is read-only and returns enabled games only", () => {
  const start = worker.indexOf('// Public, read-only catalogue.');
  const end = worker.indexOf("const adminGamesRoute", start);
  assert.ok(start >= 0 && end > start);
  const route = worker.slice(start, end);
  assert.match(route, /url\.pathname === "\/api\/v1\/games\/catalog" && request\.method === "GET"/);
  assert.match(route, /status = 'active' AND enabled = 1/);
  assert.doesNotMatch(route, /INSERT INTO|UPDATE |DELETE FROM|wallet/i);
});

test("game administration requires a verified admin session and excludes moderator role", () => {
  const start = worker.indexOf("const adminGamesRoute");
  const end = worker.indexOf('if (url.pathname === "/api/v1/admin/auth/setup-status"', start);
  assert.ok(start >= 0 && end > start);
  const route = worker.slice(start, end);
  assert.match(route, /authenticatedAdmin\(request, env\.DB\)/);
  assert.match(route, /actor\.role !== "owner" && actor\.role !== "admin"/);
  assert.match(route, /request\.method === "POST"/);
  assert.match(route, /request\.method === "PATCH"/);
  assert.match(route, /isSafeExternalHttpsUrl\(gameUrl\)/);
  assert.match(route, /status = COALESCE\(\?, status\)/);
  assert.match(route, /game_url_required_before_activation/);
  assert.match(route, /development.*disabled.*active/);
  assert.match(route, /games\.create/);
  assert.match(route, /games\\.update/);
  assert.match(route, /admin_audit_logs/);
});

test("external game URLs reject unsafe schemes, IP literals and private host suffixes", () => {
  const start = worker.indexOf("function isSafeExternalHttpsUrl");
  const end = worker.indexOf("function isValidGiftSoundUrl", start);
  assert.ok(start >= 0 && end > start);
  const validator = worker.slice(start, end);
  assert.match(validator, /parsed\.protocol === "https:"/);
  assert.match(validator, /!hostname\.includes\(":"\) && !isIpv4Literal/);
  assert.match(validator, /\.localhost.*\.local.*\.internal/);
  assert.match(validator, /parsed\.username === "" && parsed\.password === ""/);
});

test("admin dashboard can create, edit, enable and disable registry entries", () => {
  assert.match(adminUi, /else if\(page==="games"\)await gamesPage\(\)/);
  assert.match(adminUi, /async function gamesPage\(/);
  assert.match(adminUi, /api\("\/admin\/games"/);
  assert.match(adminUi, /data-game-edit/);
  assert.match(adminUi, /data-game-status/);
  assert.match(adminUi, /gameStatus/);
  assert.match(adminUi, /قيد التطوير/);
  assert.match(adminUi, /مفعّلة/);
  assert.match(adminUi, /method:"PATCH"/);
  assert.match(adminUi, /esc\(g\.name\)/);
});

test("web app loads published games dynamically without replacing the native Food Wheel", () => {
  assert.match(appMain, /import 'pages\/food_wheel_game\.dart';/);
  assert.match(appMain, /openFoodWheelGame\(context, accessToken: accessToken\)/);
  assert.match(appMain, /if \(kIsWeb\) const DynamicGamesList\(\)/);
  assert.match(gamesWidget, /\/api\/v1\/games\/catalog/);
  assert.match(gamesWidget, /launchExternalGame\(url\)/);
  assert.match(gamesWidget, /إعادة المحاولة/);
  assert.doesNotMatch(gamesWidget, /wallet|bet|reward|accessToken/i);
});
