import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../migrations/0027_gift_economy_foundation.sql", import.meta.url), "utf8");
const categoriesMigration = await readFile(new URL("../migrations/0028_gift_categories_events_custom.sql", import.meta.url), "utf8");
const customGiftMediaMigration = await readFile(new URL("../migrations/0030_custom_gift_media.sql", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const adminPage = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");
const giftSheet = await readFile(new URL("../../../frontend/lib/widgets/room_gift_sheet.dart", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomSeatsHub = await readFile(new URL("../src/room_seats_hub.ts", import.meta.url), "utf8");

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

test("room gifts accept former room participants but reject unrelated users", () => {
  assert.ok(worker.includes(String.raw`const roomGiftSendRoute = url.pathname.match(/^\/api\/v1\/rooms\/([0-9a-f-]{36})\/gifts\/send$/i);`));
  assert.match(worker, /authenticatedUser\(request, env\.DB\)/);
  assert.match(worker, /EXISTS \(SELECT 1 FROM room_chat_visits v WHERE v\.room_id = r\.id AND v\.user_id = recipient\.id\)/);
  assert.match(worker, /recipient_not_room_member/);
  assert.doesNotMatch(worker, /JOIN room_chat_visits v ON v\.room_id = r\.id AND v\.user_id = recipient\.id AND v\.exited_at IS NULL/);
  assert.match(migration, /UNIQUE\(sender_user_id, idempotency_key\)/);
  assert.match(worker, /sender_balance_before/);
  assert.match(worker, /room_exp_gift_awards/);
  assert.match(worker, /gift_wallet_ledger/);
});

test("gift picker supports avatar recipients, all-recipient selection, and a preselected message recipient", () => {
  assert.match(giftSheet, /initialRecipientId/);
  assert.match(giftSheet, /_recipientIds/);
  assert.match(giftSheet, /Text\('الجميع'/);
  assert.match(giftSheet, /recipientIds\.length/);
  assert.match(roomPage, /_openRoomGiftPicker\(\{Map<String, dynamic>\? targetRecipient\}\)/);
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
  assert.ok(worker.includes(String.raw`const roomBattleRoute = url.pathname.match(/^\/api\/v1\/rooms\/([0-9a-f-]{36})\/battle$/i);`));
  assert.match(worker, /room_moderators WHERE room_id = \? AND user_id = \?/);
  assert.match(worker, /INSERT INTO room_battles/);
  assert.match(worker, /UPDATE room_battles SET status = 'finished'/);
  assert.match(worker, /CASE WHEN b\.id IS NULL THEN 1 ELSE 2 END/);
});

test("gift categories support weekly event windows and country-specific gifts", () => {
  assert.match(categoriesMigration, /category TEXT NOT NULL DEFAULT 'trending'/);
  assert.match(categoriesMigration, /'event', 'trending', 'country', 'lucky', 'custom'/);
  assert.match(categoriesMigration, /country_code TEXT/);
  assert.match(categoriesMigration, /starts_at TEXT/);
  assert.match(categoriesMigration, /ends_at TEXT/);
  assert.match(worker, /url\.searchParams\.get\("tab"\)/);
  assert.match(worker, /starts_at IS NULL OR starts_at <=/);
  assert.match(worker, /country_name/);
  assert.match(adminPage, /newGiftStarts/);
  assert.match(adminPage, /newGiftEnds/);
  assert.match(adminPage, /SOUTH_ARABIA/);
});

test("custom gift requests are authenticated, rate limited, and owner-reviewed", () => {
  assert.match(categoriesMigration, /CREATE TABLE IF NOT EXISTS gift_custom_requests/);
  assert.match(categoriesMigration, /status TEXT NOT NULL DEFAULT 'pending'/);
  assert.match(worker, /\/api\/v1\/gifts\/custom-requests/);
  assert.match(worker, /custom_gift_request_limit/);
  assert.match(worker, /owner_permission_required/);
  assert.match(worker, /INSERT INTO gift_catalog .*'custom'/);
  assert.match(adminPage, /giftCustomRequestRows/);
  assert.match(adminPage, /اعتماد وإنشاء/);
});

test("room gift sends enforce event windows and sender country eligibility", () => {
  assert.match(worker, /g\.starts_at IS NULL OR g\.starts_at <=/);
  assert.match(worker, /g\.ends_at IS NULL OR g\.ends_at >=/);
  assert.match(worker, /sender_profile\.country_name/);
  assert.match(worker, /g\.category <> 'country' OR g\.country_code = CASE/);
  assert.match(worker, /THEN 'SOUTH_ARABIA'/);
});

test("custom gift animation uploads use ImageKit and are limited to GIF/SVGA under five seconds", () => {
  assert.match(customGiftMediaMigration, /media_url TEXT/);
  assert.match(customGiftMediaMigration, /media_type IS NULL OR media_type IN \('gif', 'svga'\)/);
  assert.match(customGiftMediaMigration, /media_duration_ms BETWEEN 1 AND 5000/);
  assert.match(worker, /\/api\/v1\/imagekit\/auth/);
  assert.match(worker, /IMAGEKIT_PRIVATE_KEY/);
  assert.match(worker, /ik\.imagekit\.io/);
  assert.match(worker, /mediaDurationMs > 5000/);
  assert.match(worker, /media_file_id/);
  assert.match(worker, /type: "room_gift"/);
  assert.match(worker, /gifts\.room\.broadcast/);
  assert.match(roomSeatsHub, /url\.pathname === "\/gift"/);
  assert.match(roomPage, /_roomGiftFullscreenOverlay/);
  assert.match(worker, /lookupDelaysMs = \[400, 700, 1000, 1300, 1600, 2000, 2500\]/);
  assert.match(worker, /api\\.imagekit\\.io\\/v1\\/files\\/.*\\/details/);
  assert.match(worker, /imagekit_credentials_invalid/);
  assert.match(worker, /providerStatus/);
  assert.match(adminPage, /mediaUrl/);
  assert.match(adminPage, /عرض SVGA/);
});

test("custom gift creation UI uploads only selected GIF or SVGA files and sends the request for review", () => {
  assert.match(giftSheet, /allowedExtensions: const \['gif', 'svga'\]/);
  assert.match(giftSheet, /durationMs > 5000/);
  assert.match(giftSheet, /_customHome\(\)/);
  assert.match(roomPage, /upload\.imagekit\.io\/api\/v1\/files\/upload/);
  assert.match(roomPage, /mediaFileId/);
  assert.match(roomPage, /mediaDurationMs/);
});
