import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");
const migration = await read("../migrations/0051_room_cannon.sql");
const cannon = await read("../src/cannon_api.ts");
const worker = await read("../src/index.ts");
const preview = await read("../../../frontend/lib/pages/voice_room_design_preview.dart");
const cannonApi = await read("../../../frontend/lib/cannon/cannon_api.dart");
const cannonSheet = await read("../../../frontend/lib/cannon/cannon_sheet.dart");
const admin = await read("../../../frontend/web/admin/index.html");

test("cannon schema is room-scoped, daily, and idempotent per committed gift transaction", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS cannon_rooms/);
  assert.match(migration, /PRIMARY KEY \(room_id, day\)/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS cannon_energy_transactions/);
  assert.match(migration, /transaction_id TEXT PRIMARY KEY REFERENCES gift_transactions\(id\)/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS cannon_contrib/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS cannon_claims/);
});

test("cannon energy uses only server-confirmed successful gift transactions", () => {
  assert.match(cannon, /FROM gift_transactions WHERE id=\? AND status='succeeded'/);
  assert.match(cannon, /INSERT OR IGNORE INTO cannon_energy_transactions/);
  assert.match(worker, /addCannonEnergy\(env\.DB!, String\(transaction\.id\), roomId, user\.id, Number\(transaction\.coinCost/);
  assert.match(worker, /addCannonEnergy\(env\.DB!, String\(existing\.id\), roomId, user\.id/);
});

test("cannon client identity comes from the bearer session, not a user id parameter", () => {
  assert.match(cannon, /authenticateUser\(request, db\)/);
  assert.match(cannon, /room_chat_visits WHERE room_id=\? AND user_id=\? AND exited_at IS NULL AND last_seen_at>=\?/);
  assert.doesNotMatch(cannonApi, /user_id|userId\(\)/);
  assert.match(cannonApi, /queryParameters: \{\s*'room_id': roomId\s*\}/);
  assert.match(cannon, /claim_id/);
  assert.doesNotMatch(cannon, /body\.user_id|searchParams\.get\("user_id"\)/);
});

test("coin rewards are credited to the real wallet once and item rewards are persisted", () => {
  assert.match(cannon, /UPDATE user_wallets SET balance=balance\+\?/);
  assert.match(cannon, /INSERT OR IGNORE INTO cannon_wallet_ledger/);
  assert.match(cannon, /INSERT OR IGNORE INTO cannon_user_items/);
  assert.match(migration, /claim_id TEXT NOT NULL UNIQUE/);
});

test("cannon admin endpoint is separately authenticated and permission-gated", () => {
  assert.match(cannon, /authenticateAdmin\(request, db\)/);
  assert.match(cannon, /hasAdminPermission\(actor, "rooms.manage"\)/);
  assert.match(cannon, /hasAdminPermission\(actor, "rooms.read"\)/);
  assert.match(admin, /data-page="cannon"/);
  assert.match(admin, /\/admin\/cannon\/settings/);
});

test("cannon admin supports gallery uploads, editable levels, and rewards without JSON editing", () => {
  assert.match(admin, /async function uploadCannonImage/);
  assert.match(admin, /\/imagekit\/auth/);
  assert.match(admin, /data-level-field="title"/);
  assert.match(admin, /data-level-field="need"/);
  assert.match(admin, /data-add-prize/);
  assert.match(admin, /data-prize-image/);
  assert.match(admin, /اختيار صورة البنر/);
  assert.match(admin, /إضافة مستوى جديد/);
});

test("cannon levels can grow sequentially while protecting room progression", () => {
  assert.match(cannon, /levels\.length > 150/);
  assert.match(cannon, /levelId !== levelIds\.size \+ 1/);
  assert.match(cannon, /level\.level < Math\.max\(\.\.\.levels\.map\(x => x\.level\)\)/);
  assert.match(cannon, /level\?\.title !== undefined/);
  assert.match(cannon, /top1Count > 1/);
});

test("only the empty BET room tile opens the cannon sheet", () => {
  assert.match(preview, /showCannonSheet\(context, roomId: cannonRoomId, onSendGift: onOpenGifts\)/);
  assert.match(preview, /CannonService\.instance\.enterRoom\(cannonRoomId, accessToken\)/);
  assert.match(cannonSheet, /مدفع الغرفة/);
});
