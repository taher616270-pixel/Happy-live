import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../migrations/0034_room_battle_gift_scores.sql", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const hub = await readFile(new URL("../src/room_seats_hub.ts", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");
const pkSheet = await readFile(new URL("../../../frontend/lib/pk/pk_sheet.dart", import.meta.url), "utf8");

test("PK gift points are persisted once per successful gift transaction and attributed to the recipient mic team", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_battle_gift_scores/);
  assert.match(migration, /gift_transaction_id TEXT NOT NULL UNIQUE/);
  assert.match(migration, /team TEXT NOT NULL CHECK \(team IN \('blue', 'red'\)\)/);
  assert.match(migration, /seat_number INTEGER NOT NULL CHECK \(seat_number BETWEEN 1 AND 12\)/);
  assert.match(worker, /pkRecipientTeam = \[3, 4, 7, 8, 11, 12\]\.includes\(seatNumber\) \? "blue" : "red"/);
  assert.match(worker, /t\.coin_cost, \?/);
  assert.match(worker, /INSERT OR IGNORE INTO room_battle_gift_scores/);
  assert.match(worker, /b\.expires_at IS NULL OR b\.expires_at > \?/);
});

test("PK rounds support the four configured durations and preserve stop versus reset behavior", () => {
  assert.match(worker, /\[5, 15, 30, 120\]\.includes\(durationMinutes\)/);
  assert.match(worker, /action === "prepare"/);
  assert.match(worker, /const teamMode = action === "end"/);
  assert.match(worker, /teamMode: true, active: false/);
  assert.match(worker, /teamMode, active: false, battleId: keepBattleId/);
  assert.match(hub, /private async finishRoomBattle\(/);
  assert.match(hub, /this\.roomBattleEndsAt/);
  assert.match(hub, /await this\.finishRoomBattle\(\)/);
});

test("PK score totals and individual recipient scores are broadcast from D1 to every room socket", () => {
  assert.match(hub, /FROM room_battle_gift_scores WHERE battle_id = \? GROUP BY team, user_id/);
  assert.match(hub, /type: "room_battle_score"/);
  assert.match(worker, /\/battle-score\/broadcast/);
  assert.match(roomPage, /type == 'room_battle_score'/);
  assert.match(roomPage, /_pkBlueScore/);
  assert.match(roomPage, /_pkRedScore/);
  assert.match(roomPage, /_pkUserScores/);
});

test("PK UI uses live team totals and shows each seated recipient's earned points", () => {
  assert.match(roomPreview, /blue: calculatedBlueScore/);
  assert.match(roomPreview, /red: calculatedRedScore/);
  assert.match(roomPreview, /final pkPoints = pkUserScores\[userId\] \?\? 0/);
  assert.match(roomPreview, /if \(occupied && pkPoints > 0\)/);
  assert.match(pkSheet, /selectedDurationMinutes/);
  assert.match(pkSheet, /onDurationChanged/);
});
