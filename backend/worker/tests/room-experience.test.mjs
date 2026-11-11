import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";

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



function extractTypedAsyncFunction(source, name) {
  const match = source.match(new RegExp(`async function ${name}\\([\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must exist in Worker source`);
  const javascript = match[0]
    .replaceAll("db: D1Database", "db")
    .replaceAll("roomId: string", "roomId")
    .replaceAll("userId: string", "userId")
    .replaceAll("now: string", "now")
    .replace("): Promise<void> {", ") {")
    .replaceAll(".first<{ last_awarded_at: string }>()", ".first()");
  return new Function(
    "ROOM_EXP_DAILY_USER_CAP",
    "crypto",
    `${javascript}; return ${name};`
  )(3_000_000, globalThis.crypto);
}

class SqliteD1Statement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql;
    this.params = [];
  }
  bind(...params) {
    this.params = params;
    return this;
  }
  async run() {
    const result = this.database.sqlite.prepare(this.sql).run(...this.params);
    return { meta: { changes: Number(result.changes) } };
  }
  async first() {
    return this.database.sqlite.prepare(this.sql).get(...this.params) ?? null;
  }
}

class SqliteD1 {
  constructor() {
    this.sqlite = new DatabaseSync(":memory:");
    this.sqlite.exec(`
      PRAGMA foreign_keys = ON;
      CREATE TABLE users (id TEXT PRIMARY KEY);
      CREATE TABLE rooms (id TEXT PRIMARY KEY);
      CREATE TABLE room_experience (
        room_id TEXT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
        total_exp INTEGER NOT NULL DEFAULT 0 CHECK (total_exp >= 0),
        updated_at TEXT NOT NULL
      );
      CREATE TABLE room_exp_activity (
        room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        last_awarded_at TEXT NOT NULL,
        PRIMARY KEY (room_id, user_id)
      );
      CREATE TABLE room_exp_daily (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        day_key TEXT NOT NULL,
        points INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0 AND points <= 3000000),
        PRIMARY KEY (user_id, day_key)
      );
      CREATE TABLE room_exp_awards (
        id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        day_key TEXT NOT NULL,
        points INTEGER NOT NULL CHECK (points > 0 AND points <= 600),
        created_at TEXT NOT NULL
      );
    `);
    this.failNextBatch = false;
  }
  prepare(sql) {
    return new SqliteD1Statement(this, sql);
  }
  async batch(statements) {
    if (this.failNextBatch) {
      this.failNextBatch = false;
      throw new Error("simulated D1 batch failure");
    }
    this.sqlite.exec("BEGIN");
    try {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      this.sqlite.exec("COMMIT");
      return results;
    } catch (error) {
      this.sqlite.exec("ROLLBACK");
      throw error;
    }
  }
  exec(sql) {
    this.sqlite.exec(sql);
  }
  get(sql, ...params) {
    return this.sqlite.prepare(sql).get(...params) ?? null;
  }
  close() {
    this.sqlite.close();
  }
}

const experienceImplementations = [
  {
    name: "Worker REST handler",
    award: extractTypedAsyncFunction(worker, "awardRoomSeatExperience"),
    reset: extractTypedAsyncFunction(worker, "resetRoomSeatExperienceTimer"),
  },
  {
    name: "RoomSeatsHub WebSocket handler",
    award: extractTypedAsyncFunction(seatHub, "awardRoomSeatExperience"),
    reset: extractTypedAsyncFunction(seatHub, "resetRoomSeatExperienceTimer"),
  },
];

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
    `${helperSource.replace("int roomLevelRequiredExpForLevel", "function roomLevelRequiredExpForLevel").replace("(int targetLevel)", "(targetLevel)").replaceAll("final ", "const ").replace("((safeLevel - 1) ~/ 5)", "Math.floor((safeLevel - 1) / 5)")}; return roomLevelRequiredExpForLevel;`
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
  assert.match(worker, /restore the old timestamp so the user's earned mic time is not lost/);
  assert.match(seatHub, /restore the old timestamp so the user's earned mic time is not lost/);
});

test("clearing microphones, moderation removal, and expired seats reset continuous XP time", () => {
  const clearBlock = seatHub.match(/if \(url\.pathname === "\/clear"[\s\S]*?return Response\.json\(\{ ok: true, \.\.\.this\.publicSnapshot\(\) \}\);/)?.[0];
  assert.ok(clearBlock, "clear endpoint must exist");
  assert.match(clearBlock, /removedMembers = Object\.values\(this\.snapshot\.seats\)/);
  assert.match(clearBlock, /resetRoomSeatExperienceTimer\(this\.env\.DB, this\.roomId, member\.userId/);

  const removeBlock = seatHub.match(/if \(url\.pathname === "\/remove-user"[\s\S]*?return Response\.json\(\{ ok: true, \.\.\.this\.publicSnapshot\(\) \}\);/)?.[0];
  assert.ok(removeBlock, "remove-user endpoint must exist");
  assert.match(removeBlock, /resetRoomSeatExperienceTimer\(this\.env\.DB, this\.roomId, targetUserId/);

  const expireBlock = seatHub.match(/private async expireSeats\(shouldBroadcast: boolean\)[\s\S]*?private async scheduleExpiry/)?.[0];
  assert.ok(expireBlock, "seat expiry handler must exist");
  assert.match(expireBlock, /resetRoomSeatExperienceTimer\(this\.env\.DB, this\.roomId, member\.userId/);
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


test("D1-backed award logic grants 600 at five minutes and persists room experience", async () => {
  for (const implementation of experienceImplementations) {
    const db = new SqliteD1();
    try {
      db.exec("INSERT INTO users (id) VALUES ('user-1')");
      db.exec("INSERT INTO rooms (id) VALUES ('room-1')");
      const start = Date.parse("2026-11-12T10:00:00.000Z");
      const at = (offset) => new Date(start + offset).toISOString();

      await implementation.reset(db, "room-1", "user-1", at(0));
      await implementation.award(db, "room-1", "user-1", at(299_999));
      assert.equal(db.get("SELECT COUNT(*) AS count FROM room_exp_awards").count, 0, implementation.name);

      await implementation.award(db, "room-1", "user-1", at(300_000));
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-1'").total_exp, 600, implementation.name);
      assert.equal(db.get("SELECT points FROM room_exp_daily WHERE user_id = 'user-1'").points, 600, implementation.name);

      // Leaving/rejoining starts a fresh five-minute interval without erasing saved room XP.
      await implementation.reset(db, "room-1", "user-1", at(350_000));
      await implementation.award(db, "room-1", "user-1", at(649_999));
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-1'").total_exp, 600, implementation.name);
      await implementation.award(db, "room-1", "user-1", at(650_000));
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-1'").total_exp, 1_200, implementation.name);
    } finally {
      db.close();
    }
  }
});

test("D1-backed award logic resets continuous time, caps contributions across rooms, and prevents duplicate heartbeats", async () => {
  for (const implementation of experienceImplementations) {
    const db = new SqliteD1();
    try {
      db.exec("INSERT INTO users (id) VALUES ('user-1')");
      db.exec("INSERT INTO rooms (id) VALUES ('room-1'), ('room-2')");
      const start = Date.parse("2026-11-12T11:00:00.000Z");
      const at = (offset) => new Date(start + offset).toISOString();

      await implementation.reset(db, "room-1", "user-1", at(0));
      await implementation.award(db, "room-1", "user-1", at(299_999));
      await implementation.reset(db, "room-1", "user-1", at(299_999));
      await implementation.award(db, "room-1", "user-1", at(300_000));
      assert.equal(db.get("SELECT COUNT(*) AS count FROM room_exp_awards").count, 0, implementation.name);
      await implementation.award(db, "room-1", "user-1", at(599_999));
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-1'").total_exp, 600, implementation.name);

      // The user's daily limit is shared across every room, and the final award is partial.
      db.exec("UPDATE room_exp_daily SET points = 2999700 WHERE user_id = 'user-1' AND day_key = '2026-11-12'");
      await implementation.reset(db, "room-2", "user-1", at(700_000));
      await implementation.award(db, "room-2", "user-1", at(1_000_000));
      assert.equal(db.get("SELECT points FROM room_exp_daily WHERE user_id = 'user-1'").points, 3_000_000, implementation.name);
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-2'").total_exp, 300, implementation.name);

      await implementation.reset(db, "room-1", "user-1", at(1_100_000));
      await implementation.award(db, "room-1", "user-1", at(1_400_000));
      assert.equal(db.get("SELECT points FROM room_exp_daily WHERE user_id = 'user-1'").points, 3_000_000, implementation.name);
      assert.equal(db.get("SELECT COUNT(*) AS count FROM room_exp_awards").count, 2, implementation.name);

      // Two simultaneous heartbeat sources may race, but only one can claim the interval.
      db.exec("INSERT INTO users (id) VALUES ('user-2')");
      db.exec("INSERT INTO rooms (id) VALUES ('room-3')");
      await implementation.reset(db, "room-3", "user-2", at(0));
      await Promise.all([
        implementation.award(db, "room-3", "user-2", at(300_000)),
        implementation.award(db, "room-3", "user-2", at(300_000)),
      ]);
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-3'").total_exp, 600, implementation.name);
    } finally {
      db.close();
    }
  }
});

test("D1 award failure restores the previous timer so the five-minute award can retry", async () => {
  for (const implementation of experienceImplementations) {
    const db = new SqliteD1();
    try {
      db.exec("INSERT INTO users (id) VALUES ('user-1')");
      db.exec("INSERT INTO rooms (id) VALUES ('room-1')");
      const start = Date.parse("2026-11-12T12:00:00.000Z");
      const at = (offset) => new Date(start + offset).toISOString();
      await implementation.reset(db, "room-1", "user-1", at(0));
      db.failNextBatch = true;

      await assert.rejects(
        implementation.award(db, "room-1", "user-1", at(300_000)),
        /simulated D1 batch failure/
      );
      assert.equal(
        db.get("SELECT last_awarded_at FROM room_exp_activity WHERE room_id = 'room-1' AND user_id = 'user-1'").last_awarded_at,
        at(0),
        implementation.name
      );

      await implementation.award(db, "room-1", "user-1", at(300_000));
      assert.equal(db.get("SELECT total_exp FROM room_experience WHERE room_id = 'room-1'").total_exp, 600, implementation.name);
    } finally {
      db.close();
    }
  }
});
