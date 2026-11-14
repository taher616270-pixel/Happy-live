type FoodWheelUser = { id: string; gabo_id?: string | null };
type FoodWheelAdmin = { id: string; username: string; role: string };
type FoodWheelEnv = { DB?: D1Database };
type FoodWheelJson = (data: unknown, status: number, origin?: string, env?: any) => Response;

type FoodWheelSettings = {
  enabled: number;
  betting_seconds: number;
  result_seconds: number;
  salad_weight_bp: number;
  pizza_weight_bp: number;
};
type FoodWheelSymbol = {
  slot: number; emoji: string; label: string; multiplier: number;
  is_vegetable: number; weight: number; image_url: string | null;
};
type FoodWheelSnapshot = {
  rulesVersion: number;
  bettingSeconds: number; resultSeconds: number; saladWeightBp: number; pizzaWeightBp: number;
  symbols: Array<{slot:number;emoji:string;label:string;multiplier:number;isVegetable:boolean;weight:number;imageUrl:string|null}>;
};
type FoodWheelRound = {
  id: string;
  phase: "betting" | "result";
  closes_at: string;
  settled_at: string | null;
  created_at: string;
  config_snapshot: string;
  result_slot: number | null;
  special: string | null;
  server_seed: string;
  seed_commitment: string;
};

const BET_CHIPS = new Set([10, 500, 6000, 30000, 100000]);
// Each player may place at most six individual bets in one round.
const MAX_BETS_PER_ROUND = 6;
// Round flow: 30s betting, 5s wheel selection, then a 3s result panel.
const SPIN_SECONDS = 5;
const RESULT_DISPLAY_SECONDS = 3;
const OUTCOME_REVEAL_OFFSET_SECONDS = SPIN_SECONDS - 1;
const ROUND_CYCLE_SECONDS = SPIN_SECONDS + RESULT_DISPLAY_SECONDS;
const BET_RATE_WINDOW_SECONDS = 10;
const BET_RATE_MAX_REQUESTS = 10;
const STATE_RATE_WINDOW_SECONDS = 60;
const STATE_RATE_MAX_REQUESTS = 90;
const isoNow = () => new Date().toISOString();

// Saudi Arabia uses UTC+3 year-round. Count rounds from Riyadh midnight.
function saudiDayStartIso(nowMs = Date.now()): string {
  const offsetMs = 3 * 60 * 60 * 1000;
  const saudiNow = new Date(nowMs + offsetMs);
  const midnightUtc = Date.UTC(
    saudiNow.getUTCFullYear(),
    saudiNow.getUTCMonth(),
    saudiNow.getUTCDate()
  ) - offsetMs;
  return new Date(midnightUtc).toISOString();
}

function isValidImageKitUrl(value: string): boolean {
  if (!value || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" &&
      (url.hostname === "ik.imagekit.io" || url.hostname.endsWith(".imagekit.io")) &&
      !url.username && !url.password && !url.port;
  } catch {
    return false;
  }
}

function calculateOdds(snapshot: FoodWheelSnapshot) {
  const totalWeight = snapshot.symbols.reduce((sum, symbol) => sum + Math.max(0, symbol.weight), 0);
  if (totalWeight <= 0) return [];
  const regularWeightBp = 10000 - snapshot.saladWeightBp - snapshot.pizzaWeightBp;
  return snapshot.symbols.map(symbol => {
    const appearanceRawBp = regularWeightBp * Math.max(0, symbol.weight) / totalWeight;
    const winRawBp = appearanceRawBp +
      (symbol.isVegetable ? snapshot.saladWeightBp : snapshot.pizzaWeightBp);
    return {
      slot: symbol.slot,
      appearanceProbabilityBp: Math.round(appearanceRawBp),
      winProbabilityBp: Math.round(winRawBp),
      // Round upward for the activation guard so display rounding can never hide excess exposure.
      expectedReturnBp: Math.ceil(winRawBp * symbol.multiplier)
    };
  });
}

function maxExpectedReturnBp(snapshot: FoodWheelSnapshot): number {
  return Math.max(0, ...calculateOdds(snapshot).map(odds => odds.expectedReturnBp));
}
const randomHex = (size = 32) => Array.from(crypto.getRandomValues(new Uint8Array(size))).map(x => x.toString(16).padStart(2, "0")).join("");
async function digestHex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes)).map(x => x.toString(16).padStart(2, "0")).join("");
}
async function getSettings(db: D1Database): Promise<FoodWheelSettings> {
  await db.prepare("INSERT OR IGNORE INTO cat_greed_settings (id, updated_at) VALUES ('current', ?)").bind(isoNow()).run();
  return (await db.prepare("SELECT enabled, betting_seconds, result_seconds, salad_weight_bp, pizza_weight_bp FROM cat_greed_settings WHERE id='current'").first<FoodWheelSettings>())!;
}
async function getSymbols(db: D1Database): Promise<FoodWheelSymbol[]> {
  const rows = await db.prepare("SELECT slot, emoji, label, multiplier, is_vegetable, weight, image_url FROM cat_greed_symbols ORDER BY slot").all<FoodWheelSymbol>();
  return rows.results ?? [];
}
function makeSnapshot(settings: FoodWheelSettings, symbols: FoodWheelSymbol[]): FoodWheelSnapshot {
  return {
    rulesVersion: 1,
    bettingSeconds: settings.betting_seconds, resultSeconds: settings.result_seconds,
    saladWeightBp: settings.salad_weight_bp, pizzaWeightBp: settings.pizza_weight_bp,
    symbols: symbols.map(s => ({slot:s.slot,emoji:s.emoji,label:s.label,multiplier:s.multiplier,isVegetable:!!s.is_vegetable,weight:s.weight,imageUrl:s.image_url}))
  };
}
async function createRound(db: D1Database): Promise<any> {
  const settings = await getSettings(db);
  const symbols = await getSymbols(db);
  const snapshot = makeSnapshot(settings, symbols);
  if (snapshot.symbols.length !== 8 || new Set(snapshot.symbols.map(symbol => symbol.slot)).size !== 8 ||
      snapshot.symbols.some((symbol, index) => symbol.slot !== index) ||
      snapshot.symbols.reduce((sum, symbol) => sum + symbol.weight, 0) <= 0) {
    throw new Error("wheel_configuration_invalid");
  }
  const id = crypto.randomUUID();
  const seed = randomHex();
  const configSnapshot = JSON.stringify(snapshot);
  const commitment = await digestHex("commit|" + seed + "|" + id + "|" + configSnapshot);
  const now = Date.now();
  const startsAt = new Date(now).toISOString();
  const closesAt = new Date(now + settings.betting_seconds * 1000).toISOString();
  await db.prepare(
    "INSERT INTO cat_greed_rounds (id, phase, starts_at, closes_at, server_seed, seed_commitment, config_snapshot, created_at) VALUES (?, 'betting', ?, ?, ?, ?, ?, ?)"
  ).bind(id, startsAt, closesAt, seed, commitment, configSnapshot, startsAt).run();
  return db.prepare("SELECT * FROM cat_greed_rounds WHERE id=?").bind(id).first();
}
async function unitRandom(round: any): Promise<number> {
  const hex = await digestHex("outcome|" + round.server_seed + "|" + round.id + "|" + round.config_snapshot);
  // 13 hex digits are exactly 52 bits, safely represented by a JS number.
  return parseInt(hex.slice(0, 13), 16) / 4503599627370496;
}
async function chooseOutcome(round: any): Promise<{slot:number|null;special:string|null}> {
  const config = JSON.parse(round.config_snapshot) as FoodWheelSnapshot;
  const sample = await unitRandom(round);
  const salad = config.saladWeightBp / 10000;
  const pizza = config.pizzaWeightBp / 10000;
  if (sample < salad) return {slot:null,special:"salad"};
  if (sample < salad + pizza) return {slot:null,special:"pizza"};
  const weights = config.symbols.map(s => Math.max(0, s.weight));
  const total = weights.reduce((a,b)=>a+b,0);
  if (total <= 0) throw new Error("wheel_symbols_have_no_weight");
  let pick = ((sample - salad - pizza) / Math.max(0.0000001, 1 - salad - pizza)) * total;
  for (let i=0;i<weights.length;i++) { pick -= weights[i]; if (pick < 0) return {slot:i,special:null}; }
  return {slot:7,special:null};
}
async function payRound(db: D1Database, round: any): Promise<void> {
  const config = JSON.parse(round.config_snapshot) as FoodWheelSnapshot;
  const bets = await db.prepare("SELECT user_id, slot, SUM(amount) AS amount FROM cat_greed_bets WHERE round_id=? GROUP BY user_id, slot").bind(round.id).all<{user_id:string;slot:number;amount:number}>();
  const alreadyPaid = await db.prepare("SELECT user_id FROM cat_greed_payouts WHERE round_id=? AND paid_at IS NOT NULL").bind(round.id).all<{user_id:string}>();
  const paidUsers = new Set((alreadyPaid.results ?? []).map(row => row.user_id));
  const totals = new Map<string, number>();
  for (const bet of bets.results ?? []) {
    const symbol = config.symbols.find(s => s.slot === bet.slot);
    if (!symbol) continue;
    const wins = round.special === "salad" ? symbol.isVegetable : round.special === "pizza" ? !symbol.isVegetable : round.result_slot === bet.slot;
    if (wins) totals.set(bet.user_id, (totals.get(bet.user_id) ?? 0) + bet.amount * symbol.multiplier);
  }

  // Each user's payout is claimed with a fresh transaction id before the wallet
  // changes. Concurrent state requests can therefore never credit the same round twice.
  for (const [userId, amount] of totals) {
    if (paidUsers.has(userId) || !Number.isSafeInteger(amount) || amount <= 0) continue;
    const now = isoNow();
    const transactionId = crypto.randomUUID();
    await db.batch([
      db.prepare("INSERT OR IGNORE INTO user_wallets (user_id,balance,updated_at) VALUES (?,0,?)").bind(userId,now),
      db.prepare("INSERT OR IGNORE INTO cat_greed_payouts (round_id,user_id,amount,created_at,paid_at,transaction_id) VALUES (?,?,?, ?,NULL,NULL)").bind(round.id,userId,amount,now),
      db.prepare("UPDATE cat_greed_payouts SET paid_at=?,transaction_id=? WHERE round_id=? AND user_id=? AND paid_at IS NULL").bind(now,transactionId,round.id,userId),
      db.prepare("UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND EXISTS (SELECT 1 FROM cat_greed_payouts WHERE round_id=? AND user_id=? AND paid_at=? AND transaction_id=?)").bind(amount,now,userId,round.id,userId,now,transactionId),
      db.prepare("INSERT INTO cat_greed_ledger (id,user_id,round_id,amount,balance_after,transaction_type,description,created_at) SELECT ?,user_id,?,?,balance,'payout','جائزة عجلة الأطعمة',? FROM user_wallets WHERE user_id=? AND changes()=1 AND EXISTS (SELECT 1 FROM cat_greed_payouts WHERE round_id=? AND user_id=? AND paid_at=? AND transaction_id=?)").bind(transactionId,round.id,amount,now,userId,round.id,userId,now,transactionId)
    ]);
  }
}
async function settleRound(db: D1Database, round: any): Promise<any> {
  if (round.phase === "betting" && Date.parse(round.closes_at) + OUTCOME_REVEAL_OFFSET_SECONDS * 1000 <= Date.now()) {
    const outcome = await chooseOutcome(round);
    const now = isoNow();
    const eligibleCloseTime = new Date(Date.now() - OUTCOME_REVEAL_OFFSET_SECONDS * 1000).toISOString();
    await db.prepare("UPDATE cat_greed_rounds SET phase='result', result_slot=?, special=?, settled_at=? WHERE id=? AND phase='betting' AND closes_at<=?")
      .bind(outcome.slot,outcome.special,now,round.id,eligibleCloseTime).run();
  }
  const settled = await db.prepare("SELECT * FROM cat_greed_rounds WHERE id=?").bind(round.id).first();
  if (settled?.phase === "result") await payRound(db, settled);
  return settled;
}
async function currentRound(db: D1Database, allowCreate = true): Promise<FoodWheelRound | null> {
  let round = await db.prepare("SELECT * FROM cat_greed_rounds WHERE phase='betting' ORDER BY created_at DESC LIMIT 1").first<FoodWheelRound>();
  if (!round) round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first<FoodWheelRound>();
  if (!round && allowCreate) {
    try { round = await createRound(db); }
    catch { round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first<FoodWheelRound>(); }
  }
  if (round?.phase === "betting" && Date.parse(round.closes_at) + OUTCOME_REVEAL_OFFSET_SECONDS * 1000 <= Date.now()) round = await settleRound(db, round);
  if (allowCreate && round?.phase === "result" && Date.now() - Date.parse(round.closes_at) >= ROUND_CYCLE_SECONDS * 1000) {
    try { round = await createRound(db); }
    catch { round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first<FoodWheelRound>(); }
  }
  return round;
}
function wheelError(message: string, status: number, json: FoodWheelJson, origin?: string, env?: unknown) {
  return json({error:message},status,origin,env);
}

async function readBoundedJson(request: Request, maxBytes: number): Promise<{ok:true;value:any}|{ok:false;status:number;error:string}> {
  const contentType = (request.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase();
  if (contentType !== "application/json") return {ok:false,status:415,error:"content_type_not_supported"};
  const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) return {ok:false,status:413,error:"request_too_large"};
  const reader = request.body?.getReader();
  if (!reader) return {ok:false,status:400,error:"invalid_json"};
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const part = await reader.read();
    if (part.done) break;
    total += part.value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return {ok:false,status:413,error:"request_too_large"};
    }
    chunks.push(part.value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.byteLength; }
  try { return {ok:true,value:JSON.parse(new TextDecoder("utf-8",{fatal:true,ignoreBOM:false}).decode(bytes))}; }
  catch { return {ok:false,status:400,error:"invalid_json"}; }
}
export async function handleFoodWheelRequest(
  request: Request, env: FoodWheelEnv, origin: string | undefined,
  authenticateUser: (request:Request,db:D1Database)=>Promise<FoodWheelUser|null>,
  authenticateAdmin: (request:Request,db:D1Database)=>Promise<FoodWheelAdmin|null>,
  json: FoodWheelJson
): Promise<Response|null> {
  const path = new URL(request.url).pathname;
  const publicState = (path === "/api/v1/games/food-wheel/state" || path === "/api/v1/games/cat-greed/state") && request.method === "GET";
  const publicBet = (path === "/api/v1/games/food-wheel/bet" || path === "/api/v1/games/cat-greed/bet") && request.method === "POST";
  const mainOverview = (path === "/api/v1/admin/games/food-wheel/overview" || path === "/api/v1/admin/games/cat-greed/overview") && request.method === "GET";
  const playerControl = path.match(/^\/api\/v1\/admin\/games\/(?:food-wheel|cat-greed)\/players\/([0-9a-f-]{36})$/i);
  const adminSettings = path === "/api/v1/admin/food-wheel/settings" || path === "/api/v1/admin/cat-greed/settings";
  const adminSymbols = path === "/api/v1/admin/food-wheel/symbols" || path === "/api/v1/admin/cat-greed/symbols";
  const adminRounds = (path === "/api/v1/admin/food-wheel/rounds" || path === "/api/v1/admin/cat-greed/rounds") && request.method === "GET";
  if (!publicState && !publicBet && !mainOverview && !playerControl && !adminSettings && !adminSymbols && !adminRounds) return null;
  if (!env.DB) return wheelError("database_unavailable",503,json,origin,env);
  const db = env.DB;
  try {
    if (publicState || publicBet) {
      const user = await authenticateUser(request,db);
      if (!user) return wheelError("authentication_required",401,json,origin,env);
      if(publicState){
        const nowSeconds=Math.floor(Date.now()/1000);
        const rate=await db.prepare("INSERT INTO cat_greed_state_rate_limits (user_id,window_start,request_count) VALUES (?,?,1) ON CONFLICT(user_id) DO UPDATE SET window_start=CASE WHEN excluded.window_start-cat_greed_state_rate_limits.window_start>=? THEN excluded.window_start ELSE cat_greed_state_rate_limits.window_start END,request_count=CASE WHEN excluded.window_start-cat_greed_state_rate_limits.window_start>=? THEN 1 ELSE cat_greed_state_rate_limits.request_count+1 END RETURNING request_count,window_start")
          .bind(user.id,nowSeconds,STATE_RATE_WINDOW_SECONDS,STATE_RATE_WINDOW_SECONDS).first<{request_count:number;window_start:number}>();
        if(!rate||rate.request_count>STATE_RATE_MAX_REQUESTS) return json({error:"state_rate_limited",retry_after_seconds:Math.max(1,(rate?.window_start??nowSeconds)+STATE_RATE_WINDOW_SECONDS-nowSeconds)},429,origin,env);
      }
      const settings = await getSettings(db);
      if (publicBet && !settings.enabled) return json({enabled:false,error:"game_disabled"},423,origin,env);
      let round = await currentRound(db,settings.enabled===1);
      if (!round) return json({enabled:false,error:"game_disabled"},423,origin,env);
      let betReceipt: { id: string; roundId: string; slot: number; amount: number } | null = null;
      let duplicateBet = false;
      if (publicBet) {
        const parsed = await readBoundedJson(request,2048);
        if (!parsed.ok) return wheelError(parsed.error,parsed.status,json,origin,env);
        const body = parsed.value;
        if (!body || typeof body !== "object" || Array.isArray(body)) return wheelError("invalid_bet",400,json,origin,env);
        const slot = Number(body.slot), amount = Number(body.amount), roundId = String(body.roundId ?? "");
        const idempotencyKey = String(body.idempotencyKey ?? "");
        if (!Number.isInteger(slot) || slot<0 || slot>7 || !BET_CHIPS.has(amount) ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey)) {
          return wheelError("invalid_bet",400,json,origin,env);
        }
        // Count every authenticated bet request, including idempotent retries.
        // Otherwise a client can bypass the burst limit by replaying a known key.
        const nowSeconds = Math.floor(Date.now()/1000);
        const rate = await db.prepare("INSERT INTO cat_greed_bet_rate_limits (user_id,window_start,request_count) VALUES (?,?,1) ON CONFLICT(user_id) DO UPDATE SET window_start=CASE WHEN excluded.window_start-cat_greed_bet_rate_limits.window_start>=? THEN excluded.window_start ELSE cat_greed_bet_rate_limits.window_start END,request_count=CASE WHEN excluded.window_start-cat_greed_bet_rate_limits.window_start>=? THEN 1 ELSE cat_greed_bet_rate_limits.request_count+1 END RETURNING request_count,window_start")
          .bind(user.id,nowSeconds,BET_RATE_WINDOW_SECONDS,BET_RATE_WINDOW_SECONDS).first<{request_count:number;window_start:number}>();
        if (!rate || rate.request_count>BET_RATE_MAX_REQUESTS) return json({error:"bet_rate_limited",retry_after_seconds:Math.max(1,(rate?.window_start??nowSeconds)+BET_RATE_WINDOW_SECONDS-nowSeconds)},429,origin,env);

        const prior = await db.prepare("SELECT round_id,slot,amount,bet_id FROM cat_greed_bet_requests WHERE idempotency_key=? AND user_id=?")
          .bind(idempotencyKey,user.id).first<{round_id:string;slot:number;amount:number;bet_id:string}>();
        if (prior) {
          if (prior.round_id!==roundId || prior.slot!==slot || prior.amount!==amount) return wheelError("idempotency_key_reused",409,json,origin,env);
          const existingBet = await db.prepare("SELECT id FROM cat_greed_bets WHERE id=? AND round_id=? AND user_id=?")
            .bind(prior.bet_id,roundId,user.id).first();
          if (!existingBet) return wheelError("bet_request_incomplete",409,json,origin,env);
          betReceipt={id:prior.bet_id,roundId,slot,amount};
          duplicateBet=true;
        } else {
          if (!round || round.id !== roundId || round.phase !== "betting" || Date.parse(round.closes_at)<=Date.now()) return wheelError("round_closed",409,json,origin,env);
          await db.prepare("INSERT OR IGNORE INTO user_wallets (user_id,balance,updated_at) VALUES (?,0,?)").bind(user.id,isoNow()).run();
          const control = await db.prepare("SELECT enabled,max_bet_per_round FROM cat_greed_player_controls WHERE user_id=?").bind(user.id).first<{enabled:number;max_bet_per_round:number}>();
          if (control?.enabled===0) return wheelError("player_disabled",403,json,origin,env);
          const currentTotal = await db.prepare("SELECT COALESCE(SUM(amount),0) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=?").bind(roundId,user.id).first<{total:number}>();
          const limit = control?.max_bet_per_round ?? 1000000;
          if ((currentTotal?.total ?? 0) + amount > limit) return wheelError("bet_limit_exceeded",400,json,origin,env);

          const now=isoNow(), betId=crypto.randomUUID();
          await db.batch([
            db.prepare("INSERT OR IGNORE INTO cat_greed_bet_requests (idempotency_key,user_id,round_id,slot,amount,bet_id,created_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM user_wallets WHERE user_id=? AND balance>=?) AND EXISTS (SELECT 1 FROM cat_greed_rounds WHERE id=? AND phase='betting' AND closes_at>?) AND NOT EXISTS (SELECT 1 FROM cat_greed_player_controls WHERE user_id=? AND enabled=0) AND (SELECT COUNT(*) FROM cat_greed_bets WHERE round_id=? AND user_id=?) < ? AND (SELECT COALESCE(SUM(amount),0) FROM cat_greed_bets WHERE round_id=? AND user_id=?) + ? <= COALESCE((SELECT max_bet_per_round FROM cat_greed_player_controls WHERE user_id=?),1000000) ")
              .bind(idempotencyKey,user.id,roundId,slot,amount,betId,now,user.id,amount,roundId,now,user.id,roundId,user.id,MAX_BETS_PER_ROUND,roundId,user.id,amount,user.id),
            db.prepare("UPDATE user_wallets SET balance=balance-?,updated_at=? WHERE user_id=? AND balance>=? AND EXISTS (SELECT 1 FROM cat_greed_bet_requests WHERE idempotency_key=? AND bet_id=? AND user_id=?) AND EXISTS (SELECT 1 FROM cat_greed_rounds WHERE id=? AND phase='betting' AND closes_at>?)")
              .bind(amount,now,user.id,amount,idempotencyKey,betId,user.id,roundId,now),
            db.prepare("INSERT INTO cat_greed_ledger (id,user_id,round_id,amount,balance_after,transaction_type,description,created_at) SELECT ?,user_id,?,?,balance,'bet','رهان عجلة الأطعمة',? FROM user_wallets WHERE user_id=? AND changes()=1")
              .bind(betId,roundId,-amount,now,user.id),
            db.prepare("INSERT INTO cat_greed_bets (id,round_id,user_id,slot,amount,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM cat_greed_ledger WHERE id=?)")
              .bind(betId,roundId,user.id,slot,amount,now,betId)
          ]);
          let placed = await db.prepare("SELECT id FROM cat_greed_bets WHERE id=? AND round_id=? AND user_id=?")
            .bind(betId,roundId,user.id).first();
          if (!placed) {
            // A concurrent retry may have inserted the same idempotency key first.
            const concurrent = await db.prepare("SELECT round_id,slot,amount,bet_id FROM cat_greed_bet_requests WHERE idempotency_key=? AND user_id=?")
              .bind(idempotencyKey,user.id).first<{round_id:string;slot:number;amount:number;bet_id:string}>();
            if (concurrent && concurrent.round_id===roundId && concurrent.slot===slot && concurrent.amount===amount) {
              placed = await db.prepare("SELECT id FROM cat_greed_bets WHERE id=? AND round_id=? AND user_id=?")
                .bind(concurrent.bet_id,roundId,user.id).first();
              if (placed) { betReceipt={id:concurrent.bet_id,roundId,slot,amount}; duplicateBet=true; }
            }
          }
          if (!placed) {
            const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=?").bind(user.id).first<{balance:number}>();
            const latestTotal = await db.prepare("SELECT COALESCE(SUM(amount),0) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=?").bind(roundId,user.id).first<{total:number}>();
            const latestControl = await db.prepare("SELECT enabled,max_bet_per_round FROM cat_greed_player_controls WHERE user_id=?").bind(user.id).first<{enabled:number;max_bet_per_round:number}>();
            if (latestControl?.enabled===0) return wheelError("player_disabled",403,json,origin,env);
            if ((latestTotal?.total ?? 0) + amount > (latestControl?.max_bet_per_round ?? 1000000)) return wheelError("bet_limit_exceeded",400,json,origin,env);
            const latestCount = await db.prepare("SELECT COUNT(*) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=?").bind(roundId,user.id).first<{total:number}>();
            if ((latestCount?.total ?? 0) >= MAX_BETS_PER_ROUND) return wheelError("bet_count_limit",409,json,origin,env);
            return wheelError((wallet?.balance ?? 0)<amount ? "insufficient_balance" : "round_closed",409,json,origin,env);
          }
          if(!duplicateBet) betReceipt={id:betId,roundId,slot,amount};
        }
        round = await currentRound(db);
        if (!round) return json({enabled:false,error:"game_disabled"},423,origin,env);
      }
      const pools = await db.prepare("SELECT slot,SUM(amount) AS total FROM cat_greed_bets WHERE round_id=? GROUP BY slot").bind(round.id).all<{slot:number;total:number}>();
      const mine = await db.prepare("SELECT slot,SUM(amount) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=? GROUP BY slot").bind(round.id,user.id).all<{slot:number;total:number}>();
      const myBetCountRow = await db.prepare("SELECT COUNT(*) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=?").bind(round.id,user.id).first<{total:number}>();
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=?").bind(user.id).first<{balance:number}>();
      const payout = await db.prepare("SELECT amount,round_id FROM cat_greed_payouts WHERE user_id=? AND round_id=? AND paid_at IS NOT NULL").bind(user.id,round.id).first<{amount:number;round_id:string}>();
      const history = await db.prepare("SELECT result_slot,special,config_snapshot FROM cat_greed_rounds WHERE phase='result' ORDER BY settled_at DESC LIMIT 9").all<{result_slot:number|null;special:string|null;config_snapshot:string}>();
      const config = JSON.parse(round.config_snapshot) as FoodWheelSnapshot;
      const odds = calculateOdds(config);
      const nowMs = Date.now();
      const closesAtMs = Date.parse(round.closes_at);
      const spinEndsAtMs = closesAtMs + SPIN_SECONDS * 1000;
      const cycleEndsAtMs = closesAtMs + ROUND_CYCLE_SECONDS * 1000;
      const outcomeReady = round.phase === "result";
      const clientPhase = nowMs < closesAtMs ? "betting" : nowMs < spinEndsAtMs ? "spinning" : "result";
      const phaseDeadlineMs = clientPhase === "betting" ? closesAtMs : clientPhase === "spinning" ? spinEndsAtMs : cycleEndsAtMs;
      const topWinners = outcomeReady
        ? await db.prepare("SELECT COALESCE(NULLIF(TRIM(p.display_name),''),'لاعب') AS name, COALESCE(p.gabo_id,'') AS userCode, cp.amount AS payout FROM cat_greed_payouts cp LEFT JOIN profiles p ON p.user_id=cp.user_id WHERE cp.round_id=? AND cp.paid_at IS NOT NULL ORDER BY cp.amount DESC, cp.created_at ASC LIMIT 3")
            .bind(round.id).all<{name:string;userCode:string;payout:number}>()
        : {results:[] as Array<{name:string;userCode:string;payout:number}>};
      const dayStart = saudiDayStartIso();
      const dailyRounds = await db.prepare(
        "SELECT COUNT(*) AS total FROM cat_greed_rounds WHERE starts_at >= ? AND starts_at <= ?"
      ).bind(dayStart, isoNow()).first<{total:number}>();
      const dailyRoundNumber = Math.max(1, dailyRounds?.total ?? 0);
      return json({
        enabled:settings.enabled===1,roundId:round.id,userCode:user.gabo_id??'',dailyRoundNumber,secondsLeft:Math.max(0,Math.ceil((phaseDeadlineMs-nowMs)/1000)),
        phase:clientPhase,pools:Array.from({length:8},(_,i)=>pools.results?.find(x=>x.slot===i)?.total??0),
        myBets:Array.from({length:8},(_,i)=>mine.results?.find(x=>x.slot===i)?.total??0),
        myBetCount:myBetCountRow?.total??0,maxBetsPerRound:MAX_BETS_PER_ROUND,
        balance:wallet?.balance??0,myPayout:payout?.amount??0,myPayoutRoundId:payout?.round_id??null,
        resultSlot:outcomeReady?round.result_slot:null,special:outcomeReady?round.special:null,
        seedCommitment:round.seed_commitment,revealedSeed:outcomeReady?round.server_seed:null,configSnapshot:outcomeReady?round.config_snapshot:null,
        topWinners:topWinners.results??[],symbols:config.symbols,odds,specialOdds:{saladWeightBp:config.saladWeightBp,pizzaWeightBp:config.pizzaWeightBp},
        betReceipt,duplicateBet,
        history:(history.results??[]).map(x=>{const old=JSON.parse(x.config_snapshot) as FoodWheelSnapshot;return x.special==="salad"?"🥗":x.special==="pizza"?"🍕":old.symbols.find(s=>s.slot===x.result_slot)?.emoji??"—";})
      },200,origin,env);
    }

    const admin = await authenticateAdmin(request,db);
    if (!admin) return wheelError("authentication_required",401,json,origin,env);
    if (admin.role!=="owner" && admin.role!=="admin") return wheelError("permission_denied",403,json,origin,env);
    if (mainOverview) {
      // Admin reads also settle an expired round and complete idempotent payouts;
      // the overview must not classify unpaid winners as losses.
      await currentRound(db,false);
      const [settings,symbols,rounds,players,totals] = await Promise.all([
        getSettings(db),getSymbols(db),
        db.prepare("SELECT r.id,r.phase,r.starts_at,r.closes_at,r.result_slot,r.special,r.seed_commitment,r.settled_at,COALESCE(b.wagered,0) AS wagered,COALESCE(b.players,0) AS players FROM cat_greed_rounds r LEFT JOIN (SELECT round_id,SUM(amount) AS wagered,COUNT(DISTINCT user_id) AS players FROM cat_greed_bets GROUP BY round_id) b ON b.round_id=r.id ORDER BY r.created_at DESC LIMIT 20").all(),
        db.prepare("SELECT u.id,p.display_name AS name,p.gabo_id AS userCode,COALESCE(c.enabled,1) AS enabled,COALESCE(c.max_bet_per_round,1000000) AS maxBetPerRound,COALESCE(b.rounds,0) AS rounds,COALESCE(b.wagered,0) AS wagered,COALESCE(b.settledWagered,0) AS settledWagered,COALESCE(b.wins,0) AS wins,COALESCE(b.losses,0) AS losses,COALESCE(b.paid,0) AS paid FROM users u LEFT JOIN profiles p ON p.user_id=u.id LEFT JOIN cat_greed_player_controls c ON c.user_id=u.id LEFT JOIN (SELECT user_id,SUM(settled) AS rounds,SUM(wagered) AS wagered,SUM(CASE WHEN settled=1 THEN wagered ELSE 0 END) AS settledWagered,SUM(CASE WHEN settled=1 AND payout>0 THEN 1 ELSE 0 END) AS wins,SUM(CASE WHEN settled=1 AND payout=0 THEN 1 ELSE 0 END) AS losses,SUM(payout) AS paid FROM (SELECT b.user_id,b.round_id,SUM(b.amount) AS wagered,COALESCE(p.amount,0) AS payout,CASE WHEN r.phase='result' THEN 1 ELSE 0 END AS settled FROM cat_greed_bets b INNER JOIN cat_greed_rounds r ON r.id=b.round_id LEFT JOIN cat_greed_payouts p ON p.user_id=b.user_id AND p.round_id=b.round_id AND p.paid_at IS NOT NULL GROUP BY b.user_id,b.round_id) GROUP BY user_id) b ON b.user_id=u.id WHERE b.user_id IS NOT NULL ORDER BY wagered DESC LIMIT 50").all(),
        db.prepare("SELECT (SELECT COUNT(*) FROM cat_greed_rounds) AS rounds,COALESCE((SELECT SUM(amount) FROM cat_greed_bets),0) AS wagered,COALESCE((SELECT SUM(amount) FROM cat_greed_payouts WHERE paid_at IS NOT NULL),0) AS paid,COALESCE((SELECT SUM(b.amount) FROM cat_greed_bets b INNER JOIN cat_greed_rounds r ON r.id=b.round_id WHERE r.phase='result'),0)-COALESCE((SELECT SUM(amount) FROM cat_greed_payouts WHERE paid_at IS NOT NULL),0) AS net,(SELECT COUNT(DISTINCT user_id) FROM cat_greed_bets) AS players").first()
      ]);
      const snapshot=makeSnapshot(settings,symbols);
      return json({settings,symbols,odds:calculateOdds(snapshot),maxExpectedReturnBp:maxExpectedReturnBp(snapshot),rounds:rounds.results??[],players:players.results??[],totals:totals??{}},200,origin,env);
    }
    if (playerControl && request.method==="PATCH") {
      if (admin.role!=="owner" && admin.role!=="admin") return wheelError("permission_denied",403,json,origin,env);
      const parsed = await readBoundedJson(request,2048);
      if (!parsed.ok) return wheelError(parsed.error,parsed.status,json,origin,env);
      const body = parsed.value;
      if(!body||typeof body!=="object"||Array.isArray(body)) return wheelError("invalid_player_control",400,json,origin,env);
      const hasEnabled=Object.prototype.hasOwnProperty.call(body,"enabled");
      const enabled=hasEnabled?(body.enabled===false?0:body.enabled===true?1:null):null;
      const hasLimit=body.maxBetPerRound!=null;
      const limit=hasLimit?Number(body.maxBetPerRound):null;
      if ((hasEnabled&&enabled===null)||(hasLimit&&(!Number.isSafeInteger(limit)||Number(limit)<10||Number(limit)>100000000))||(enabled===null&&limit===null)) return wheelError("invalid_player_control",400,json,origin,env);
      const userId=playerControl[1],now=isoNow();
      await db.prepare("INSERT INTO cat_greed_player_controls (user_id,enabled,max_bet_per_round,updated_by_admin_id,updated_at) VALUES (?,?,? ,?,?) ON CONFLICT(user_id) DO UPDATE SET enabled=COALESCE(?,enabled),max_bet_per_round=COALESCE(?,max_bet_per_round),updated_by_admin_id=excluded.updated_by_admin_id,updated_at=excluded.updated_at")
        .bind(userId,enabled??1,limit??1000000,admin.id,now,enabled,limit).run();
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,target_id,details_json,created_at) VALUES (?,?,?,?,?,?)")
        .bind(crypto.randomUUID(),admin.id,"player_control",userId,JSON.stringify({enabled,maxBetPerRound:limit}),now).run();
      return json({ok:true},200,origin,env);
    }
    if (adminSettings) {
      if (request.method==="GET") {
        const settings=await getSettings(db), snapshot=makeSnapshot(settings,await getSymbols(db));
        return json({settings,odds:calculateOdds(snapshot),maxExpectedReturnBp:maxExpectedReturnBp(snapshot)},200,origin,env);
      }
      if (request.method!=="PATCH") return wheelError("method_not_allowed",405,json,origin,env);
      if (admin.role!=="owner") return wheelError("owner_permission_required",403,json,origin,env);
      const parsed = await readBoundedJson(request,2048);
      if (!parsed.ok) return wheelError(parsed.error,parsed.status,json,origin,env);
      const body = parsed.value;
      const current=await getSettings(db);
      if (!body || typeof body!=="object" || Array.isArray(body)) return wheelError("invalid_settings",400,json,origin,env);
      const next={enabled:body.enabled==null?current.enabled:body.enabled===true?1:body.enabled===false?0:-1,betting:Number(body.bettingSeconds??current.betting_seconds),result:Number(body.resultSeconds??current.result_seconds),salad:Number(body.saladWeightBp??current.salad_weight_bp),pizza:Number(body.pizzaWeightBp??current.pizza_weight_bp)};
      if (![0,1].includes(next.enabled)||!Number.isInteger(next.betting)||next.betting<10||next.betting>120||!Number.isInteger(next.result)||next.result<5||next.result>30||!Number.isInteger(next.salad)||!Number.isInteger(next.pizza)||next.salad<0||next.pizza<0||next.salad+next.pizza>5000) return wheelError("invalid_settings",400,json,origin,env);
      const proposedSnapshot=makeSnapshot({...current,enabled:next.enabled,betting_seconds:next.betting,result_seconds:next.result,salad_weight_bp:next.salad,pizza_weight_bp:next.pizza},await getSymbols(db));
      const exposure=maxExpectedReturnBp(proposedSnapshot);
      if(next.enabled===1&&exposure>10000) return json({error:"payout_exposure_too_high",maxExpectedReturnBp:exposure,odds:calculateOdds(proposedSnapshot)},409,origin,env);
      const now=isoNow();
      await db.prepare("UPDATE cat_greed_settings SET enabled=?,betting_seconds=?,result_seconds=?,salad_weight_bp=?,pizza_weight_bp=?,updated_by_admin_id=?,updated_at=? WHERE id='current'").bind(next.enabled,next.betting,next.result,next.salad,next.pizza,admin.id,now).run();
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,details_json,created_at) VALUES (?,?,?,?,?)").bind(crypto.randomUUID(),admin.id,"settings_update",JSON.stringify(next),now).run();
      const saved=await getSettings(db), snapshot=makeSnapshot(saved,await getSymbols(db));
      return json({ok:true,settings:saved,odds:calculateOdds(snapshot),maxExpectedReturnBp:maxExpectedReturnBp(snapshot)},200,origin,env);
    }
    if (adminSymbols) {
      if (request.method==="GET") {
        const symbols=await getSymbols(db), settings=await getSettings(db), snapshot=makeSnapshot(settings,symbols);
        return json({symbols,odds:calculateOdds(snapshot),maxExpectedReturnBp:maxExpectedReturnBp(snapshot)},200,origin,env);
      }
      if (request.method!=="PATCH") return wheelError("method_not_allowed",405,json,origin,env);
      if (admin.role!=="owner") return wheelError("owner_permission_required",403,json,origin,env);
      const parsed = await readBoundedJson(request,16384);
      if (!parsed.ok) return wheelError(parsed.error,parsed.status,json,origin,env);
      const body = parsed.value;
      if (!body || typeof body!=="object" || Array.isArray(body) || !Array.isArray(body.symbols)||body.symbols.length!==8) return wheelError("invalid_symbols",400,json,origin,env);
      const now=isoNow(), statements:D1PreparedStatement[]=[], seenSlots=new Set<number>();
      let totalWeight=0;
      const proposed: FoodWheelSymbol[]=[];
      for (const item of body.symbols) {
        if (!item || typeof item!=="object") return wheelError("invalid_symbol",400,json,origin,env);
        const slot=Number(item.slot),multiplier=Number(item.multiplier),weight=Number(item.weight);
        const emoji=String(item.emoji??""),label=String(item.label??"").trim(),imageUrl=item.imageUrl==null?"":String(item.imageUrl).trim();
        if (!Number.isInteger(slot)||slot<0||slot>7||seenSlots.has(slot)||!Number.isInteger(multiplier)||multiplier<1||multiplier>100||!Number.isInteger(weight)||weight<0||weight>100000||!emoji.trim()||emoji.length>12||/[<>\u0000-\u001f]/.test(emoji)||!label||label.length>40||/[<>\u0000-\u001f]/.test(label)||(imageUrl&&!isValidImageKitUrl(imageUrl))||typeof item.isVegetable!=="boolean") return wheelError("invalid_symbol",400,json,origin,env);
        seenSlots.add(slot); totalWeight+=weight;
        proposed.push({slot,emoji,label,multiplier,is_vegetable:item.isVegetable?1:0,weight,image_url:imageUrl||null});
        statements.push(db.prepare("UPDATE cat_greed_symbols SET emoji=?,label=?,multiplier=?,is_vegetable=?,weight=?,image_url=?,updated_at=? WHERE slot=?").bind(emoji,label,multiplier,item.isVegetable?1:0,weight,imageUrl||null,now,slot));
      }
      if(seenSlots.size!==8||totalWeight<=0||proposed.some((symbol,index)=>symbol.slot!==index)) return wheelError("invalid_symbol_weights",400,json,origin,env);
      const settings=await getSettings(db);
      const proposedSnapshot=makeSnapshot(settings,proposed);
      const exposure=maxExpectedReturnBp(proposedSnapshot);
      if(settings.enabled===1&&exposure>10000) return json({error:"payout_exposure_too_high",maxExpectedReturnBp:exposure,odds:calculateOdds(proposedSnapshot)},409,origin,env);
      await db.batch(statements);
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,details_json,created_at) VALUES (?,?,?,?,?)").bind(crypto.randomUUID(),admin.id,"symbols_update",JSON.stringify({symbols:proposed.map(({slot,emoji,label,multiplier,is_vegetable,weight,image_url})=>({slot,emoji,label,multiplier,isVegetable:!!is_vegetable,weight,imageUrl:image_url}))}),now).run();
      const saved=await getSymbols(db), currentSettings=await getSettings(db), snapshot=makeSnapshot(currentSettings,saved);
      return json({ok:true,symbols:saved,odds:calculateOdds(snapshot),maxExpectedReturnBp:maxExpectedReturnBp(snapshot)},200,origin,env);
    }
    if (adminRounds) {
      await currentRound(db,false);
      const rounds=await db.prepare("SELECT r.id,r.phase,r.starts_at,r.closes_at,r.result_slot,r.special,r.seed_commitment,CASE WHEN r.phase='result' THEN r.server_seed ELSE NULL END AS revealed_seed,CASE WHEN r.phase='result' THEN r.config_snapshot ELSE NULL END AS config_snapshot,r.settled_at,COALESCE(b.wagered,0) AS wagered,COALESCE(b.players,0) AS players FROM cat_greed_rounds r LEFT JOIN (SELECT round_id,SUM(amount) AS wagered,COUNT(DISTINCT user_id) AS players FROM cat_greed_bets GROUP BY round_id) b ON b.round_id=r.id ORDER BY r.created_at DESC LIMIT 100").all();
      return json({rounds:rounds.results??[]},200,origin,env);
    }
    return null;
  } catch (error) {
    console.error("[food-wheel] request failed",error instanceof Error?error.message:"UnknownError");
    return wheelError("food_wheel_unavailable",500,json,origin,env);
  }
}
// Production deploy trigger: publish the restored pre-six-slot betting behavior.
