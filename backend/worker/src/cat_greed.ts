type CatGreedUser = { id: string };
type CatGreedAdmin = { id: string; username: string; role: string };
type CatGreedEnv = { DB?: D1Database };
type CatGreedJson = (data: unknown, status: number, origin?: string, env?: any) => Response;

type CatGreedSettings = {
  enabled: number;
  betting_seconds: number;
  result_seconds: number;
  salad_weight_bp: number;
  pizza_weight_bp: number;
};
type CatGreedSymbol = {
  slot: number; emoji: string; label: string; multiplier: number;
  is_vegetable: number; weight: number; image_url: string | null;
};
type CatGreedSnapshot = {
  bettingSeconds: number; resultSeconds: number; saladWeightBp: number; pizzaWeightBp: number;
  symbols: Array<{slot:number;emoji:string;label:string;multiplier:number;isVegetable:boolean;weight:number;imageUrl:string|null}>;
};

const BET_CHIPS = new Set([10, 500, 6000, 30000, 100000]);
const isoNow = () => new Date().toISOString();
const randomHex = (size = 32) => Array.from(crypto.getRandomValues(new Uint8Array(size))).map(x => x.toString(16).padStart(2, "0")).join("");
async function digestHex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes)).map(x => x.toString(16).padStart(2, "0")).join("");
}
async function getSettings(db: D1Database): Promise<CatGreedSettings> {
  await db.prepare("INSERT OR IGNORE INTO cat_greed_settings (id, updated_at) VALUES ('current', ?)").bind(isoNow()).run();
  return (await db.prepare("SELECT enabled, betting_seconds, result_seconds, salad_weight_bp, pizza_weight_bp FROM cat_greed_settings WHERE id='current'").first<CatGreedSettings>())!;
}
async function getSymbols(db: D1Database): Promise<CatGreedSymbol[]> {
  const rows = await db.prepare("SELECT slot, emoji, label, multiplier, is_vegetable, weight, image_url FROM cat_greed_symbols ORDER BY slot").all<CatGreedSymbol>();
  return rows.results ?? [];
}
function makeSnapshot(settings: CatGreedSettings, symbols: CatGreedSymbol[]): CatGreedSnapshot {
  return {
    bettingSeconds: settings.betting_seconds, resultSeconds: settings.result_seconds,
    saladWeightBp: settings.salad_weight_bp, pizzaWeightBp: settings.pizza_weight_bp,
    symbols: symbols.map(s => ({slot:s.slot,emoji:s.emoji,label:s.label,multiplier:s.multiplier,isVegetable:!!s.is_vegetable,weight:s.weight,imageUrl:s.image_url}))
  };
}
async function createRound(db: D1Database): Promise<any> {
  const settings = await getSettings(db);
  const symbols = await getSymbols(db);
  const snapshot = makeSnapshot(settings, symbols);
  const id = crypto.randomUUID();
  const seed = randomHex();
  const now = Date.now();
  const startsAt = new Date(now).toISOString();
  const closesAt = new Date(now + settings.betting_seconds * 1000).toISOString();
  await db.prepare(
    "INSERT INTO cat_greed_rounds (id, phase, starts_at, closes_at, server_seed, seed_commitment, config_snapshot, created_at) VALUES (?, 'betting', ?, ?, ?, ?, ?, ?)"
  ).bind(id, startsAt, closesAt, seed, await digestHex(seed), JSON.stringify(snapshot), startsAt).run();
  return db.prepare("SELECT * FROM cat_greed_rounds WHERE id=?").bind(id).first();
}
async function unitRandom(round: any): Promise<number> {
  const hex = await digestHex(round.server_seed + "|" + round.id + "|" + round.config_snapshot);
  return parseInt(hex.slice(0, 13), 16) / Math.pow(16, 13);
}
async function chooseOutcome(round: any): Promise<{slot:number|null;special:string|null}> {
  const config = JSON.parse(round.config_snapshot) as CatGreedSnapshot;
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
  const config = JSON.parse(round.config_snapshot) as CatGreedSnapshot;
  const bets = await db.prepare("SELECT user_id, slot, SUM(amount) AS amount FROM cat_greed_bets WHERE round_id=? GROUP BY user_id, slot").bind(round.id).all<{user_id:string;slot:number;amount:number}>();
  const totals = new Map<string, number>();
  for (const bet of bets.results ?? []) {
    const symbol = config.symbols.find(s => s.slot === bet.slot);
    if (!symbol) continue;
    const wins = round.special === "salad" ? symbol.isVegetable : round.special === "pizza" ? !symbol.isVegetable : round.result_slot === bet.slot;
    if (wins) totals.set(bet.user_id, (totals.get(bet.user_id) ?? 0) + bet.amount * symbol.multiplier);
  }
  const now = isoNow();
  const statements: D1PreparedStatement[] = [];
  for (const [userId, amount] of totals) {
    if (!Number.isSafeInteger(amount) || amount <= 0) continue;
    const transactionId = crypto.randomUUID();
    statements.push(
      db.prepare("INSERT OR IGNORE INTO cat_greed_payouts (round_id,user_id,amount,created_at,transaction_id) VALUES (?,?,?,?,?)").bind(round.id,userId,amount,now,transactionId),
      db.prepare("UPDATE user_wallets SET balance=balance+?, updated_at=? WHERE user_id=? AND EXISTS (SELECT 1 FROM cat_greed_payouts WHERE round_id=? AND user_id=? AND paid_at IS NULL)").bind(amount,now,userId,round.id,userId),
      db.prepare("INSERT INTO cat_greed_ledger (id,user_id,round_id,amount,balance_after,transaction_type,description,created_at) SELECT ?,user_id,?,?,balance,'payout','جائزة قط الجشع',? FROM user_wallets WHERE user_id=? AND changes()=1").bind(transactionId,round.id,amount,now,userId),
      db.prepare("UPDATE cat_greed_payouts SET paid_at=?, transaction_id=? WHERE round_id=? AND user_id=? AND paid_at IS NULL AND EXISTS (SELECT 1 FROM cat_greed_ledger WHERE id=?)").bind(now,transactionId,round.id,userId,transactionId)
    );
  }
  if (statements.length) await db.batch(statements);
}
async function settleRound(db: D1Database, round: any): Promise<any> {
  if (round.phase === "betting" && Date.parse(round.closes_at) <= Date.now()) {
    const outcome = await chooseOutcome(round);
    await db.prepare("UPDATE cat_greed_rounds SET phase='result', result_slot=?, special=?, settled_at=? WHERE id=? AND phase='betting' AND closes_at<=?")
      .bind(outcome.slot,outcome.special,isoNow(),round.id,isoNow()).run();
  }
  const settled = await db.prepare("SELECT * FROM cat_greed_rounds WHERE id=?").bind(round.id).first();
  if (settled?.phase === "result") await payRound(db, settled);
  return settled;
}
async function currentRound(db: D1Database): Promise<any> {
  let round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first();
  if (!round) {
    try { round = await createRound(db); }
    catch { round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first(); }
  }
  if (round?.phase === "betting" && Date.parse(round.closes_at) <= Date.now()) round = await settleRound(db, round);
  if (round?.phase === "result" && Date.now() - Date.parse(round.settled_at ?? round.created_at) >= JSON.parse(round.config_snapshot).resultSeconds * 1000) {
    try { round = await createRound(db); }
    catch { round = await db.prepare("SELECT * FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 1").first(); }
  }
  return round;
}
function wheelError(message: string, status: number, json: CatGreedJson, origin?: string, env?: unknown) {
  return json({error:message},status,origin,env);
}
export async function handleCatGreedRequest(
  request: Request, env: CatGreedEnv, origin: string | undefined,
  authenticateUser: (request:Request,db:D1Database)=>Promise<CatGreedUser|null>,
  authenticateAdmin: (request:Request,db:D1Database)=>Promise<CatGreedAdmin|null>,
  json: CatGreedJson
): Promise<Response|null> {
  const path = new URL(request.url).pathname;
  const publicState = path === "/api/v1/games/cat-greed/state" && request.method === "GET";
  const publicBet = path === "/api/v1/games/cat-greed/bet" && request.method === "POST";
  const mainOverview = path === "/api/v1/admin/games/cat-greed/overview" && request.method === "GET";
  const playerControl = path.match(/^\/api\/v1\/admin\/games\/cat-greed\/players\/([0-9a-f-]{36})$/i);
  const adminSettings = path === "/api/v1/admin/cat-greed/settings";
  const adminSymbols = path === "/api/v1/admin/cat-greed/symbols";
  const adminRounds = path === "/api/v1/admin/cat-greed/rounds" && request.method === "GET";
  if (!publicState && !publicBet && !mainOverview && !playerControl && !adminSettings && !adminSymbols && !adminRounds) return null;
  if (!env.DB) return wheelError("database_unavailable",503,json,origin,env);
  const db = env.DB;
  try {
    if (publicState || publicBet) {
      const user = await authenticateUser(request,db);
      if (!user) return wheelError("authentication_required",401,json,origin,env);
      const settings = await getSettings(db);
      if (!settings.enabled) return json({enabled:false,error:"game_disabled"},423,origin,env);
      let round = await currentRound(db);
      if (publicBet) {
        let body: any;
        try { body = await request.json(); } catch { return wheelError("invalid_json",400,json,origin,env); }
        const slot = Number(body.slot), amount = Number(body.amount), roundId = String(body.roundId ?? "");
        if (!Number.isInteger(slot) || slot<0 || slot>7 || !BET_CHIPS.has(amount)) return wheelError("invalid_bet",400,json,origin,env);
        if (!round || round.id !== roundId || round.phase !== "betting" || Date.parse(round.closes_at)<=Date.now()) return wheelError("round_closed",409,json,origin,env);
        await db.prepare("INSERT OR IGNORE INTO user_wallets (user_id,balance,updated_at) VALUES (?,0,?)").bind(user.id,isoNow()).run();
        const control = await db.prepare("SELECT enabled,max_bet_per_round FROM cat_greed_player_controls WHERE user_id=?").bind(user.id).first<{enabled:number;max_bet_per_round:number}>();
        if (control?.enabled===0) return wheelError("player_disabled",403,json,origin,env);
        const currentTotal = await db.prepare("SELECT COALESCE(SUM(amount),0) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=?").bind(roundId,user.id).first<{total:number}>();
        const limit = control?.max_bet_per_round ?? 1000000;
        if ((currentTotal?.total ?? 0) + amount > limit) return wheelError("bet_limit_exceeded",400,json,origin,env);
        const now=isoNow(), transactionId=crypto.randomUUID(), betId=crypto.randomUUID();
        await db.batch([
          db.prepare("UPDATE user_wallets SET balance=balance-?,updated_at=? WHERE user_id=? AND balance>=? AND EXISTS (SELECT 1 FROM cat_greed_rounds WHERE id=? AND phase='betting' AND closes_at>?)").bind(amount,now,user.id,amount,roundId,now),
          db.prepare("INSERT INTO cat_greed_ledger (id,user_id,round_id,amount,balance_after,transaction_type,description,created_at) SELECT ?,user_id,?,?,balance,'bet','رهان قط الجشع',? FROM user_wallets WHERE user_id=? AND changes()=1").bind(transactionId,roundId,-amount,now,user.id),
          db.prepare("INSERT INTO cat_greed_bets (id,round_id,user_id,slot,amount,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM cat_greed_ledger WHERE id=?)").bind(betId,roundId,user.id,slot,amount,now,transactionId)
        ]);
        const placed = await db.prepare("SELECT id FROM cat_greed_bets WHERE id=?").bind(betId).first();
        if (!placed) {
          const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=?").bind(user.id).first<{balance:number}>();
          return wheelError((wallet?.balance ?? 0)<amount ? "insufficient_balance" : "round_closed",409,json,origin,env);
        }
        round = await currentRound(db);
      }
      const pools = await db.prepare("SELECT slot,SUM(amount) AS total FROM cat_greed_bets WHERE round_id=? GROUP BY slot").bind(round.id).all<{slot:number;total:number}>();
      const mine = await db.prepare("SELECT slot,SUM(amount) AS total FROM cat_greed_bets WHERE round_id=? AND user_id=? GROUP BY slot").bind(round.id,user.id).all<{slot:number;total:number}>();
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=?").bind(user.id).first<{balance:number}>();
      const payout = await db.prepare("SELECT amount FROM cat_greed_payouts WHERE round_id=? AND user_id=?").bind(round.id,user.id).first<{amount:number}>();
      const history = await db.prepare("SELECT result_slot,special FROM cat_greed_rounds WHERE phase='result' ORDER BY settled_at DESC LIMIT 9").all<{result_slot:number|null;special:string|null}>();
      const config = JSON.parse(round.config_snapshot) as CatGreedSnapshot;
      const isBetting=round.phase==="betting";
      return json({
        enabled:true,roundId:round.id,secondsLeft:Math.max(0,Math.ceil((Date.parse(isBetting?round.closes_at:new Date(Date.parse(round.settled_at)+config.resultSeconds*1000).toISOString())-Date.now())/1000)),
        phase:round.phase,pools:Array.from({length:8},(_,i)=>pools.results?.find(x=>x.slot===i)?.total??0),
        myBets:Array.from({length:8},(_,i)=>mine.results?.find(x=>x.slot===i)?.total??0),
        balance:wallet?.balance??0,myPayout:payout?.amount??0,
        resultSlot:isBetting?null:round.result_slot,special:isBetting?null:round.special,
        seedCommitment:round.seed_commitment,revealedSeed:isBetting?null:round.server_seed,configSnapshot:isBetting?null:round.config_snapshot,
        symbols:config.symbols,history:(history.results??[]).map(x=>x.special==="salad"?"🥗":x.special==="pizza"?"🍕":config.symbols.find(s=>s.slot===x.result_slot)?.emoji??"—")
      },200,origin,env);
    }

    const admin = await authenticateAdmin(request,db);
    if (!admin) return wheelError("authentication_required",401,json,origin,env);
    if (mainOverview) {
      const [settings,symbols,rounds,players,totals] = await Promise.all([
        getSettings(db),getSymbols(db),
        db.prepare("SELECT id,phase,starts_at,closes_at,result_slot,special,seed_commitment,settled_at FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 20").all(),
        db.prepare("SELECT u.id,p.display_name AS name,p.gabo_id AS userCode,COALESCE(c.enabled,1) AS enabled,COALESCE(c.max_bet_per_round,1000000) AS maxBetPerRound,COALESCE(b.rounds,0) AS rounds,COALESCE(b.wagered,0) AS wagered,COALESCE(py.paid,0) AS paid FROM users u LEFT JOIN profiles p ON p.user_id=u.id LEFT JOIN cat_greed_player_controls c ON c.user_id=u.id LEFT JOIN (SELECT user_id,COUNT(DISTINCT round_id) AS rounds,SUM(amount) AS wagered FROM cat_greed_bets GROUP BY user_id) b ON b.user_id=u.id LEFT JOIN (SELECT user_id,SUM(amount) AS paid FROM cat_greed_payouts WHERE paid_at IS NOT NULL GROUP BY user_id) py ON py.user_id=u.id WHERE b.user_id IS NOT NULL ORDER BY wagered DESC LIMIT 50").all(),
        db.prepare("SELECT COUNT(*) AS rounds,COALESCE(SUM(amount),0) AS wagered FROM cat_greed_bets").first()
      ]);
      return json({settings,symbols,rounds:rounds.results??[],players:players.results??[],totals:totals??{}},200,origin,env);
    }
    if (playerControl && request.method==="PATCH") {
      if (admin.role!=="owner" && admin.role!=="admin") return wheelError("permission_denied",403,json,origin,env);
      let body:any; try { body=await request.json(); } catch { return wheelError("invalid_json",400,json,origin,env); }
      const enabled=body.enabled===false?0:body.enabled===true?1:null;
      const limit=body.maxBetPerRound==null?null:Number(body.maxBetPerRound);
      if (enabled===null && (limit===null || !Number.isSafeInteger(limit) || limit<10 || limit>100000000)) return wheelError("invalid_player_control",400,json,origin,env);
      const userId=playerControl[1],now=isoNow();
      await db.prepare("INSERT INTO cat_greed_player_controls (user_id,enabled,max_bet_per_round,updated_by_admin_id,updated_at) VALUES (?,?,? ,?,?) ON CONFLICT(user_id) DO UPDATE SET enabled=COALESCE(?,enabled),max_bet_per_round=COALESCE(?,max_bet_per_round),updated_by_admin_id=excluded.updated_by_admin_id,updated_at=excluded.updated_at")
        .bind(userId,enabled??1,limit??1000000,admin.id,now,enabled,limit).run();
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,target_id,details_json,created_at) VALUES (?,?,?,?,?,?)")
        .bind(crypto.randomUUID(),admin.id,"player_control",userId,JSON.stringify({enabled,maxBetPerRound:limit}),now).run();
      return json({ok:true},200,origin,env);
    }
    if (adminSettings) {
      if (request.method==="GET") return json({settings:await getSettings(db)},200,origin,env);
      if (request.method!=="PATCH") return wheelError("method_not_allowed",405,json,origin,env);
      if (admin.role!=="owner") return wheelError("owner_permission_required",403,json,origin,env);
      let body:any; try { body=await request.json(); } catch { return wheelError("invalid_json",400,json,origin,env); }
      const current=await getSettings(db);
      const next={enabled:body.enabled==null?current.enabled:body.enabled?1:0,betting:Number(body.bettingSeconds??current.betting_seconds),result:Number(body.resultSeconds??current.result_seconds),salad:Number(body.saladWeightBp??current.salad_weight_bp),pizza:Number(body.pizzaWeightBp??current.pizza_weight_bp)};
      if (!Number.isInteger(next.betting)||next.betting<10||next.betting>120||!Number.isInteger(next.result)||next.result<5||next.result>30||!Number.isInteger(next.salad)||!Number.isInteger(next.pizza)||next.salad<0||next.pizza<0||next.salad+next.pizza>5000) return wheelError("invalid_settings",400,json,origin,env);
      const now=isoNow();
      await db.prepare("UPDATE cat_greed_settings SET enabled=?,betting_seconds=?,result_seconds=?,salad_weight_bp=?,pizza_weight_bp=?,updated_by_admin_id=?,updated_at=? WHERE id='current'").bind(next.enabled,next.betting,next.result,next.salad,next.pizza,admin.id,now).run();
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,details_json,created_at) VALUES (?,?,?,?,?)").bind(crypto.randomUUID(),admin.id,"settings_update",JSON.stringify(next),now).run();
      return json({ok:true,settings:await getSettings(db)},200,origin,env);
    }
    if (adminSymbols) {
      if (request.method==="GET") return json({symbols:await getSymbols(db)},200,origin,env);
      if (request.method!=="PATCH") return wheelError("method_not_allowed",405,json,origin,env);
      if (admin.role!=="owner") return wheelError("owner_permission_required",403,json,origin,env);
      let body:any; try { body=await request.json(); } catch { return wheelError("invalid_json",400,json,origin,env); }
      if (!Array.isArray(body.symbols)||body.symbols.length!==8) return wheelError("invalid_symbols",400,json,origin,env);
      const now=isoNow(), statements:D1PreparedStatement[]=[];
      for (const item of body.symbols) {
        const slot=Number(item.slot),multiplier=Number(item.multiplier),weight=Number(item.weight);
        const emoji=String(item.emoji??""),label=String(item.label??"").trim(),imageUrl=item.imageUrl==null?"":String(item.imageUrl).trim();
        if (!Number.isInteger(slot)||slot<0||slot>7||!Number.isInteger(multiplier)||multiplier<1||multiplier>100||!Number.isInteger(weight)||weight<0||weight>100000||!emoji||emoji.length>12||!label||label.length>40||(imageUrl&&!/^https:\/\//i.test(imageUrl))) return wheelError("invalid_symbol",400,json,origin,env);
        statements.push(db.prepare("UPDATE cat_greed_symbols SET emoji=?,label=?,multiplier=?,is_vegetable=?,weight=?,image_url=?,updated_at=? WHERE slot=?").bind(emoji,label,multiplier,item.isVegetable?1:0,weight,imageUrl||null,now,slot));
      }
      await db.batch(statements);
      await db.prepare("INSERT INTO cat_greed_admin_audit (id,admin_id,action,details_json,created_at) VALUES (?,?,?,?,?)").bind(crypto.randomUUID(),admin.id,"symbols_update",JSON.stringify({count:8}),now).run();
      return json({ok:true,symbols:await getSymbols(db)},200,origin,env);
    }
    if (adminRounds) {
      const rounds=await db.prepare("SELECT id,phase,starts_at,closes_at,result_slot,special,seed_commitment,CASE WHEN phase='result' THEN server_seed ELSE NULL END AS revealed_seed,settled_at FROM cat_greed_rounds ORDER BY created_at DESC LIMIT 100").all();
      return json({rounds:rounds.results??[]},200,origin,env);
    }
    return null;
  } catch (error) {
    console.error("[cat-greed] request failed",error instanceof Error?error.message:"UnknownError");
    return wheelError("cat_greed_unavailable",500,json,origin,env);
  }
}
