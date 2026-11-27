import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const hub = await readFile(new URL("src/food_wheel_hub.ts", root), "utf8");
const api = await readFile(new URL("src/games_api.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");
const config = await readFile(new URL("wrangler.toml", root), "utf8");
const migration = await readFile(new URL("migrations/0062_global_food_wheel_rounds.sql", root), "utf8");
const ui = await readFile(new URL("../../../frontend/lib/games/food_wheel/food_wheel_game.dart", import.meta.url), "utf8");

test("Food Wheel uses one sequential global round with a server-enforced single active round", () => {
  assert.match(migration, /round_no INTEGER PRIMARY KEY AUTOINCREMENT/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS idx_food_wheel_one_active_round/);
  assert.match(migration, /WHERE status IN \('betting', 'result'\)/);
  assert.match(hub, /class FoodWheelRoundsHub extends DurableObject/);
  assert.match(hub, /private async createRound\(startMs: number\)/);
  assert.match(hub, /round_no AS roundNo/);
  assert.doesNotMatch(api, /food-wheel-state-/);
});

test("Durable Object alarms advance betting, result, settlement, and the next round without player traffic", () => {
  assert.match(hub, /const BETTING_MS = 15_000/);
  assert.match(hub, /const ROUND_MS = 20_000/);
  assert.match(hub, /async alarm\(\): Promise<void>/);
  assert.match(hub, /this\.ctx\.storage\.setAlarm/);
  assert.match(hub, /private async chooseAndPublishResult/);
  assert.match(hub, /private async settleRound/);
  assert.match(worker, /async scheduled\(/);
  assert.match(config, /crons = \["\* \* \* \* \*"\]/);
});

test("all players join the shared round and state returns live totals and real winner identities", () => {
  assert.match(api, /FOOD_WHEEL_ROUNDS\.idFromName\("food-wheel-global"\)/);
  assert.match(api, /round_end_at: endAt/);
  assert.match(api, /total_bets: pools/);
  assert.match(api, /my_bets: myBets/);
  assert.match(api, /top_winners: topWinners/);
  assert.match(api, /SUM\(fb\.payout\) AS amount/);
  assert.match(api, /p\.avatar_key AS avatar/);
});

test("wallet debit remains at bet acceptance and wallet payout is deferred to server settlement", () => {
  assert.match(api, /UPDATE user_wallets SET balance = balance - \?/);
  assert.match(api, /'bet_debit'/);
  assert.match(hub, /UPDATE user_wallets SET balance = balance \+ \?/);
  assert.match(hub, /'payout_credit'/);
  assert.match(hub, /food-wheel-payout:/);
  assert.match(hub, /status = 'result'/);
});

test("web client uses server round end time and does not create rounds from taps", () => {
  assert.match(ui, /roundEndAt/);
  assert.match(ui, /Timer\.periodic\(const Duration\(seconds: 1\)/);
  assert.match(ui, /roundEndAt! - DateTime\.now\(\)\.millisecondsSinceEpoch/);
  assert.match(ui, /placeBet\(\s*bet\.roundId,\s*bet\.slot,\s*bet\.amount,\s*bet\.idempotencyKey/);
  assert.match(ui, /Future<void> _drainBetQueue\(\)/);
  assert.match(ui, /final List<_PendingWheelBet> _pendingBets/);
  assert.match(ui, /bool observedInState = false/);
  assert.match(api, /SELECT slot, SUM\(stake\) AS amount FROM food_wheel_bets/);
  assert.match(api, /const priorGlobalBet = await db\.prepare/);
  assert.ok(api.indexOf("const priorGlobalBet") < api.indexOf("if (globalRound.status !== \"betting\""));
  assert.match(api, /reason: "betting_window_closed"/);
  assert.doesNotMatch(ui, /food-wheel-state-/);
});
