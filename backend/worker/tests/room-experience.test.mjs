import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const seatHub = await readFile(new URL("../src/room_seats_hub.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0026_room_experience_progression.sql", import.meta.url), "utf8");
const roomPage = await readFile(new URL("../../../frontend/lib/pages/room_page.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");
const roomLevelSheet = await readFile(new URL("../../../frontend/lib/widgets/room_level_sheet.dart", import.meta.url), "utf8");
const roomSeatSocket = await readFile(new URL("../../../frontend/lib/services/room_seat_socket.dart", import.meta.url), "utf8");

const progressSource = worker.match(/function roomExperienceProgress\(totalExperience: number\) \{[\s\S]*?\n\}/)?.[0];
assert.ok(progressSource, "room experience progression function must exist");
const roomExperienceProgress = new Function(
  `const ROOM_EXP_PER_LEVEL_GROUP = 3_300_000; ${progressSource.replace("(totalExperience: number)", "(totalExperience)")}; return roomExperienceProgress;`
)();

test("room experience follows the cost band of the level being entered", () => {
  assert.deepEqual(roomExperienceProgress(0), { level: 1, exp: 0, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(3_299_999), { level: 1, exp: 3_299_999, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(3_300_000), { level: 2, exp: 0, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(13_199_999), { level: 4, exp: 3_299_999, nextLevelExp: 3_300_000 });
  assert.deepEqual(roomExperienceProgress(13_200_000), { level: 5, exp: 0, nextLevelExp: 6_600_000 });
  assert.deepEqual(roomExperienceProgress(16_499_999), { level: 5, exp: 3_299_999, nextLevelExp: 6_600_000 });
  assert.deepEqual(roomExperienceProgress(19_800_000), { level: 6, exp: 0, nextLevelExp: 6_600_000 });
  assert.deepEqual(roomExperienceProgress(46_200_000), { level: 10, exp: 0, nextLevelExp: 9_900_000 });
  assert.deepEqual(roomExperienceProgress(56_100_000), { level: 11, exp: 0, nextLevelExp: 9_900_000 });
  assert.deepEqual(roomExperienceProgress(Number.NaN), { level: 1, exp: 0, nextLevelExp: 3_300_000 });
});

test("experience progression continues beyond level 120 with the next band's cost", () => {
  assert.deepEqual(roomExperienceProgress(4_946_700_000), {
    level: 120,
    exp: 0,
    nextLevelExp: 82_500_000,
  });
  assert.deepEqual(roomExperienceProgress(4_950_000_000), {
    level: 120,
    exp: 3_300_000,
    nextLevelExp: 82_500_000,
  });
});

test("Flutter level sheet uses the same target-level cost bands as the Worker", () => {
  const helperSource = roomLevelSheet.match(/int roomLevelRequiredExpForLevel\(int targetLevel\) \{[\s\S]*?\n\}/)?.[0];
  assert.ok(helperSource, "Flutter room level cost helper must exist");
  const requiredExp = new Function(
    `${helperSource.replace("int roomLevelRequiredExpForLevel", "function roomLevelRequiredExpForLevel").replace("(int targetLevel)", "(targetLevel)")}; return roomLevelRequiredExpForLevel;`
  )();
  for (const targetLevel of [2, 5, 6, 10, 11, 15, 16, 120, 121]) {
    const expected = (Math.floor((targetLevel - 1) / 5) + 1) * 3_300_000;
    assert.equal(requiredExp(targetLevel), expected, `wrong cost for target level ${targetLevel}`);
  }
  assert.equal(roomExperienceProgress(13_200_000).nextLevelExp, requiredExp(6));
  assert.equal(roomExperienceProgress(46_200_000).nextLevelExp, requiredExp(11));
});

test("microphone heartbeat is sent periodically and experience is only credited by server seat presence", () => {
  assert.match(roomSeatSocket, /Timer\.periodic\(const Duration\(seconds: 15\)/);
  assert.match(seatHub, /const member = Object\.values\(this\.snapshot\.seats\)\.find\(\(seat\) => seat\.userId === identity\.userId\)/);
  assert.match(seatHub, /if \(member\) \{[\s\S]*?awardRoomSeatExperience\(this\.env\.DB, this\.roomId, identity\.userId/);
  assert.match(worker, /if \(isOnMic\) \{[\s\S]*?awardRoomSeatExperience\(env\.DB, roomId, user\.id, now\)/);
  assert.match(worker, /Only continuous microphone time counts; audience time resets the 5-minute clock/);
  assert.match(worker, /if \(moveData\.from !== moveData\.mySeat\) \{[\s\S]*?resetRoomSeatExperienceTimer/);
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
