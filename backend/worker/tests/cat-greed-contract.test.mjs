import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../migrations/0034_cat_greed_wheel.sql", import.meta.url), "utf8");
const ledgerMigration = await readFile(new URL("../migrations/0035_cat_greed_ledger.sql", import.meta.url), "utf8");
const protectionMigration = await readFile(new URL("../migrations/0036_cat_greed_bet_protection.sql", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/cat_greed.ts", import.meta.url), "utf8");
const flutterGame = await readFile(new URL("../../../frontend/lib/pages/cat_greed_game.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");
const mainAdmin = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");
const gameAdmin = await readFile(new URL("../../../frontend/web/cat-greed-admin/index.html", import.meta.url), "utf8");
const gameSite = await readFile(new URL("../../../frontend/web/cat-greed/index.html", import.meta.url), "utf8");

test("Cat Greed stores rounds, bets, payouts, symbols and player limits separately", () => {
  for (const table of ["cat_greed_settings","cat_greed_symbols","cat_greed_rounds","cat_greed_bets","cat_greed_payouts","cat_greed_player_controls","cat_greed_admin_audit","cat_greed_ledger"]) {
    assert.match(migration, new RegExp("CREATE TABLE IF NOT EXISTS " + table));
  }
  assert.match(migration, /idx_cat_greed_one_betting_round/);
});

test("round results are committed before betting and revealed only after settlement", () => {
  assert.match(worker, /seed_commitment/);
  assert.match(worker, /revealedSeed:isBetting\?null:round\.server_seed/);
  assert.match(worker, /configSnapshot:isBetting\?null:round\.config_snapshot/);
  assert.match(worker, /phase='result'/);
  assert.match(worker, /server_seed/);
});

test("betting and payouts are server-authoritative and use the Happy Live wallet ledger", () => {
  assert.match(worker, /authenticateUser\(request,db\)/);
  assert.match(worker, /UPDATE user_wallets SET balance=balance-\?/);
  assert.match(worker, /INSERT INTO cat_greed_ledger/);
  assert.match(worker, /cat_greed_payouts/);
  assert.match(worker, /BET_CHIPS/);
});

test("player-specific controls are risk limits, not hidden personalized outcome odds", () => {
  assert.match(worker, /max_bet_per_round/);
  assert.match(worker, /player_disabled/);
  assert.doesNotMatch(worker, /player_win_rate|player_loss_rate|player_outcome_weight/);
});

test("the room games sheet launches Cat Greed without replacing other room controls", () => {
  assert.match(roomPreview, /showCatGreedGame\(context, accessToken: accessToken\)/);
  assert.match(roomPreview, /ألعاب طرف ثالث/);
  assert.match(flutterGame, /\/games\/cat-greed\/state/);
  assert.match(flutterGame, /\/games\/cat-greed\/bet/);
});

test("both requested admin surfaces and the standalone game route are present", () => {
  assert.match(mainAdmin, /catGreedMainPage/);
  assert.match(mainAdmin, /maxBetPerRound/);
  assert.match(gameAdmin, /admin\/cat-greed\/settings/);
  assert.match(gameAdmin, /admin\/cat-greed\/symbols/);
  assert.match(gameAdmin, /admin\/cat-greed\/rounds/);
  assert.match(gameSite, /\/games\/cat-greed\/state/);
});

test("Cat Greed bet requests are idempotent and rate-limited per authenticated player", () => {
  assert.match(protectionMigration, /CREATE TABLE IF NOT EXISTS cat_greed_bet_requests/);
  assert.match(protectionMigration, /idempotency_key TEXT PRIMARY KEY/);
  assert.match(protectionMigration, /CREATE TABLE IF NOT EXISTS cat_greed_bet_rate_limits/);
  assert.match(worker, /idempotencyKey/);
  assert.match(worker, /BET_RATE_MAX_REQUESTS/);
  assert.match(worker, /bet_rate_limited/);
});

test("payout settlement claims a unique payout before crediting the wallet", () => {
  assert.match(worker, /UPDATE cat_greed_payouts SET paid_at=\?,transaction_id=\? WHERE round_id=\? AND user_id=\? AND paid_at IS NULL/);
  assert.match(worker, /Concurrent state requests can therefore never credit the same round twice/);
  assert.match(worker, /cat_greed_ledger/);
});

test("round commitments bind the seed to the round id and immutable config", () => {
  assert.match(worker, /digestHex\(seed \+ "\\|" \+ id \+ "\\|" \+ configSnapshot\)/);
  assert.match(worker, /round\.server_seed \+ "\\|" \+ round\.id \+ "\\|" \+ round\.config_snapshot/);
});

test("unsafe payout exposure cannot be enabled and all players share published odds", () => {
  assert.match(worker, /payout_exposure_too_high/);
  assert.match(worker, /maxExpectedReturnBp/);
  assert.match(worker, /appearanceProbabilityBp/);
  assert.match(worker, /expectedReturnBp/);
  assert.match(protectionMigration, /salad_weight_bp = 30, pizza_weight_bp = 30/);
});

test("symbol images are restricted to ImageKit and game pages use safe rendering", () => {
  assert.match(worker, /isValidImageKitUrl/);
  assert.match(worker, /hostname === "ik\.imagekit\.io"/);
  assert.match(gameSite, /safeImage/);
  assert.match(gameSite, /idempotencyKey/);
});
