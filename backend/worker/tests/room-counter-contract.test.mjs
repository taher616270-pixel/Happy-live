import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const seatHub = await readFile(new URL("../src/room_seats_hub.ts", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");

test("room gift counter is a timed room-wide feature with manual and automatic stop", () => {
  assert.match(seatHub, /message\.type === "start_room_counter" \|\| message\.type === "stop_room_counter" \|\| message\.type === "get_room_counter_history"/);
  const counterHandler = seatHub.slice(seatHub.indexOf('if (message.type === "start_room_counter"'), seatHub.indexOf('if (message.type === "seat_heartbeat"'));
  assert.doesNotMatch(counterHandler, /permission_denied/);
  assert.match(seatHub, /durationSeconds < 60 \|\| durationSeconds > 3600/);
  assert.match(seatHub, /endsAt: startedAt \+ durationSeconds \* 1000/);
  assert.match(seatHub, /this\.state\.storage\.put\("room-counter", this\.roomCounter\)/);
  assert.match(seatHub, /this\.broadcast\(\{ type: "room_counter", counter: null, reason: "expired" \}\)/);
  assert.match(seatHub, /private async scheduleExpiry\(\)[\s\S]*?expiries\.push\(this\.roomCounter\.endsAt\)/);
  assert.match(seatHub, /private async finishRoomCounter\([\s\S]*?room-counter-history/);
  assert.match(seatHub, /private publicRoomCounterHistory\(\)/);
  assert.match(roomPage, /_showRoomCounterHistory\(records\)/);
});

test("gift score is credited to the recipient using committed server-priced coins exactly once", () => {
  assert.match(worker, /coinCost: Number\(transaction\.coinCost \?\? 0\)/);
  assert.match(seatHub, /const recipientUserId = String\(event\.recipientUserId \?\? ""\)\.trim\(\)/);
  assert.match(seatHub, /const transactionId = String\(event\.transactionId \?\? ""\)\.trim\(\)/);
  assert.match(seatHub, /Number\.isSafeInteger\(coinCost\) && coinCost > 0/);
  assert.match(seatHub, /!this\.roomCounter\.processedTransactions\.includes\(transactionId\)/);
  assert.match(seatHub, /scores\[recipientUserId\] = \(Number\(scores\[recipientUserId\]\) \|\| 0\) \+ coinCost/);
  assert.match(seatHub, /this\.roomCounter\.processedTransactions\.push\(transactionId\)/);
  assert.match(seatHub, /await this\.enqueue\(async \(\) => \{[\s\S]*?this\.broadcast\(\{ \.\.\.event, type: "room_gift" \}\)/);
});

test("room counter sync survives reconnects without exposing idempotency internals", () => {
  assert.match(seatHub, /this\.send\(server, \{ type: "room_counter", counter: this\.publicRoomCounter\(\) \}\)/);
  assert.match(seatHub, /private publicRoomCounter\(\)[\s\S]*?scores: this\.roomCounter\.scores/);
  assert.doesNotMatch(seatHub.match(/private publicRoomCounter\(\)[\s\S]*?\n  \}/)?.[0] ?? "", /processedTransactions/);
});

test("Flutter shows the orange timer control and per-recipient green mic score badges", () => {
  assert.match(roomPage, /roomGiftScores: _roomGiftScores/);
  assert.match(roomPage, /isRoomGiftCounterActive: _roomCounter != null/);
  assert.match(roomPage, /Color\(0xFFFFA21A\)/);
  assert.match(roomPage, /stop_room_counter/);
  assert.match(roomPage, /_roomCounterTicker = Timer\.periodic\(const Duration\(seconds: 1\)/);
  assert.match(roomPreview, /roomGiftScores\[\(seat\?\['userId'\] \?\? ''\)\.toString\(\)\] \?\? 0/);
  assert.match(roomPreview, /if \(occupied && isRoomGiftCounterActive\)/);
  assert.match(roomPreview, /Color\(0xFF00BFA5\)/);
});
