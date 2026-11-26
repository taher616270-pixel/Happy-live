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

function field(body: Record<string,unknown>, key: string): string {
  const value=body[key];
  return value === undefined || value === null ? "" : String(value);
}
function validAmount(value: string): number | null {
  if (!/^(0|[1-9]\\d*)$/.test(value)) return null;
  const amount=Number(value);
  return Number.isSafeInteger(amount) && amount <= 2_000_000_000 ? amount : null;
}

/**
 * Happy Food Wheel uses one app-scoped server credential for both project
 * verification and runtime callbacks. UID is checked against an active account;
 * temporary UTD test sessions are not accepted or created.
 */
async function handleHappyFoodWheelHandshake(
  request: Request, db: D1Database | undefined, reply: JsonReply
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/v1/platform/handshake") return null;
  if (request.method === "GET" || request.method === "HEAD") {
    const health = reply({ ok: true, service: "happy-live-api", integration: "happy-food-wheel", endpoint: "/v1/platform/handshake" }, 200);
    // HEAD is a bodyless health probe; preserve the same status and headers as GET.
    return request.method === "HEAD"
      ? new Response(null, { status: health.status, statusText: health.statusText, headers: health.headers })
      : health;
  }
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
      const saved = await db.prepare(
        "SELECT setting_value FROM platform_settings WHERE setting_key='happy_food_wheel_token_hash' LIMIT 1"
      ).first<{ setting_value: string }>();
      if (!player || !saved?.setting_value || !constantTimeEqual(await sha256(suppliedToken), saved.setting_value)) {
        return reply({ error: "test_player_or_application_authentication_failed" }, 401);
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
      "SELECT user_id,game_id,round_id,delta,applied FROM platform_game_callback_orders WHERE order_id=? LIMIT 1"
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
        "INSERT OR IGNORE INTO platform_game_callback_orders(order_id,user_id,game_id,round_id,delta,claim_id,applied,created_at) " +
        "SELECT ?,?,?,?,?,?,0,? WHERE EXISTS(SELECT 1 FROM user_wallets WHERE user_id=? AND balance+?>=0)"
      ).bind(scopedOrderId,user.id,scopedGameId,roundId,delta,claimId,now,user.id,delta),
      db.prepare(
        "UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND changes()=1 " +
        "AND EXISTS(SELECT 1 FROM platform_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0)"
      ).bind(delta,now,user.id,scopedOrderId,claimId),
      db.prepare(
        "UPDATE platform_game_callback_orders SET applied=1 WHERE order_id=? AND claim_id=? AND applied=0 AND changes()=1"
      ).bind(scopedOrderId,claimId),
      db.prepare("DELETE FROM platform_game_callback_orders WHERE order_id=? AND claim_id=? AND applied=0").bind(scopedOrderId,claimId)
    ]);
    const applied = await db.prepare(
      "SELECT user_id,game_id,round_id,delta,applied FROM platform_game_callback_orders WHERE order_id=? LIMIT 1"
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
  request: Request, db: D1Database | undefined, _appKey: string | undefined, reply: JsonReply
): Promise<Response | null> {
  const foodWheelWallet=await handleHappyFoodWheelWalletCallback(request,db,reply);
  if (foodWheelWallet) return foodWheelWallet;
  return handleHappyFoodWheelHandshake(request,db,reply);
}
