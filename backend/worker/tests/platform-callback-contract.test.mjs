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
  assert.match(callback, /constantTimeEqual\(appId, savedAppId\.setting_value\)/);
  assert.match(worker, /happy_food_wheel_token_hash/);
});

test("callback echoes App ID, API version, UID when supplied, and one-time challenge", () => {
  assert.match(callback, /platform !== "Happy Food Wheel"/);
  assert.match(callback, /apiVersion !== "v1"/);
  assert.match(callback, /body\.uid === undefined/);
  assert.match(callback, /test_player_not_found_or_inactive/);
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", uid, challenge \}, 200\)/);
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", challenge \}, 200\)/);
  const handshakeStart = callback.indexOf("async function handleHappyFoodWheelHandshake(");
  const handshakeEnd = callback.indexOf("\nexport async function handlePlatformCallbackRequest", handshakeStart);
  assert.ok(handshakeStart >= 0 && handshakeEnd > handshakeStart, "Happy Food Wheel handshake handler must remain present");
  const handshake = callback.slice(handshakeStart, handshakeEnd);
  assert.doesNotMatch(handshake, /user_wallets|wallet_transactions|game_wallet_ledger/);
});

test("Happy Food Wheel exposes authenticated player and idempotent wallet callbacks", () => {
  assert.match(callback, /"\\/v1\\/platform\\/player"/);
  assert.match(callback, /"\\/v1\\/platform\\/wallet\\/adjust"/);
  assert.match(callback, /happyFoodWheelCredential/);
  assert.match(callback, /invalid_application_credential/);
  assert.match(callback, /idempotency_conflict/);
  assert.match(callback, /insufficient_balance/);
  assert.match(callback, /happy-food-wheel:\\" \\+ appId/);
  assert.match(callback, /user_wallets SET balance=balance\\+\\?/);
});

test("owner-only credential management returns the raw token only on creation", () => {
  assert.match(worker, /actor\.role !== "owner"/);
  assert.match(worker, /const apiToken = "hfw_live_"/);
  assert.match(worker, /setting_key, setting_value, updated_at/);
  assert.match(worker, /apiToken,/);
  assert.match(admin, /happy-food-wheel/);
  assert.match(admin, /لن يظهر مرة أخرى بعد مغادرة هذه الصفحة/);
});
