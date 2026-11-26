import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const callback = await readFile(new URL("src/platform_callback.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");
const admin = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");

test("Happy Food Wheel callback is mounted at the exact documented endpoint", () => {
  assert.ok(callback.includes('url.pathname !== "/v1/platform/handshake"'));
  assert.match(callback, /request\.method !== "POST"/);
  assert.match(worker, /handlePlatformCallbackRequest/);
});

test("callback authenticates the app-issued token by hash and binds it to the saved App ID", () => {
  assert.ok(callback.includes("Bearer\\s+(\\S{24,4096})"));
  assert.match(callback, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(callback, /happy_food_wheel_token_hash/);
  assert.match(callback, /constantTimeEqual\(appId, existing\.setting_value\)/);
  assert.match(worker, /happy_food_wheel_token_hash/);
});

test("callback echoes App ID, API version, UID when supplied, and one-time challenge", () => {
  assert.match(callback, /platform !== "Happy Food Wheel"/);
  assert.match(callback, /apiVersion !== "v1"/);
  assert.match(callback, /body\.uid === undefined/);
  assert.match(callback, /test_player_or_application_authentication_failed/);
  assert.match(callback, /happy_food_wheel_token_hash/);
  assert.doesNotMatch(callback, /validUtdPlayerToken|utd_test_session|handleUtdCallback/);
  assert.doesNotMatch(worker, /UTD_APP_KEY/);
  assert.ok(!worker.includes("/admin/utd/test-session"));
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", uid, challenge \}, 200\)/);
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", challenge \}, 200\)/);
  const handshakeStart = callback.indexOf("async function handleHappyFoodWheelHandshake(");
  const handshakeEnd = callback.indexOf("\nasync function happyFoodWheelCredential", handshakeStart);
  assert.ok(handshakeStart >= 0 && handshakeEnd > handshakeStart, "Happy Food Wheel handshake handler must remain present");
  const handshake = callback.slice(handshakeStart, handshakeEnd);
  assert.ok(!handshake.includes("if (!(await bindHappyFoodWheelAppId(db, appId)))"), "UID profile validation must not bind the app ID");
  assert.doesNotMatch(handshake, /user_wallets|wallet_transactions|game_wallet_ledger/);
});

test("Happy Food Wheel exposes authenticated player and idempotent wallet callbacks", () => {
  assert.ok(callback.includes('"/v1/platform/player"'));
  assert.ok(callback.includes('"/v1/platform/wallet/adjust"'));
  assert.match(callback, /happyFoodWheelCredential/);
  assert.match(callback, /invalid_application_credential/);
  assert.match(callback, /idempotency_conflict/);
  assert.match(callback, /insufficient_balance/);
  assert.ok(callback.includes('"happy-food-wheel:" + appId + ":" + gameId'));
  assert.ok(callback.includes("user_wallets SET balance=balance+?"));
});

test("Happy Food Wheel wallet adjustments are idempotent, app-scoped, and balance-safe", () => {
  assert.ok(callback.includes('"hfw:" + appId + ":" + orderId'));
  assert.ok(callback.includes('"happy-food-wheel:" + appId + ":" + gameId'));
  assert.match(callback, /prior\.user_id !== user\.id/);
  assert.match(callback, /prior\.round_id !== roundId/);
  assert.match(callback, /prior\.delta !== delta/);
  assert.match(callback, /INSERT OR IGNORE INTO platform_game_callback_orders/);
  assert.match(callback, /balance\+\?>=0/);
  assert.match(callback, /insufficient_balance/);
  assert.match(callback, /idempotency_conflict/);
  assert.match(callback, /UPDATE platform_game_callback_orders SET applied=1/);
});

test("legacy UTD order history is archived and copied without dropping financial rows", async () => {
  const migration = await readFile(new URL("migrations/0059_platform_game_callback_orders.sql", root), "utf8");
  assert.match(migration, /RENAME TO legacy_game_callback_orders_archive/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS platform_game_callback_orders/);
  assert.match(migration, /INSERT OR IGNORE INTO platform_game_callback_orders/);
  assert.match(migration, /FROM legacy_game_callback_orders_archive/);
  assert.doesNotMatch(migration, /DROP TABLE/i);
});

test("owner-only credential management returns the raw token only on creation", () => {
  assert.match(worker, /actor\.role !== "owner"/);
  assert.match(worker, /const apiToken = "hfw_live_"/);
  assert.match(worker, /setting_key, setting_value, updated_at/);
  assert.match(worker, /apiToken,/);
  assert.match(admin, /happy-food-wheel/);
  assert.doesNotMatch(admin, /utd-test-session|hfwIssueTest|UTD/i);
  assert.match(admin, /يظهر مرة واحدة فقط/);
  assert.match(admin, /مفتاح موحّد/);
});


test("Happy Food Wheel callback exposes a JSON deployment health response", () => {
  assert.match(callback, /ok: true, service: "happy-live-api", integration: "happy-food-wheel", endpoint:/);
  assert.match(callback, /request.method === "GET" \|\| request.method === "HEAD"/);
  assert.match(callback, /request.method === "HEAD"[\s\S]*?new Response\(null/);
});
