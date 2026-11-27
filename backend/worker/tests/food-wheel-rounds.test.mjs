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
  assert.match(ui, /Timer\.periodic\(const Duration\(milliseconds: 200\)/);
  assert.match(ui, /_phaseSecondsLeft\(RoundState s\)/);
  assert.match(ui, /_clockDisplaySecond = math\.min/);
  assert.match(ui, /_serverClockSynced/);
  assert.match(ui, /void _queueBetSend\(_PendingWheelBet bet\)/);
  assert.doesNotMatch(ui, /Future\.delayed\(const Duration\(milliseconds: 450\)\)/);
  assert.match(ui, /int _resultStartAt\(RoundState s\)/);
  assert.match(ui, /final elapsedMs = \(_serverNowMs\(\) - _resultStartAt\(s\)\)/);
  assert.match(ui, /deadline \+ 5000 - now/);
  assert.match(ui, /_isResultPhase\(RoundState s\)/);
  assert.match(ui, /_bettingOpen\(RoundState s\)/);
  assert.match(ui, /_serverNowMs\(\) >= _bettingDeadline\(current\)/);
  assert.match(ui, /_serverNowMs\(\)/);
  assert.match(ui, /_serverClockOffsetMs = s\.serverTime!/);
  assert.match(ui, /_popupSecondsLeft\(RoundState s\)/);
  assert.match(ui, /duration: const Duration\(milliseconds: 5000\)/);
  assert.match(ui, /class _TopTopSpinCurve extends Curve/);
  assert.match(ui, /_spinController\.value = elapsedMs / spinDurationMs/);
  assert.match(ui, /void _startProvisionalSpin\(RoundState s\)/);
  assert.match(ui, /_isResultPhase\(current\) && _spinStartedRoundId != current\.roundId/);
  assert.match(ui, /final beginAngle = denominator > 0\.0001/);
  assert.match(ui, /await _spinController\.forward\(\)/);
  assert.match(ui, /3 \* math\.pi \* 2/);
  assert.match(ui, /Tween<double>\(begin: 0, end: endAngle\)/);
  assert.match(ui, /AnimatedBuilder\(\s*animation: _spinController/);
  assert.match(ui, /_highlightForSlot\(spinAngle, i\)/);
  assert.doesNotMatch(ui, /currentIndex\+\+|step\+\+ % kSlots\.length|_hit = target/);
  assert.doesNotMatch(ui, /await Future\.delayed\(const Duration\(seconds: 1\)\)/);
  assert.doesNotMatch(ui, /_panelTimer|_refreshAfterPopup/);
  assert.match(ui, /popupEndAt = s\.roundEndAt \?\? \(_resultStartAt\(s\) \+ 8000\)/);
  assert.match(ui, /heightFactor: 0\.45/);
  assert.doesNotMatch(ui, /AnimatedContainer\(\s*duration: const Duration\(milliseconds: 120\)/);
  assert.match(ui, /الفائز الأكبر لهذه الجولة/);
  assert.match(ui, /_popupTimeLeft/);
  assert.match(ui, /placeBet\(\s*bet\.roundId,\s*bet\.slot,\s*bet\.amount,\s*bet\.idempotencyKey/);
  assert.match(ui, /Future<void> _sendBet\(_PendingWheelBet bet(?:, \{Future<RoundState>\? request\})?\)/);
  assert.match(ui, /_queueBetSend\(bet\)/);
  assert.match(ui, /behavior: HitTestBehavior\.opaque,\s*onPointerDown: \(_\) => _onFoodPointerDown\(i\)/);
  assert.match(ui, /_fmt\(math\.max\(0, _bal - _pendingReserved\)\)/);
  assert.match(ui, /bet\.status != _PendingBetStatus\.accepted/);
  assert.match(ui, /\x27رهانك في هذه الجولة:/);
  assert.match(ui, /\x27الفائز في هذه الجولة:/);
  assert.match(ui, /الفائز الأكبر لهذه الجولة/);
  assert.match(ui, /for \(final i in \[2, 0, 1\]\)/);
  assert.doesNotMatch(ui, /_drainBetQueue|_betQueueRunning/);
  assert.match(ui, /final List<_PendingWheelBet> _pendingBets/);
  assert.match(ui, /final List<int> _roundLockedMine = List\.filled\(8, 0\)/);
  assert.match(ui, /_roundLockedMine\[i\] \+= amount/);
  assert.match(ui, /_lockedMineRoundId == s\.roundId \? _roundLockedMine\[i\] : 0/);
  assert.match(ui, /انتهت الجولة انتظر الجولة القادمة/);
  assert.match(ui, /Duration\(seconds: 2\)/);
  assert.match(ui, /ignoring: !_bettingOpen\(s\)/);
  assert.match(ui, /bool observedInState = false/);
  assert.match(api, /SELECT slot, SUM\(stake\) AS amount FROM food_wheel_bets/);
  assert.match(api, /const priorGlobalBet = await db\.prepare/);
  assert.ok(api.indexOf("const priorGlobalBet") < api.indexOf("if (globalRound.status !== \"betting\""));
  assert.match(api, /reason: "betting_window_closed"/);
  const topBar = ui.slice(ui.indexOf("Widget _topBar(RoundState s)"), ui.indexOf("Widget _wheel(RoundState s)"));
  assert.ok(topBar.indexOf("_openMore") < topBar.indexOf("_trophyBtn()"));
  assert.ok(topBar.indexOf("_trophyBtn()") < topBar.indexOf("_openLog"));
  assert.ok(topBar.indexOf("_openLog") < topBar.indexOf("_openSettings"));
  assert.ok(topBar.indexOf("_openSettings") < topBar.indexOf("_modeToggle()"));
  assert.doesNotMatch(ui, /food-wheel-state-/);
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
  assert.match(ui, /_spinController\.value = elapsedMs / spinDurationMs/);
  assert.match(ui, /await _spinController\.forward\(\)/);
  assert.match(ui, /return 0;/);
  assert.match(ui, /popupEndAt = s\.roundEndAt \?\? \(_resultStartAt\(s\) \+ 8000\)/);
  assert.match(ui, /_isResultPhase\(s\) \? 'النتيجة القادمة' : 'وقت الرهان'/);
  assert.match(ui, /_popupTimeLeft\.clamp\(1, 4\)/);
  assert.match(ui, /popupNext <= 1/);
  assert.match(ui, /if \(popupExpired\) _panel = false/);
  assert.match(ui, /phaseExpired \|\| popupExpired \|\| now - _lastRefreshAt >= 1000/);
});
