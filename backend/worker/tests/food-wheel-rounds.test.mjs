import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const hub = await readFile(new URL("src/food_wheel_hub.ts", root), "utf8");
const api = await readFile(new URL("src/games_api.ts", root), "utf8");
const worker = await readFile(new URL("src/index.ts", root), "utf8");
const config = await readFile(new URL("wrangler.toml", root), "utf8");
const migration = await readFile(new URL("migrations/0062_global_food_wheel_rounds.sql", root), "utf8");
const rareMigration = await readFile(new URL("migrations/0063_food_wheel_rare_groups.sql", root), "utf8");
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
  assert.match(hub, /const ROUND_MS = 30_000/);
  assert.match(hub, /const chosenAt = round\.bettingEndsAt/);
  assert.match(hub, /Date\.parse\(round\.bettingEndsAt\) \+ 10_000/);
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
  assert.match(ui, /totalBetsByFood: _foodTotalsFromJson\(j\)/);
  assert.match(ui, /const kSlotKeys = <String>\[/);
  assert.match(ui, /totals\[key\] = math\.max\(totals\[key\] \?\? 0, value\)/);
  assert.match(api, /total_bets_by_food: totalBetsByFood/);
  assert.match(api, /SELECT slot, SUM\(stake\) AS amount FROM food_wheel_bets WHERE round_id = \? AND status IN \('accepted', 'settled'\) GROUP BY slot/);
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
  assert.ok(ui.includes("roundEndAt"));
  assert.ok(ui.includes("Timer.periodic(const Duration(milliseconds: 200)"));
  assert.equal((ui.match(/Timer\.periodic\(/g) || []).length, 1);
  assert.ok(ui.includes("pollStartedAt - _lastRefreshAt < 1000"));

  assert.ok(ui.includes("int getSpinDelay(double remaining)"));
  assert.ok(ui.includes("if (remaining > 4) return 650"));
  assert.ok(ui.includes("if (remaining > 3) return 400"));
  assert.ok(ui.includes("if (remaining > 2) return 180"));
  assert.ok(ui.includes("return 80"));
  assert.ok(ui.includes("return 80"));
  assert.ok(ui.includes("double _spinAngleForElapsed(double elapsedMs)"));
  assert.ok(ui.includes("integral * 5 * _spinStep"));
  assert.ok(ui.includes("double _landingArcToWinner"));
  assert.ok(ui.includes("_spinLandingArc = _landingArcToWinner"));
  assert.ok(ui.includes("final endAngle = _spinAngleAtProgress(1)"));
  assert.ok(ui.includes("if (p <= 0.8)"));
  const spinSection = ui.slice(ui.indexOf('int getSpinDelay'), ui.indexOf('String _newBetIdempotencyKey'));
  assert.doesNotMatch(spinSection, /_SpinAccelerationCurve|easeOut|ease-out|final eased/);
  assert.ok(ui.includes("_spinTargetKnown = true"));
  assert.ok(ui.includes("_spinFinalizedRoundId == s.roundId"));
  assert.ok(ui.includes("static const int _spinDurationMs = 5000"));
  assert.ok(ui.includes("static const double _spinBaseAngle = 3 * math.pi * 2"));
  assert.ok(ui.includes("final activeSlot = (angle / step).floor() % 10"));
  assert.doesNotMatch(ui, /_spinAnimation|_msgTimer|_toastTimer/);

  assert.ok(ui.includes("final Map<int, Map<String, int>> _myBetsByRound"));
  assert.ok(ui.includes("final Map<int, Map<String, int>> _frozenBetsByRound"));
  assert.ok(ui.includes("void _freezeMyBets(int roundId)"));
  assert.ok(ui.includes("Map<String, int>.unmodifiable(Map<String, int>.from(_myBetsForRound(roundId)))"));
  assert.match(ui, /_displayBetsForRound\(int roundId\) =>\s*_frozenBetsByRound\[roundId\]/);
  assert.ok(ui.includes("final mine = _myBetTotalForRound(s.roundId)"));
  assert.ok(ui.includes("_popupRoundState ?? s"));
  assert.ok(ui.includes("if (s.phase == RoundPhase.result) _finalServerTotalsRounds.add(s.roundId)"));
  assert.ok(ui.includes("final hasNamedTotals = s.totalBetsByFood.isNotEmpty"));
  assert.ok(ui.includes("final value = hasNamedTotals"));
  assert.ok(ui.includes("Map<String, int>.unmodifiable(revisedFrozen)"));
  assert.ok(ui.includes("if (_isResultPhase(current)) _freezeMyBets(current.roundId)"));
  assert.ok(ui.includes("bets[kSlotKeys[i]] = (bets[kSlotKeys[i]] ?? 0) + amount"));
  assert.ok(ui.includes("_myBetTotalForRound(s.roundId)"));
  assert.ok(ui.includes("_prevBets[kSlotKeys[i]] ?? 0"));
  assert.doesNotMatch(ui, /_confirmedRoundId|_confirmedMine|_reconcileOptimisticBets|observedInState/);
  assert.ok(ui.includes("_finalServerTotalsRounds.contains(s.roundId)"));
  assert.doesNotMatch(ui, /kSlotKeys\[i\]: _safeSlotValue\(s\.myBets/);
  assert.ok(ui.includes("_lockedBetRounds.contains(current.roundId)"));
  assert.ok(ui.includes("_lockedBetRounds.contains(roundId)"));
  assert.ok(ui.includes("_rememberServerTotals(s)"));
  assert.ok(ui.includes("final ValueNotifier<int> _timeLeftNotifier"));
  assert.ok(ui.includes("final ValueNotifier<RoundState?> _wheelStateNotifier"));
  assert.ok(ui.includes("if (wheelTotalsChanged) _wheelStateNotifier.value = _withOptimisticBets(s)"));
  assert.ok(ui.includes("ValueListenableBuilder<int>("));
  assert.doesNotMatch(ui, /myBets:|j\['my_bets'\]/);
  assert.ok(ui.includes("final pools = _serverTotalsForRound(s.roundId)"));
  assert.doesNotMatch(ui, /pendingBySlot|_confirmedPools \+ pending/);
  assert.ok(ui.includes("_serverClockSynced"));
  assert.ok(ui.includes("void _queueBetSend(_PendingWheelBet bet)"));
  assert.ok(ui.includes("unawaited(_sendBet(bet))"));
  assert.doesNotMatch(ui, /_betSendChain/);
  assert.ok(ui.includes("bet.roundId,\n        bet.slot,\n        bet.amount,\n        bet.idempotencyKey"));
  assert.ok(ui.includes("_isResultPhase(current) && _spinStartedRoundId != current.roundId"));
  assert.match(api, /ORDER BY fb\.created_at DESC, fb\.id DESC LIMIT 12/);
  assert.doesNotMatch(ui, /Future\.delayed\(const Duration\(seconds: 5\)/);
  assert.ok(ui.includes("heightFactor: 0.45"));
  assert.match(ui, /AnimatedBuilder\(\s*animation: _spinController/);
  assert.ok(ui.includes("_highlightForSlot(spinAngle, i)"));
  assert.ok(ui.includes("popupEndAt = s.roundEndAt ?? (_resultStartAt(s) + 10000)"));
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
  assert.match(ui, /popupEndAt = s\.roundEndAt \?\? \(_resultStartAt\(s\) \+ 10000\)/);
  assert.match(ui, /_isResultPhase\(s\) \? 'النتيجة القادمة' : 'وقت الرهان'/);
  assert.match(ui, /seconds\.clamp\(1, 4\)/);
  assert.match(ui, /_roundCleanupAtMs\[s\.roundId\] = DateTime\.now\(\)\.millisecondsSinceEpoch \+ 5000/);
  assert.match(ui, /final popupExpired = popupId != null && cleanupAt != null && now >= cleanupAt/);
  assert.match(ui, /_serverTotalsByRound\.remove\(popupId\)/);
  assert.match(ui, /_resultOverlay\(_popupRoundState \?\? s\)/);
  assert.doesNotMatch(ui, /_myBetsByRound\.remove\(previous\.roundId\)/);
  assert.match(ui, /now - _lastRefreshAt >= 1000/);
});


test("rare Pizza and Salad outcomes are public weighted outcomes and pay complete food groups", () => {
  assert.match(hub, /RARE_PIZZA_WEIGHT = 3/);
  assert.match(hub, /RARE_SALAD_WEIGHT = 3/);
  assert.match(hub, /const roll = crypto\\.getRandomValues/);
  assert.match(hub, /resultSpecial: "pizza" \\| "salad" \\| null/);
  assert.match(hub, /slot IN \\(1,2,4,6\\) THEN stake \\* 5/);
  assert.match(hub, /result_special.*salad/);
  assert.match(api, /special: round\\.resultSpecial/);
  assert.match(rareMigration, /ADD COLUMN result_special/);
});

test("Food Wheel accepts arbitrary positive integer stakes and rejects a seventh distinct food", () => {
  assert.match(api, /Number\\.isSafeInteger\\(amount\\) \\|\\| amount <= 0/);
  assert.match(api, /COUNT\\(DISTINCT slot\\)/);
  assert.match(api, /max_foods_per_round/);
  assert.ok(ui.includes("for (var i = 0; i < 10; i++)"));
  assert.ok(!ui.includes("Text('Hot'"));
});
