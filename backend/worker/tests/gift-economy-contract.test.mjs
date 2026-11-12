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
  assert.match(migration, /context_type TEXT NOT NULL DEFAULT 'room' CHECK \(context_type = 'room'\)/);
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

 
test("gift catalogue migration seeds three premium priced gifts", () => {
  assert.match(migration, /'وردة الألماس', '💎', '', 999, 1/);
  assert.match(migration, /'قصر الذهب', '🏰', '', 4999, 1/);
  assert.match(migration, /'يخت الملوك', '🛥️', '', 9999, 1/);
  assert.match(migration, /icon_emoji TEXT NOT NULL/);
});

test("gift catalogue has owner-only management and public active listing", () => {
  assert.match(worker, /\/api\/v1\/admin\/gifts\/catalog/);
  assert.match(worker, /actor\.role !== "owner"/);
  assert.match(worker, /INSERT INTO gift_catalog/);
  assert.match(worker, /UPDATE gift_catalog SET name/);
  assert.match(worker, /\/api\/v1\/gifts\/catalog/);
  assert.match(adminPage, /giftCreateForm/);
  assert.match(adminPage, /data-gift-edit/);
});

test("room gift sending is authenticated, presence-checked, idempotent, and server-awards XP", () => {
  assert.match(worker, /\/api\/v1\/rooms\/\(\[0-9a-f-\]\{36\}\)\/gifts\/send/);
  assert.match(worker, /authenticatedUser\(request, env\.DB\)/);
  assert.match(worker, /last_seen_at >= \?/);
  assert.match(worker, /UNIQUE\(sender_user_id, idempotency_key\)/);
  assert.match(worker, /sender_balance_before/);
  assert.match(worker, /room_exp_gift_awards/);
  assert.match(worker, /gift_wallet_ledger/);
});

test("private gifts remain disabled until private conversations are implemented", () => {
  assert.match(migration, /context_type TEXT NOT NULL DEFAULT 'room' CHECK \(context_type = 'room'\)/);
  assert.doesNotMatch(worker, /\/api\/v1\/private\/.*gifts/);
});

test("wallet reports tagged earnings and room-upgrade spending consumes tagged lots FIFO", () => {
  assert.match(worker, /futureWithdrawableCoins/);
  assert.match(worker, /remaining_withdrawable_coins = MAX\(0, remaining_withdrawable_coins/);
  assert.match(worker, /ORDER BY created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING/);
});

test("battle multiplier can only be enabled through owner/moderator server-side battle state", () => {
  assert.match(worker, /\/api\/v1\/rooms\/\(\[0-9a-f-\]\{36\}\)\/battle/);
  assert.match(worker, /room_moderators WHERE room_id = \? AND user_id = \?/);
  assert.match(worker, /INSERT INTO room_battles/);
  assert.match(worker, /UPDATE room_battles SET status = 'finished'/);
  assert.match(worker, /CASE WHEN b\.id IS NULL THEN 1 ELSE 2 END/);
});
