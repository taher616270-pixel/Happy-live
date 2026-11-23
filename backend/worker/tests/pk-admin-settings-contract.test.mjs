import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const adminPage = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");
const pkSheet = await readFile(new URL("../../../frontend/lib/pk/pk_sheet.dart", import.meta.url), "utf8");

test("PK settings are owner-managed and publicly readable for room presentation", () => {
  assert.match(worker, /\/api\/v1\/pk\/settings/);
  assert.match(worker, /\/api\/v1\/admin\/pk\/settings/);
  assert.match(worker, /actor\.role !== "owner"/);
  assert.match(worker, /pk_battle_settings/);
});

test("PK admin controls title, GIF or SVGA media, text visibility, square style and durations", () => {
  assert.match(adminPage, /data-page="pk"/);
  assert.match(adminPage, /uploadPkMedia/);
  assert.match(adminPage, /\["gif","svga"\]/);
  assert.match(adminPage, /pkShowTitle/);
  assert.match(adminPage, /pkShowStart/);
  assert.match(adminPage, /pkShowTimer/);
  assert.match(adminPage, /pkDurations/);
  assert.match(adminPage, /pkRadius/);
  assert.match(adminPage, /pkStartShowDuration/);
  assert.match(adminPage, /pkStartHideDuration/);
  assert.match(adminPage, /pkStartMediaFile/);
  assert.match(worker, /startShowDurationSeconds/);
  assert.match(worker, /startHideDurationSeconds/);
  assert.match(roomPage, /_pkStartShowDurationSeconds/);
  assert.match(roomPage, /_buildPkStartAnimation/);
  assert.match(roomPreview, /pkStartHiding/);
});

test("room PK uses admin-configured animation, title, timer and duration options", () => {
  assert.match(roomPage, /_loadPkSettings/);
  assert.match(roomPage, /SVGAEasyPlayer/);
  assert.match(roomPage, /GifView\.network/);
  assert.match(roomPage, /pkMediaOpacity:/);
  assert.match(roomPage, /durationOptions: _pkDurationOptions/);
  assert.match(roomPreview, /pkSquareAnimation/);
  assert.match(roomPreview, /pkShowChallengeTitle/);
  assert.match(roomPreview, /pkShowStartText/);
  assert.match(roomPreview, /pkShowTimer/);
  assert.match(pkSheet, /for \(final m in durationOptions\)/);
});

test("server rejects PK starts when disabled and enforces configured duration choices", () => {
  assert.match(worker, /pk_disabled_by_admin/);
  assert.match(worker, /configuredDurationOptions\.includes\(durationMinutes\)/);
});
