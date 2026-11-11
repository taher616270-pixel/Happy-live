import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const seatHub = await readFile(new URL("../src/room_seats_hub.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0026_room_experience_progression.sql", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");

const progressSource = worker.match(/function roomExperienceProgress\(totalExperience: number\) \{[\s\S]*?\n\}/)?.[0];
assert.ok(progressSource, "room experience progression function must exist");
const roomExperienceProgress = new Function(
  `${progressSource.replace("(totalExperience: number)", "(totalExperience)")}; return roomExperienceProgress;`
)() as (totalExperience: number) => { level: number; exp: number; nextLevelExp: number };

test("room experience follows the approved five-level bands", () => {
  assert.deepEqual(roomExperienceProgress(0), { level: 1, exp: 0, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(3_299_999), { level: 1, exp: 3_299_999, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(3_300_000), { level: 2, exp: 0, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(16_499_999), { level: 5, exp: 3_299_999, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(16_500_000), { level: 6, exp: 0, nextLevelExp: 6_600_000 });
  assert.deepEqual(roomExperienceProgress(49_500_000), { level: 11, exp: 0, nextLevelExp: 9_900_000 });
});

test("experience progression has no level cap at 120", () => {
  assert.deepEqual(roomExperienceProgress(4_950_000_000), {
    level: 121,
    exp: 0,
    nextLevelExp: 82_500_000,
  });
});

test("only continuous microphone occupancy awards room experience", () => {
  assert.match(seatHub, /message\.type === "seat_heartbeat"/);
  assert.match(seatHub, /awardRoomSeatExperience\(this\.env\.DB, this\.roomId, identity\.userId/);
  assert.match(seatHub, /resetRoomSeatExperienceTimer\(this\.env\.DB, this\.roomId, identity\.userId/);
  assert.match(seatHub, /< 300_000/);
});

test("daily contribution cap and persistent room experience tables are enforced", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_experience/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_exp_activity/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_exp_daily/);
  assert.match(migration, /points <= 3000000/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS room_exp_awards/);
  assert.match(seatHub, /ROOM_EXP_DAILY_USER_CAP = 3_000_000/);
});

test("room UI reads server experience separately from paid room tier", () => {
  assert.match(worker, /experienceLevel: experience\.level/);
  assert.match(worker, /experienceTotalExp: Number\(room\.total_exp \?\? 0\)/);
  assert.match(roomPage, /_roomExperienceLevel = nextExperienceLevel/);
  assert.match(roomPreview, /\['experienceLevel', 'experience_level'\]/);
  assert.match(roomPreview, /\['experienceExp', 'experience_exp'\]/);
  assert.match(roomPage, /'level': _roomLevel, 'experienceLevel': _roomExperienceLevel/);
});
