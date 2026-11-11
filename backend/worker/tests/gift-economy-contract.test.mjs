import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../migrations/0027_gift_economy_foundation.sql", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const adminPage = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");

test("gift revenue split defaults to 30/70 and is constrained to 100 percent", () => {
  assert.match(migration, /DEFAULT 30/);
  assert.match(migration, /DEFAULT 70/);
  assert.match(migration, /CHECK \(app_percent \+ recipient_percent = 100\)/);
});

test("withdrawals are disabled until future agency integration", () => {
  assert.match(migration, /withdrawals_enabled INTEGER NOT NULL DEFAULT 0/);
  assert.match(migration, /enabled INTEGER NOT NULL DEFAULT 0/);
  assert.match(migration, /agency_integration_ready INTEGER NOT NULL DEFAULT 0/);
  assert.match(worker, /ready: false/);
  assert.match(adminPage, /طلبات السحب والتحويل النقدي مغلقة حاليًا/);
});

test("gift transactions preserve the revenue split and use sender-scoped idempotency", () => {
  assert.match(migration, /app_percent_snapshot INTEGER NOT NULL/);
  assert.match(migration, /recipient_percent_snapshot INTEGER NOT NULL/);
  assert.match(migration, /UNIQUE\(sender_user_id, idempotency_key\)/);
});

test("gift earnings are tagged and future withdrawal eligibility cannot exceed unspent tagged coins", () => {
  assert.match(migration, /remaining_tagged_coins INTEGER NOT NULL CHECK \(remaining_tagged_coins >= 0 AND remaining_tagged_coins <= credited_coins\)/);
  assert.match(migration, /remaining_withdrawable_coins INTEGER NOT NULL CHECK \(remaining_withdrawable_coins >= 0 AND remaining_withdrawable_coins <= remaining_tagged_coins\)/);
});

test("room battle multiplier is stored server-side and no private-gift room XP is configured", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_battles/);
  assert.match(migration, /experience_multiplier INTEGER NOT NULL DEFAULT 1 CHECK \(experience_multiplier IN \(1, 2\)\)/);
  assert.match(migration, /context_type TEXT NOT NULL CHECK \(context_type IN \('room', 'private'\)\)/);
});

test("admin gift split endpoint validates the sum and limits edits to the owner", () => {
  assert.match(worker, /url\.pathname === "\/api\/v1\/admin\/gifts\/settings"/);
  assert.match(worker, /appPercent \+ recipientPercent !== 100/);
  assert.match(worker, /request\.method === "PATCH" && actor\.role !== "owner"/);
  assert.match(worker, /gift_revenue_settings_audit/);
});

test("admin console exposes the real gift revenue settings endpoint", () => {
  assert.match(adminPage, /async function giftsPage\(\)/);
  assert.match(adminPage, /\/admin\/gifts\/settings/);
  assert.match(adminPage, /حفظ نسب الأرباح/);
});
