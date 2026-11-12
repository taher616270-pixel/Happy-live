import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../migrations/0034_cat_greed_wheel.sql", import.meta.url), "utf8");
const ledgerMigration = await readFile(new URL("../migrations/0035_cat_greed_ledger.sql", import.meta.url), "utf8");
const protectionMigration = await readFile(new URL("../migrations/0036_cat_greed_bet_protection.sql", import.meta.url), "utf8");
const roundGuardMigration = await readFile(new URL("../migrations/0037_cat_greed_round_guard.sql", import.meta.url), "utf8");
const previewRoundGuardMigration = await readFile(new URL("../migrations-cat-greed-preview/0037_cat_greed_round_guard.sql", import.meta.url), "utf8");
const previewWheelMigration = await readFile(new URL("../migrations-cat-greed-preview/0034_cat_greed_wheel.sql", import.meta.url), "utf8");
const previewLedgerMigration = await readFile(new URL("../migrations-cat-greed-preview/0035_cat_greed_ledger.sql", import.meta.url), "utf8");
const previewProtectionMigration = await readFile(new URL("../migrations-cat-greed-preview/0036_cat_greed_bet_protection.sql", import.meta.url), "utf8");
const previewMigrationConfig = await readFile(new URL("../wrangler.preview-migrations.toml", import.meta.url), "utf8");
const wranglerConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
const packageJson = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
const deployWorkflow = await readFile(new URL("../../../.github/workflows/deploy-happy-live-worker.yml", import.meta.url), "utf8");
const previewDeployWorkflow = await readFile(new URL("../../../.github/workflows/deploy-cat-greed-preview.yml", import.meta.url), "utf8");
const worker = await readFile(new URL("../src/cat_greed.ts", import.meta.url), "utf8");
const flutterGame = await readFile(new URL("../../../frontend/lib/pages/cat_greed_game.dart", import.meta.url), "utf8");
const roomPreview = await readFile(new URL("../../../frontend/lib/pages/voice_room_design_preview.dart", import.meta.url), "utf8");
const mainAdmin = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");
const gameAdmin = await readFile(new URL("../../../frontend/web/cat-greed-admin/index.html", import.meta.url), "utf8");
const gameAdminScript = await readFile(new URL("../../../frontend/web/cat-greed-admin/app.js", import.meta.url), "utf8");
const gameSite = await readFile(new URL("../../../frontend/web/cat-greed/index.html", import.meta.url), "utf8");
const gameScript = await readFile(new URL("../../../frontend/web/cat-greed/app.js", import.meta.url), "utf8");
const pageHeaders = await readFile(new URL("../../../frontend/web/_headers", import.meta.url), "utf8");

test("Cat Greed stores rounds, bets, payouts, symbols and player limits separately", () => {
  for (const table of ["cat_greed_settings","cat_greed_symbols","cat_greed_rounds","cat_greed_bets","cat_greed_payouts","cat_greed_player_controls","cat_greed_admin_audit"]) {
    assert.match(migration, new RegExp("CREATE TABLE IF NOT EXISTS " + table));
  }
  assert.match(ledgerMigration, /CREATE TABLE IF NOT EXISTS cat_greed_ledger/);
  assert.match(migration, /idx_cat_greed_one_betting_round/);
});

test("round results are committed before betting and revealed only after settlement", () => {
  assert.match(worker, /seed_commitment/);
  assert.match(worker, /revealedSeed:isBetting\?null:round\.server_seed/);
  assert.match(worker, /configSnapshot:isBetting\?null:round\.config_snapshot/);
  assert.match(worker, /rulesVersion: 1/);
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
  assert.match(mainAdmin, /catGreedToggle/);
  assert.match(mainAdmin, /admin\.role==="owner"/);
  assert.match(mainAdmin, /admin\/cat-greed\/settings/);
  assert.match(mainAdmin, /maxBetPerRound/);
  assert.match(gameAdminScript, /admin\/cat-greed\/settings/);
  assert.match(gameAdminScript, /admin\/cat-greed\/symbols/);
  assert.match(gameAdminScript, /admin\/cat-greed\/rounds/);
  assert.match(gameScript, /\/games\/cat-greed\/state/);
});

test("Cat Greed bet requests are idempotent and rate-limited per authenticated player", () => {
  assert.match(protectionMigration, /CREATE TABLE IF NOT EXISTS cat_greed_bet_requests/);
  assert.match(protectionMigration, /idempotency_key TEXT PRIMARY KEY/);
  assert.match(protectionMigration, /CREATE TABLE IF NOT EXISTS cat_greed_bet_rate_limits/);
  assert.match(protectionMigration, /CREATE TABLE IF NOT EXISTS cat_greed_state_rate_limits/);
  assert.match(worker, /STATE_RATE_MAX_REQUESTS = 90/);
  assert.match(worker, /BET_RATE_MAX_REQUESTS = 10/);
  assert.match(protectionMigration, /cat_greed_round_result_consistency_update/);
  assert.match(protectionMigration, /idx_cat_greed_payout_transaction/);
  assert.match(worker, /idempotencyKey/);
  assert.match(worker, /BET_RATE_MAX_REQUESTS/);
  assert.match(worker, /bet_rate_limited/);
  assert.match(worker, /excluded\.window_start-cat_greed_bet_rate_limits\.window_start>=\?/);
  assert.match(worker, /excluded\.window_start-cat_greed_state_rate_limits\.window_start>=\?/);
  assert.doesNotMatch(worker, /Math\.floor\(Date\.now\(\)\/BET_RATE_WINDOW_SECONDS\)/);
});

test("payout settlement claims a unique payout before crediting the wallet", () => {
  assert.match(worker, /UPDATE cat_greed_payouts SET paid_at=\?,transaction_id=\? WHERE round_id=\? AND user_id=\? AND paid_at IS NULL/);
  assert.match(worker, /Concurrent state requests can therefore never credit the same round twice/);
  assert.match(worker, /cat_greed_ledger/);
});

test("round commitments bind the seed to the round id and immutable config", () => {
  assert.ok(worker.includes('digestHex("commit|" + seed + "|" + id + "|" + configSnapshot)'));
  assert.ok(worker.includes('digestHex("outcome|" + round.server_seed + "|" + round.id + "|" + round.config_snapshot)'));
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
  assert.match(gameScript, /safeImage/);
  assert.match(gameScript, /idempotencyKey/);
  assert.match(gameScript, /فشل التحقق من نتيجة الجولة/);
  assert.match(gameAdminScript, /verifyRoundRow/);
  assert.match(gameAdminScript, /function safeImage/);
  assert.match(gameAdminScript, /const image=safeImage\(s\.image_url\)/);
  assert.match(gameAdminScript, /fmt\(r\.wagered\)/);
  assert.match(gameAdminScript, /fmt\(r\.players\)/);
  assert.match(worker, /COALESCE\(b\.wagered,0\) AS wagered/);
  assert.match(worker, /THEN config_snapshot ELSE NULL END AS config_snapshot/);
});

test("bet debit, ledger entry and bet insert use the same idempotent transaction id", () => {
  assert.ok(worker.includes(".bind(betId,roundId,-amount,now,user.id)"));
  assert.match(worker, /INSERT OR IGNORE INTO cat_greed_bet_requests/);
  assert.match(worker, /WHERE idempotency_key=\? AND bet_id=\? AND user_id=\?/);
  assert.match(worker, /duplicateBet/);
});

test("new migration defaults keep the maximum expected return below the activation cap", () => {
  const multipliers = [45,5,15,5,25,5,10,5];
  const weights = [192,1988,648,1988,372,1988,972,1988];
  const total = weights.reduce((a,b)=>a+b,0);
  const maximum = Math.max(...weights.map((weight,index) =>
    Math.ceil((9940 * weight / total + 30) * multipliers[index])
  ));
  assert.ok(maximum <= 10000, "default theoretical return must stay at or below 100%");
});

test("pausing Cat Greed blocks new bets but keeps the active round visible for settlement", () => {
  assert.match(worker, /if \(publicBet && !settings\.enabled\)/);
  assert.match(worker, /currentRound\(db,settings\.enabled===1\)/);
  assert.match(worker, /enabled:settings\.enabled===1/);
  assert.match(gameScript, /n\.enabled!==true&&!n\.roundId/);
  assert.match(flutterGame, /next\['enabled'\]!=true&&next\['roundId'\]==null/);
});

test("standalone Cat Greed scripts are external and route CSP blocks inline script execution", () => {
  assert.match(gameSite, /<script src="app\.js" defer><\/script>/);
  assert.match(gameAdmin, /<script src="app\.js" defer><\/script>/);
  assert.match(pageHeaders, /script-src 'self'/);
  assert.match(pageHeaders, /frame-ancestors 'none'/);
  assert.ok(pageHeaders.slice(pageHeaders.indexOf("/cat-greed-admin/*")).includes("https://*.taher616270.workers.dev"));
  assert.match(gameScript, /location\.hostname==="happy-live\.pages\.dev"/);
  assert.match(gameAdminScript, /location\.hostname==="happy-live\.pages\.dev"/);
  assert.match(gameScript, /catGreedApi/);
  assert.match(gameAdminScript, /catGreedApi/);
  assert.match(mainAdmin, /location\.hostname!=="happy-live\.pages\.dev"/);
  assert.match(flutterGame, /Uri\.base\.queryParameters\['catGreedApi'\]/);
  assert.match(flutterGame, /host\.endsWith\('\.taher616270\.workers\.dev'\)/);
});

test("Preview migrations are explicitly isolated from the production D1 database", () => {
  assert.match(previewMigrationConfig, /database_name = "happy-live-room-exp-preview-db"/);
  assert.match(previewMigrationConfig, /database_id = "7ade3803-97bf-4f6d-9200-48b3dfb0573c"/);
  assert.match(previewMigrationConfig, /binding = "PREVIEW_DB"/);
  assert.match(previewMigrationConfig, /migrations_dir = "migrations-cat-greed-preview"/);
  assert.doesNotMatch(previewMigrationConfig, /migrations_dir = "migrations"/);
  assert.match(wranglerConfig, /database_name = "happy-live-room-exp-preview-db"/);
  assert.match(wranglerConfig, /preview_urls = true/);
  assert.match(wranglerConfig, /migrations_dir = "migrations-cat-greed-preview"/);
  assert.match(wranglerConfig, /database_name = "happy-live-db"/);
  assert.match(packageJson.scripts["db:preview"], /wrangler\.preview-migrations\.toml/);
  assert.match(packageJson.scripts["db:preview"], /happy-live-room-exp-preview-db/);
  assert.match(previewMigrationConfig, /migrations_dir = "migrations-cat-greed-preview"/);
  assert.match(packageJson.scripts["preview:deploy"], /wrangler preview --name cat-greed --ignore-base-config/);
  assert.match(packageJson.scripts["preview:secrets:list"], /preview secret list --name cat-greed/);
});

test("manual production Worker deployment applies all Cat Greed migrations before deploy", () => {
  assert.match(deployWorkflow, /workflow_dispatch:/);
  const m34 = deployWorkflow.indexOf("migrations/0034_cat_greed_wheel.sql");
  const m35 = deployWorkflow.indexOf("migrations/0035_cat_greed_ledger.sql");
  const m36 = deployWorkflow.indexOf("migrations/0036_cat_greed_bet_protection.sql");
  const m37 = deployWorkflow.indexOf("migrations/0037_cat_greed_round_guard.sql");
  const deploy = deployWorkflow.indexOf("Deploy Worker with Wrangler");
  assert.ok(m34 >= 0 && m35 > m34 && m36 > m35 && m37 > m36 && deploy > m37);
});

test("Preview-only migration copies stay byte-identical to the canonical Cat Greed migrations", () => {
  assert.equal(previewWheelMigration, migration);
  assert.equal(previewLedgerMigration, ledgerMigration);
  assert.equal(previewProtectionMigration, protectionMigration);
  assert.equal(previewRoundGuardMigration, roundGuardMigration);
});

test("Cat Greed Preview deployment is manual, confirmed, and cannot target production", () => {
  assert.match(previewDeployWorkflow, /workflow_dispatch:/);
  assert.match(previewDeployWorkflow, /confirm_preview_only/);
  assert.match(previewDeployWorkflow, /npm run db:preview/);
  assert.match(previewDeployWorkflow, /npm run preview:deploy/);
  assert.doesNotMatch(previewDeployWorkflow, /db:remote|happy-live-db|wrangler deploy/);
});

test("admin write endpoints reject oversized and non-JSON request bodies", () => {
  assert.match(worker, /async function readBoundedJson\(request: Request, maxBytes: number\)/);
  assert.match(worker, /content_type_not_supported/);
  assert.match(worker, /request\.body\?\.getReader\(\)/);
  assert.match(worker, /total > maxBytes/);
  assert.match(worker, /await reader\.cancel\(\)/);
  assert.match(worker, /readBoundedJson\(request,2048\)/);
  assert.match(worker, /readBoundedJson\(request,16384\)/);
  assert.doesNotMatch(worker, /request\.json\(\)/);
});

test("player win/loss statistics count settled rounds only", () => {
  assert.match(worker, /INNER JOIN cat_greed_rounds r ON r\.id=b\.round_id/);
  assert.match(worker, /CASE WHEN r\.phase='result' THEN 1 ELSE 0 END AS settled/);
  assert.match(worker, /settled=1 AND payout>0/);
  assert.match(worker, /settled=1 AND payout=0/);
  assert.match(worker, /SUM\(CASE WHEN settled=1 THEN wagered ELSE 0 END\) AS settledWagered/);
});

test("both admin entry points warn before enabling cash-value wagering", () => {
  assert.match(gameAdminScript, /currentEnabled!==1/);
  assert.match(gameAdminScript, /احتياطي يغطي أقصى الجوائز/);
  assert.match(mainAdmin, /احتياطي يغطي أقصى الجوائز/);
});

test("D1 independently rejects unsupported chips and bets on closed rounds", () => {
  assert.match(roundGuardMigration, /CREATE TRIGGER IF NOT EXISTS cat_greed_bet_guard_insert/);
  assert.match(roundGuardMigration, /NEW\.amount NOT IN \(10, 500, 6000, 30000, 100000\)/);
  assert.match(roundGuardMigration, /phase='betting' AND julianday\(closes_at\)>julianday\('now'\)/);
  assert.match(roundGuardMigration, /invalid_or_closed_cat_greed_bet/);
});
