import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const callback = await readFile(new URL("src/platform_callback.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");

test("Happy Food Wheel onboarding callback validates the exact public endpoint and method", () => {
  assert.match(callback, /\/v1\/platform\/handshake/);
  assert.match(callback, /request\.method !== "POST"/);
  assert.match(worker, /handlePlatformCallbackRequest/);
});

test("callback authenticates an active, unexpired Happy Live app session and matches the public player UID", () => {
  assert.match(callback, /Bearer\\s\+/);
  assert.match(callback, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(callback, /FROM user_sessions s INNER JOIN users u/);
  assert.match(callback, /s\.revoked_at IS NULL AND s\.expires_at > \?/);
  assert.match(callback, /u\.status/);
  assert.match(callback, /constantTimeEqual\(account\.publicUid, uid\)/);
});

test("callback returns the exact challenge-bound handshake response and does not touch wallets", () => {
  assert.match(callback, /platform !== "Happy Food Wheel"/);
  assert.match(callback, /apiVersion !== "v1"/);
  assert.match(callback, /return reply\(\{ ok: true, appId, apiVersion: "v1", uid, challenge \}, 200\)/);
  assert.doesNotMatch(callback, /user_wallets|wallet_transactions|game_wallet_ledger/);
});
