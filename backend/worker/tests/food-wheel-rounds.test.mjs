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
  assert.match(hub, /const BETTING_MS = 20_000/);
  assert.match(hub, /const ROUND_MS = 28_000/);
  assert.match(hub, /const chosenAt = round\.bettingEndsAt/);
  assert.match(hub, /Date\.parse\(round\.bettingEndsAt\) \+ 8_000/);
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
  assert.match(api, /result_chosen_at: resultChosenAt/);
  assert.match(api, /server_time: now/);
  assert.match(api, /Math.min\(20, Math.ceil\(\(bettingEndAt - now\) \/ 1000\)\)/);
  assert.match(api, /total_bets: pools/);
  assert.match(ui, /totalBetsByFood: j\['total_bets_by_food'\] is Map/);
  assert.match(api, /total_bets_by_food: totalBetsByFood/);
  assert.match(api, /const foodKeys = \[\"chicken\", \"tomato\", \"goat\", \"chili\", \"fish\", \"carrot\", \"shrimp\", \"corn\"\]/);
  assert.match(ui, /const kSlotKeys = <String>\[/);
  assert.match(ui, /totals\[key\] = math\.max\(totals\[key\] \?\? 0, value\)/);
  assert.match(ui, /_serverTotalsByRound/);
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

test("web client freezes round-keyed bets, renders server-only totals, and lands the 5-second spin without easing", () => {
  assert.match(ui, /roundEndAt/);
  assert.match(ui, /Timer\\.periodic\\(const Duration\\(milliseconds: 200\\)/);
  assert.equal((ui.match(/Timer\\.periodic\\(/g) || []).length, 1);
  assert.match(ui, /pollStartedAt - _lastRefreshAt < 1000/);
  assert.match(ui, /int getSpinDelay\\(double remaining\\)/);
  assert.match(ui, /if \\(remaining > 4\\) return 220/);
  assert.match(ui, /if \\(remaining > 3\\) return 150/);
  assert.match(ui, /if \\(remaining > 2\\) return 90/);
  assert.match(ui, /if \\(remaining > 1\\) return 55/);
  assert.match(ui, /return 55/);
  assert.match(ui, /double _spinAngleForElapsed\\(double elapsedMs\\)/);
  assert.match(ui, /getSpinDelay\\(5\\.0 - second\\)/);
  assert.match(ui, /double _landingArcToWinner/);
  assert.match(ui, /_spinLandingArc = _landingArcToWinner/);
  assert.match(ui, /final endAngle = _spinAngleAtProgress\\(1\\)/);
  assert.match(ui, /if \\(p <= 0\\.8\\)/);
  assert.doesNotMatch(ui, /_SpinAccelerationCurve|easeOut|ease-out|final eased/);
  assert.match(ui, /_spinTargetKnown = true/);
  assert.match(ui, /_spinFinalizedRoundId == s\\.roundId/);
  assert.match(ui, /static const int _spinDurationMs = 5000/);
  assert.match(ui, /static const double _spinBaseAngle = 3 \\* math\\.pi \\* 2/);
  assert.match(ui, /final activeSlot = \\(angle \\/ step\\)\\.round\\(\\) % kSlots\\.length/);
  assert.doesNotMatch(ui, /_spinAnimation|_msgTimer|_toastTimer/);

  assert.match(ui, /final Map<int, Map<String, int>> _myBetsByRound/);
  assert.match(ui, /final Map<int, Map<String, int>> _frozenBetsByRound/);
  assert.match(ui, /void _freezeMyBets\\(int roundId\\)/);
  assert.match(ui, /_displayBetsForRound\\(int roundId\\) => _frozenBetsByRound\\[roundId\\]/);
  assert.match(ui, /bets\\[kSlotKeys\\[i\\]\\] = \\(bets\\[kSlotKeys\\[i\\]\\] \\?\\? 0\\) \\+ amount/);
  assert.match(ui, /_myBetTotalForRound\\(s\\.roundId\\)/);
  assert.doesNotMatch(ui, /kSlotKeys\\[i\\]: _safeSlotValue\\(s\\.myBets/);
  assert.match(ui, /_lockedBetRounds\\.contains\\(current\\.roundId\\)/);
  assert.match(ui, /_lockedBetRounds\\.contains\\(roundId\\)/);
  assert.match(ui, /_rememberServerTotals\\(s\\)/);
  assert.match(ui, /final pools = _serverTotalsForRound\\(s\\.roundId\\)/);
  assert.doesNotMatch(ui, /pendingBySlot|_confirmedPools \\+ pending/);
  assert.match(ui, /_serverClockSynced/);
  assert.match(ui, /void _queueBetSend\\(_PendingWheelBet bet\\)/);
  assert.match(ui, /placeBet\\(\\s*bet\\.roundId,\\s*bet\\.slot,\\s*bet\\.amount,\\s*bet\\.idempotencyKey/);
  assert.match(ui, /_isResultPhase\\(current\\) && _spinStartedRoundId != current\\.roundId/);
  assert.match(api, /ORDER BY fb\\.created_at DESC, fb\\.id DESC LIMIT 12/);
  assert.doesNotMatch(ui, /Future\\.delayed\\(const Duration\\(seconds: 5\\)/);
  assert.match(ui, /heightFactor: 0\\.45/);
  assert.match(ui, /AnimatedBuilder\\(\\s*animation: _spinController/);
  assert.match(ui, /_highlightForSlot\\(spinAngle, i\\)/);
  assert.match(ui, /popupEndAt = s\\.roundEndAt \\?\\? \\(_resultStartAt\\(s\\) \\+ 8000\\)/);
});

test("Food Wheel spin paints only the lower half red with a thick red border", () => {
  const wheel = ui.slice(ui.indexOf("Widget _slot("), ui.indexOf("Widget _special("));
  assert.match(wheel, /isSpinPosition = highlight >= 0\.5/);
  assert.match(wheel, /color: isSpinPosition\s*\? const Color\(0xFFFF0000\)\s*:\s*const Color\(0xFFFFD84D\)/);
  assert.match(wheel, /width: isSpinPosition \? 8 : 4/);
  assert.match(wheel, /color: isSpinPosition\s*\? const Color\(0xFFFF0000\)\s*:\s*const Color\(0xFF8A4B2A\)/);
  assert.match(wheel, /Alignment\(0, -0\.58\)/);
  assert.match(wheel, /Alignment\(0, 0\.20\)/);
  assert.match(wheel, /Alignment\(0, 0\.67\)/);
  assert.match(wheel, /color: isSpinPosition\s*\? Colors\.white\s*:\s*dark/);
  assert.doesNotMatch(wheel, /BoxShadow|withOpacity|0xFF00FF00|0xFF00C853/);
  assert.match(wheel, /Text\('x\$\{slot\.mult\}'/);
  assert.match(wheel, /Text\('\$\{s\.pools\[i\]\} 🪙'/);
  assert.match(wheel, /Text\('\$myBet'/);
});

test("Food Wheel starts the full spin at chicken and immediately refreshes after popup expiry", () => {


  assert.match(ui, /return 0;/);
  assert.match(ui, /popupEndAt = s\.roundEndAt \?\? \(_resultStartAt\(s\) \+ 8000\)/);
  assert.match(ui, /_isResultPhase\(s\) \? 'النتيجة القادمة' : 'وقت الرهان'/);
  assert.match(ui, /_popupTimeLeft\.clamp\(1, 4\)/);
  assert.match(ui, /popupNext <= 1/);
  assert.match(ui, /if \(popupExpired\) \{/);
  assert.match(ui, /_serverTotalsByRound\.remove\(current\.roundId\)/);
  assert.match(ui, /now - _lastRefreshAt >= 1000/);
});
