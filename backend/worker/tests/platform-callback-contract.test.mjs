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

test("callback echoes the exact App ID, API version, and one-time challenge", () => {
  assert.match(callback, /platform !== "Happy Food Wheel"/);
  assert.match(callback, /apiVersion !== "v1"/);
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", challenge \}, 200\)/);
  assert.doesNotMatch(callback, /user_wallets|wallet_transactions|game_wallet_ledger/);
});

test("owner-only credential management returns the raw token only on creation", () => {
  assert.match(worker, /actor\.role !== "owner"/);
  assert.match(worker, /const apiToken = "hfw_live_"/);
  assert.match(worker, /setting_key, setting_value, updated_at/);
  assert.match(worker, /apiToken,/);
  assert.match(admin, /happy-food-wheel/);
  assert.match(admin, /لن يظهر مرة أخرى بعد مغادرة هذه الصفحة/);
});
