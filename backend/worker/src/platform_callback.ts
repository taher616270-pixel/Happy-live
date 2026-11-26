type JsonReply = (data: unknown, status?: number) => Response;

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

async function sha256(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function validUtdPlayerToken(db: D1Database, userId: string, token: string): Promise<boolean> {
  const tokenHash = await sha256(token);
  const session = await db.prepare(
    "SELECT id FROM user_sessions WHERE user_id=? AND token_hash=? AND revoked_at IS NULL AND expires_at>? LIMIT 1"
  ).bind(userId, tokenHash, new Date().toISOString()).first<{id:string}>();
  if (session) return true;

  // Temporary UTD-only test tokens are never accepted by normal Happy Live APIs.
  const saved = await db.prepare(
    "SELECT setting_value FROM platform_settings WHERE setting_key='utd_test_session' LIMIT 1"
  ).first<{setting_value:string}>();
  if (!saved?.setting_value) return false;
  try {
    const test = JSON.parse(saved.setting_value) as { user_id?: string; token_hash?: string; expires_at?: string };
    return test.user_id === userId &&
      typeof test.token_hash === "string" && constantTimeEqual(test.token_hash, tokenHash) &&
      typeof test.expires_at === "string" && test.expires_at > new Date().toISOString();
  } catch { return false; }
}

function md5(value: string): string {
  const bytes = new TextEncoder().encode(value);
  const bitLength = bytes.length * 8;
  const paddedLength = (((bytes.length + 8) >>> 6) + 1) * 64;
  const data = new Uint8Array(paddedLength);
  data.set(bytes);
  data[bytes.length] = 0x80;
  const view = new DataView(data.buffer);
  view.setUint32(paddedLength - 8, bitLength >>> 0, true);
  view.setUint32(paddedLength - 4, Math.floor(bitLength / 0x100000000), true);
  const shifts = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
  const constants = Array.from({length:64}, (_,k) => Math.floor(Math.abs(Math.sin(k+1))*0x100000000) >>> 0);
  let a0=0x67452301, b0=0xefcdab89, c0=0x98badcfe, d0=0x10325476;
  for(let offset=0; offset<data.length; offset+=64) {
    const words = Array.from({length:16},(_,k)=>view.getUint32(offset+k*4,true));
    let a=a0,b=b0,c=c0,d=d0;
    for(let k=0;k<64;k++) {
      let f=0,g=0;
      if(k<16){f=(b&c)|(~b&d);g=k;}
      else if(k<32){f=(d&b)|(~d&c);g=(5*k+1)%16;}
      else if(k<48){f=b^c^d;g=(3*k+5)%16;}
      else {f=c^(b|~d);g=(7*k)%16;}
      const sum=(a+f+constants[k]+words[g])|0;
      const rotated=(sum<<shifts[k])|(sum>>>(32-shifts[k]));
      const next=(b+rotated)|0;
      a=d;d=c;c=b;b=next;
    }
    a0=(a0+a)|0;b0=(b0+b)|0;c0=(c0+c)|0;d0=(d0+d)|0;
  }
  return [a0,b0,c0,d0].map(n=>[0,8,16,24].map(s=>((n>>>s)&255).toString(16).padStart(2,"0")).join("")).join("");
}

function utdReply(data: unknown, reply: JsonReply): Response {
  return reply(data, 200);
}
function utdOk(data: Record<string, unknown>, reply: JsonReply): Response {
  return utdReply({ errorCode: 0, errorMsg: "success", data }, reply);
}
function utdFail(code: number, message: string, reply: JsonReply): Response {
  return utdReply({ errorCode: code, errorMsg: message, data: [] }, reply);
}

type UtdUser = {
  id: string; status: string; display_name: string | null; avatar_key: string | null;
  happy_id: string | null; balance: number;
};

async function readUtdPayload(request: Request): Promise<Record<string, unknown>> {
  if (request.method === "GET") {
    const values: Record<string, unknown> = {};
    new URL(request.url).searchParams.forEach((value,key)=>{values[key]=value;});
    return values;
  }
  try {
    const value = await request.json();
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string,unknown> : {};
  } catch { return {}; }
}

function field(body: Record<string,unknown>, key: string): string {
  const value=body[key];
  return value === undefined || value === null ? "" : String(value);
}
function validAmount(value: string): number | null {
  if (!/^(0|[1-9]\d*)$/.test(value)) return null;
  const amount=Number(value);
  return Number.isSafeInteger(amount) && amount <= 2_000_000_000 ? amount : null;
}

/**
 * UTD callbacks. UTD signs the exact concatenation of fields (no separators)
 * followed by UTD_APP_KEY. Player tokens are app session tokens and are
 * independently checked against user_sessions; a valid signature alone is
 * never accepted as player authentication.
 */
async function handleUtdCallback(
  request: Request, db: D1Database | undefined, appKey: string | undefined, reply: JsonReply
): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  const routes = new Set([
    "/api/leader-cc-game/get-user-info",
    "/api/leader-cc-game/change-balance",
    "/api/leader-cc-game/make-up-orders"
  ]);
  if (!routes.has(path)) return null;
  if (request.method !== "GET" && request.method !== "POST") {
    return utdFail(4005, "invalid request method", reply);
  }
  if (!appKey) return utdFail(4005, "UTD callback signing key is not configured", reply);
  if (!db) return utdFail(4005, "database unavailable", reply);

  const body = await readUtdPayload(request);
  const sign = field(body,"sign").toLowerCase();
  const signingFields = path.endsWith("/get-user-info")
    ? ["gameId","uid","token","roomId"]
    : path.endsWith("/change-balance")
      ? ["orderId","gameId","roundId","uid","coin","type","rewardType","token","winId","roomId"]
      : ["orderId","gameId","roundId","uid","coin","rewardType","winId","roomId"];
  const expected = md5(signingFields.map(key=>field(body,key)).join("")+appKey);
  if (!/^[a-f0-9]{32}$/.test(sign) || !constantTimeEqual(expected,sign)) {
    return utdFail(10004,"Verify signature fail",reply);
  }

  const uid=field(body,"uid");
  if (!uid || uid.length>128) return utdFail(10003,"user not found",reply);
  try {
    const user = await db.prepare(
      "SELECT u.id, u.status, p.display_name, p.avatar_key, p.happy_id, COALESCE(w.balance, 0) AS balance " +
      "FROM users u LEFT JOIN profiles p ON p.user_id=u.id LEFT JOIN user_wallets w ON w.user_id=u.id " +
      "WHERE p.happy_id=? OR u.id=? LIMIT 1"
    ).bind(uid,uid).first<UtdUser>();
    if (!user || user.status !== "active") {
      return utdFail(user ? 30001 : 10003, user ? "games disabled for this player" : "user not found", reply);
    }

    if (path.endsWith("/get-user-info")) {
      const token=field(body,"token");
      if (!token || token.length>4096) return utdFail(10003,"user not found",reply);
      if (!(await validUtdPlayerToken(db, user.id, token))) return utdFail(10003,"user not found",reply);
      return utdOk({
        uid, nickname:user.display_name?.trim() || "مستخدم", avatar:user.avatar_key || "",
        coin:Number(user.balance)||0, vipLevel:0, water:0
      },reply);
    }

    const orderId=field(body,"orderId");
    const amount=validAmount(field(body,"coin"));
    const gameId=field(body,"gameId");
    const roundId=field(body,"roundId");
    if (!orderId || orderId.length>160 || !gameId || !roundId || amount===null) {
      return utdFail(4005,"invalid callback parameters",reply);
    }

    if (path.endsWith("/change-balance")) {
      const token=field(body,"token");
      if (!token || token.length>4096) return utdFail(10003,"user not found",reply);
      if (!(await validUtdPlayerToken(db, user.id, token))) return utdFail(10003,"user not found",reply);
    }

    let delta=amount;
    if (path.endsWith("/change-balance")) {
      const type=field(body,"type");
      if (type!=="1" && type!=="2") return utdFail(4005,"invalid transaction type",reply);
      if (type==="1") delta=-amount;
    }
    // make-up-orders is always a credit and deliberately has no player token.
    const now=new Date().toISOString();
    await db.prepare("INSERT OR IGNORE INTO user_wallets (user_id,balance,updated_at) VALUES (?,0,?)").bind(user.id,now).run();

    const prior=await db.prepare(
      "SELECT user_id, applied FROM utd_game_callback_orders WHERE order_id=? LIMIT 1"
    ).bind(orderId).first<{user_id:string;applied:number}>();
    if (prior) {
      if (prior.user_id!==user.id || prior.applied!==1) return utdFail(4005,"order id conflict",reply);
      const current=await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1").bind(user.id).first<{balance:number}>();
      const balance=Number(current?.balance)||0;
      return utdOk({coins:balance,coin:balance},reply);
    }

    const claimId=crypto.randomUUID();
    // D1 batch is transactional. changes() gates the wallet update on a newly
    // inserted order, so concurrent retries cannot apply the same order twice.
    await db.batch([
      db.prepare(
        "INSERT OR IGNORE INTO utd_game_callback_orders (order_id,user_id,game_id,round_id,delta,claim_id,applied,created_at) " +
        "SELECT ?,?,?,?,?,?,0,? WHERE EXISTS (SELECT 1 FROM user_wallets WHERE user_id=? AND balance + ? >= 0)"
      ).bind(orderId,user.id,gameId,roundId,delta,claimId,now,user.id,delta),
      db.prepare(
        "UPDATE user_wallets SET balance=balance+?, updated_at=? WHERE user_id=? AND ?<>0 AND changes()=1 " +
        "AND EXISTS (SELECT 1 FROM utd_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0)"
      ).bind(delta,now,user.id,delta,orderId,claimId),
      db.prepare(
        "UPDATE utd_game_callback_orders SET applied=1 WHERE order_id=? AND claim_id=? AND applied=0 " +
        "AND (delta=0 OR changes()=1)"
      ).bind(orderId,claimId),
      db.prepare(
        "DELETE FROM utd_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0"
      ).bind(orderId,claimId)
    ]);

    const order=await db.prepare(
      "SELECT user_id,claim_id,applied FROM utd_game_callback_orders WHERE order_id=? LIMIT 1"
    ).bind(orderId).first<{user_id:string;claim_id:string;applied:number}>();
    if (order?.user_id===user.id && order.applied===1) {
      const current=await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1")
        .bind(user.id).first<{balance:number}>();
      const balance=Number(current?.balance)||0;
      return utdOk({coins:balance,coin:balance},reply);
    }
    if (order && order.user_id!==user.id) return utdFail(4005,"order id conflict",reply);
    const latest=await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1")
      .bind(user.id).first<{balance:number}>();
    if (delta<0 && Number(latest?.balance ?? 0)+delta<0) return utdFail(4004,"Insufficient game coins",reply);
    return utdFail(4005,"wallet settlement failed",reply);

  } catch (error) {
    console.error("[utd.callback] failed",error instanceof Error?error.message:"unknown");
    return utdFail(4005,"callback processing failed",reply);
  }
}

/**
 * Happy Food Wheel uses two distinct handshake credentials:
 * - Profile verification: the short-lived test-player token, paired with UID.
 * - Runtime integration: the long-lived app token, without UID.
 * The test-player token is accepted only for this one-time identity check.
 */
async function handleHappyFoodWheelHandshake(
  request: Request, db: D1Database | undefined, reply: JsonReply
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/v1/platform/handshake") return null;
  if (request.method === "GET") return reply({ success: true, message: "handshake endpoint ready" }, 200);
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  if (!db) return reply({ error: "database_unavailable" }, 503);

  const authorization = request.headers.get("Authorization") ?? "";
  const tokenMatch = authorization.match(/^Bearer\s+(\S{24,4096})$/i);
  if (!tokenMatch) return reply({ error: "authentication_required" }, 401);
  const suppliedToken = tokenMatch[1];
  if (!(request.headers.get("Content-Type") ?? "").toLowerCase().includes("application/json")) {
    return reply({ error: "application_json_required" }, 415);
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return reply({ error: "invalid_handshake_payload" }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch { return reply({ error: "invalid_handshake_payload" }, 400); }

  const appId = body.appId;
  const challenge = body.challenge;
  const uid = body.uid === undefined || body.uid === null ? "" : String(body.uid).trim();
  if (
    body.platform !== "Happy Food Wheel" ||
    typeof appId !== "string" || !/^app_[A-Za-z0-9_-]{8,128}$/.test(appId) ||
    body.apiVersion !== "v1" ||
    typeof challenge !== "string" || challenge.length < 16 || challenge.length > 256 ||
    uid.length > 128
  ) return reply({ error: "invalid_handshake_payload" }, 400);

  try {
    if (uid) {
      // Project-profile validation: authenticate the supplied test token
      // against this exact active Happy Live account. Do not bind the app ID
      // or grant runtime API access from a temporary test token.
      const player = await db.prepare(
        "SELECT u.id FROM users u LEFT JOIN profiles p ON p.user_id=u.id " +
        "WHERE (p.happy_id=? OR u.id=?) AND u.status='active' LIMIT 1"
      ).bind(uid, uid).first<{ id: string }>();
      if (!player || !(await validUtdPlayerToken(db, player.id, suppliedToken))) {
        return reply({ error: "test_player_authentication_failed" }, 401);
      }
      return reply({ ok: true, appId, apiVersion: "v1", uid, challenge }, 200);
    }

    // Runtime integration handshake: only the permanent app-issued token
    // can bind the platform app ID and authenticate future player/wallet calls.
    const saved = await db.prepare(
      "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_token_hash' LIMIT 1"
    ).first<{ setting_value: string }>();
    if (!saved?.setting_value) return reply({ error: "integration_not_configured" }, 503);
    if (!constantTimeEqual(await sha256(suppliedToken), saved.setting_value)) {
      return reply({ error: "invalid_application_token" }, 401);
    }

    const existing = await db.prepare(
      "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_app_id' LIMIT 1"
    ).first<{ setting_value: string }>();
    if (existing?.setting_value) {
      if (!constantTimeEqual(appId, existing.setting_value)) return reply({ error: "app_id_mismatch" }, 403);
    } else {
      const now = new Date().toISOString();
      await db.prepare(
        "INSERT INTO platform_settings (setting_key,setting_value,updated_at) " +
        "VALUES ('happy_food_wheel_app_id',?,?) ON CONFLICT(setting_key) DO NOTHING"
      ).bind(appId, now).run();
      const bound = await db.prepare(
        "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_app_id' LIMIT 1"
      ).first<{ setting_value: string }>();
      if (!bound?.setting_value || !constantTimeEqual(appId, bound.setting_value)) {
        return reply({ error: "app_id_mismatch" }, 403);
      }
    }
    return reply({ ok: true, appId, apiVersion: "v1", challenge }, 200);
  } catch {
    return reply({ error: "callback_validation_unavailable" }, 503);
  }
}

async function happyFoodWheelCredential(db: D1Database, request: Request, appId: string): Promise<boolean> {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(\S{24,4096})$/i);
  if (!match || !appId || !/^app_[A-Za-z0-9_-]{8,128}$/.test(appId)) return false;
  const saved = await db.prepare(
    "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_token_hash' LIMIT 1"
  ).first<{setting_value:string}>();
  const bound = await db.prepare(
    "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_app_id' LIMIT 1"
  ).first<{setting_value:string}>();
  return Boolean(saved?.setting_value && bound?.setting_value &&
    constantTimeEqual(await sha256(match[1]), saved.setting_value) &&
    constantTimeEqual(appId, bound.setting_value));
}

/**
 * Server-to-server player and wallet callbacks for the Happy Food Wheel
 * external game platform. The platform credential is app-scoped; every
 * balance mutation is idempotent and is applied to the canonical Happy Live
 * wallet, never to a client-supplied balance.
 */
async function handleHappyFoodWheelWalletCallback(
  request: Request, db: D1Database | undefined, reply: JsonReply
): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  const isPlayer = path === "/v1/platform/player";
  const isAdjust = path === "/v1/platform/wallet/adjust";
  if (!isPlayer && !isAdjust) return null;
  if (request.method !== "POST") return reply({error:"method_not_allowed"},405);
  if (!db) return reply({error:"database_unavailable"},503);
  let body: Record<string,unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return reply({error:"invalid_payload"},400);
    body = parsed as Record<string,unknown>;
  } catch { return reply({error:"invalid_payload"},400); }
  const appId = typeof body.appId === "string" ? body.appId : "";
  if (!(await happyFoodWheelCredential(db, request, appId))) return reply({error:"invalid_application_credential"},401);
  const uid = field(body,"uid");
  if (!uid || uid.length > 128) return reply({error:"invalid_uid"},400);
  try {
    const user = await db.prepare(
      "SELECT u.id,u.status,p.display_name,p.avatar_key,p.happy_id,COALESCE(w.balance,0) AS balance " +
      "FROM users u LEFT JOIN profiles p ON p.user_id=u.id LEFT JOIN user_wallets w ON w.user_id=u.id " +
      "WHERE p.happy_id=? OR u.id=? LIMIT 1"
    ).bind(uid,uid).first<{id:string;status:string;display_name:string|null;avatar_key:string|null;happy_id:string|null;balance:number}>();
    if (!user || user.status !== "active") return reply({error:"player_not_found_or_inactive"},404);
    if (isPlayer) {
      return reply({ok:true,appId,player:{uid:user.happy_id || uid,displayName:user.display_name?.trim() || "مستخدم",avatarUrl:user.avatar_key || ""},wallet:{balance:Number(user.balance)||0}},200);
    }

    const orderId = field(body,"orderId");
    const gameId = field(body,"gameId") || "food-wheel";
    const roundId = field(body,"roundId");
    const direction = field(body,"direction");
    const amount = validAmount(field(body,"amount"));
    if (!orderId || orderId.length > 160 || !roundId || roundId.length > 160 ||
        !["debit","credit"].includes(direction) || amount === null || amount <= 0) {
      return reply({error:"invalid_wallet_adjustment"},400);
    }
    const scopedOrderId = "hfw:" + appId + ":" + orderId;
    const scopedGameId = "happy-food-wheel:" + appId + ":" + gameId;
    const delta = direction === "debit" ? -amount : amount;
    const now = new Date().toISOString();
    await db.prepare("INSERT OR IGNORE INTO user_wallets(user_id,balance,updated_at) VALUES(?,0,?)").bind(user.id,now).run();
    const prior = await db.prepare(
      "SELECT user_id,game_id,round_id,delta,applied FROM utd_game_callback_orders WHERE order_id=? LIMIT 1"
    ).bind(scopedOrderId).first<{user_id:string;game_id:string;round_id:string;delta:number;applied:number}>();
    if (prior) {
      if (prior.user_id !== user.id || prior.game_id !== scopedGameId || prior.round_id !== roundId || prior.delta !== delta || prior.applied !== 1) {
        return reply({error:"idempotency_conflict"},409);
      }
      const current = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1").bind(user.id).first<{balance:number}>();
      return reply({ok:true,appId,uid,balance:Number(current?.balance)||0,replayed:true},200);
    }

    const claimId = crypto.randomUUID();
    await db.batch([
      db.prepare(
        "INSERT OR IGNORE INTO utd_game_callback_orders(order_id,user_id,game_id,round_id,delta,claim_id,applied,created_at) " +
        "SELECT ?,?,?,?,?,?,0,? WHERE EXISTS(SELECT 1 FROM user_wallets WHERE user_id=? AND balance+?>=0)"
      ).bind(scopedOrderId,user.id,scopedGameId,roundId,delta,claimId,now,user.id,delta),
      db.prepare(
        "UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND changes()=1 " +
        "AND EXISTS(SELECT 1 FROM utd_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0)"
      ).bind(delta,now,user.id,scopedOrderId,claimId),
      db.prepare(
        "UPDATE utd_game_callback_orders SET applied=1 WHERE order_id=? AND claim_id=? AND applied=0 AND changes()=1"
      ).bind(scopedOrderId,claimId),
      db.prepare("DELETE FROM utd_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0").bind(scopedOrderId,claimId)
    ]);
    const applied = await db.prepare(
      "SELECT user_id,game_id,round_id,delta,applied FROM utd_game_callback_orders WHERE order_id=? LIMIT 1"
    ).bind(scopedOrderId).first<{user_id:string;game_id:string;round_id:string;delta:number;applied:number}>();
    if (!applied || applied.user_id !== user.id || applied.game_id !== scopedGameId || applied.round_id !== roundId || applied.delta !== delta || applied.applied !== 1) {
      const latest = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1").bind(user.id).first<{balance:number}>();
      if (delta < 0 && Number(latest?.balance || 0) < amount) return reply({error:"insufficient_balance"},409);
      return reply({error:"wallet_settlement_failed"},409);
    }
    const current = await db.prepare("SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1").bind(user.id).first<{balance:number}>();
    return reply({ok:true,appId,uid,balance:Number(current?.balance)||0,replayed:false},200);
  } catch (error) {
    console.error("[happy-food-wheel.callback] failed",error instanceof Error?error.message:"unknown");
    return reply({error:"wallet_callback_failed"},500);
  }
}

export async function handlePlatformCallbackRequest(
  request: Request, db: D1Database | undefined, appKey: string | undefined, reply: JsonReply
): Promise<Response | null> {
  const utd=await handleUtdCallback(request,db,appKey,reply);
  if (utd) return utd;
  const foodWheelWallet=await handleHappyFoodWheelWalletCallback(request,db,reply);
  if (foodWheelWallet) return foodWheelWallet;
  return handleHappyFoodWheelHandshake(request,db,reply);
}
