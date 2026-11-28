import type { FoodWheelRoundsHub } from "./food_wheel_hub";

type GameApiUser = { id: string; session_id: string; display_name: string | null; happy_id: string | null };
type GameApiEnv = { DB?: D1Database; FOOD_WHEEL_ROUNDS?: DurableObjectNamespace<FoodWheelRoundsHub> };
type GameApiJson = (data: unknown, status?: number, origin?: string, env?: any) => Response;
const GAME_SESSION_TTL_SECONDS = 15 * 60;
const GAME_SESSION_RATE_WINDOW_SECONDS = 60;
const GAME_SESSION_RATE_MAX_REQUESTS = 120;
const GAME_PERMISSIONS = ["session.read", "profile.read", "wallet.read", "round.create", "round.read", "bets.place"] as const;

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function tokenValue(request: Request): string {
  const match = (request.headers.get("Authorization") ?? "").match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
  return match?.[1] ?? "";
}

async function readBody(request: Request, maxBytes = 2048): Promise<Record<string, unknown> | null> {
  const length = Number(request.headers.get("Content-Length") ?? 0);
  if (Number.isFinite(length) && length > maxBytes) return null;
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body) || new TextEncoder().encode(JSON.stringify(body)).length > maxBytes) return null;
    return body as Record<string, unknown>;
  } catch {
    return null;
  }
}

function isSafeGameUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    const hostname = parsed.hostname.toLowerCase();
    const labels = hostname.split(".");
    const isIpv4Literal = labels.length === 4 && labels.every((part) =>
      part.length > 0 && part.length <= 3 && [...part].every((char) => char >= "0" && char <= "9")
    );
    const blockedSuffix = [".localhost", ".local", ".internal", ".lan", ".home", ".test", ".invalid"];
    return parsed.protocol === "https:" &&
      parsed.username === "" && parsed.password === "" &&
      (parsed.port === "" || parsed.port === "443") &&
      !hostname.includes(":") && !isIpv4Literal &&
      hostname.includes(".") && !hostname.endsWith(".") &&
      hostname !== "localhost" &&
      !blockedSuffix.some((suffix) => hostname.endsWith(suffix));
  } catch {
    return false;
  }
}

async function gameOriginForId(db: D1Database, gameId: string): Promise<string | null> {
  const row = await db.prepare(
    "SELECT g.game_url AS gameUrl FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.id = ? AND g.enabled = 1 AND l.status = 'active' LIMIT 1"
  ).bind(gameId).first<{ gameUrl: string }>();
  if (!row?.gameUrl || row.gameUrl === "https://pending-game.happylive.invalid") return null;
  try {
    const parsed = new URL(row.gameUrl);
    if (!isSafeGameUrl(row.gameUrl)) return null;
    return parsed.origin;
  } catch {
    return null;
  }
}

function isAllowedSessionOrigin(registeredOrigin: string, requestOrigin: string): boolean {
  if (registeredOrigin === requestOrigin) return true;
  try {
    const registered = new URL(registeredOrigin);
    const requested = new URL(requestOrigin);
    return registered.protocol === "https:" &&
      registered.hostname === "happy-live.pages.dev" &&
      registered.port === "" &&
      requested.protocol === "https:" &&
      requested.port === "" &&
      requested.hostname.endsWith(".happy-live.pages.dev") &&
      requested.hostname !== "happy-live.pages.dev";
  } catch {
    return false;
  }
}

export async function isRegisteredGameOrigin(db: D1Database, origin: string): Promise<boolean> {
  try {
    const parsed = new URL(origin);
    if (parsed.protocol !== "https:" || parsed.origin !== origin) return false;
    const rows = await db.prepare(
      "SELECT g.game_url AS gameUrl FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.enabled = 1 AND l.status = 'active'"
    ).all<{ gameUrl: string }>();
    return (rows.results ?? []).some((row) => {
      return isSafeGameUrl(row.gameUrl) && new URL(row.gameUrl).origin === origin;
    });
  } catch {
    return false;
  }
}

function withGameCors(response: Response, origin: string | undefined, gameOrigin: string | null): Response {
  if (!origin || !gameOrigin || origin !== gameOrigin) return response;
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", origin);
  headers.set("vary", "Origin");
  headers.set("access-control-allow-headers", "Content-Type, Authorization");
  headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export async function handleGamesApiRequest(
  request: Request,
  env: GameApiEnv,
  origin: string | undefined,
  authenticateUser: (request: Request, db: D1Database) => Promise<GameApiUser | null>,
  json: GameApiJson,
  authenticateAdmin: (request: Request, db: D1Database) => Promise<{ id: string; username: string; role: string } | null>
): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  const foodWheelGameId = "4bcb9b74-3c87-4d9e-9f26-2b61c9a5f841";
  const isFoodWheelState = path === "/api/v1/game/food-wheel/state" && request.method === "GET";
  const isFoodWheelBet = path === "/api/v1/game/food-wheel/bet" && request.method === "POST";
  const isFoodWheelHistory = path === "/api/v1/game/food-wheel/history" && request.method === "GET";
  const isFoodWheelTopWins = path === "/api/v1/game/food-wheel/top-wins" && request.method === "GET";
  const isAuth = path === "/api/v1/game/auth" && request.method === "POST";
  const isSession = path === "/api/v1/game/session" && request.method === "GET";
  const isRefresh = path === "/api/v1/game/session/refresh" && request.method === "POST";
  const isRevoke = path === "/api/v1/game/session/revoke" && request.method === "POST";
  const isProfile = path === "/api/v1/game/profile" && request.method === "GET";
  const isWallet = path === "/api/v1/game/wallet" && request.method === "GET";
  const isCreateRound = path === "/api/v1/game/rounds" && request.method === "POST";
  const isListRounds = path === "/api/v1/game/rounds" && request.method === "GET";
  const placeBetMatch = path.match(/^\/api\/v1\/game\/rounds\/([0-9a-f-]{36})\/bets$/i);
  const getRoundMatch = path.match(/^\/api\/v1\/game\/rounds\/([0-9a-f-]{36})$/i);
  const serverSettleMatch = path.match(/^\/api\/v1\/game\/server\/rounds\/([0-9a-f-]{36})\/settle$/i);
  const serverCancelMatch = path.match(/^\/api\/v1\/game\/server\/rounds\/([0-9a-f-]{36})\/cancel$/i);
  const adminEconomyMatch = path.match(/^\/api\/v1\/admin\/games\/([0-9a-f-]{36})\/economy$/i);
  const adminKeyMatch = path.match(/^\/api\/v1\/admin\/games\/([0-9a-f-]{36})\/server-key$/i);
  const adminRoundsMatch = path.match(/^\/api\/v1\/admin\/games\/([0-9a-f-]{36})\/rounds$/i);
  if (!isFoodWheelState && !isFoodWheelBet && !isFoodWheelHistory && !isFoodWheelTopWins && !isAuth && !isSession && !isRefresh && !isRevoke && !isProfile && !isWallet &&
      !isCreateRound && !isListRounds && !(placeBetMatch && request.method === "POST") &&
      !(getRoundMatch && request.method === "GET") &&
      !(serverSettleMatch && request.method === "POST") && !(serverCancelMatch && request.method === "POST") &&
      !(adminEconomyMatch && ["GET", "PATCH"].includes(request.method)) &&
      !(adminKeyMatch && request.method === "POST") && !(adminRoundsMatch && request.method === "GET")) return null;
  const reply = (data: unknown, status = 200, _origin?: string, _env?: any) => origin
    ? withGameCors(json(data, status, undefined, env), origin, origin)
    : json(data, status, undefined, env);
  if (!env.DB) return reply({ error: "database_unavailable" }, 503, origin, env);
  const db = env.DB;
  try {
    if (adminEconomyMatch || adminKeyMatch || adminRoundsMatch) {
      const actor = await authenticateAdmin(request, db);
      if (!actor) return reply({ error: "authentication_required" }, 401, origin, env);
      if (actor.role !== "owner" && actor.role !== "admin") return reply({ error: "permission_denied" }, 403, origin, env);
      const gameId = (adminEconomyMatch ?? adminKeyMatch ?? adminRoundsMatch)![1];
      const game = await db.prepare("SELECT id FROM game_registry WHERE id = ? LIMIT 1").bind(gameId).first<{ id: string }>();
      if (!game) return reply({ error: "game_not_found" }, 404, origin, env);
      if (adminRoundsMatch && request.method === "GET") {
        const rows = await db.prepare(
          "SELECT r.id, COALESCE(p.happy_id, '') AS userCode, COALESCE(p.display_name, '') AS playerName, r.status, r.total_stake AS totalStake, r.total_payout AS totalPayout, r.result_json AS result, r.created_at AS createdAt, r.settled_at AS settledAt FROM game_rounds r LEFT JOIN profiles p ON p.user_id = r.user_id WHERE r.game_id = ? ORDER BY r.created_at DESC LIMIT 100"
        ).bind(gameId).all();
        return reply({ ok: true, rounds: rows.results ?? [] }, 200, origin, env);
      }
      if (adminEconomyMatch && request.method === "GET") {
        const settings = await db.prepare(
          "SELECT enabled, min_bet AS minBet, max_bet AS maxBet, max_bets_per_round AS maxBetsPerRound, max_total_bet AS maxTotalBet, max_payout_multiplier_bp AS maxPayoutMultiplierBp, updated_at AS updatedAt FROM game_economy_settings WHERE game_id = ? LIMIT 1"
        ).bind(gameId).first<Record<string, unknown>>();
        const key = await db.prepare("SELECT key_prefix AS keyPrefix, created_at AS createdAt, revoked_at AS revokedAt FROM game_server_keys WHERE game_id = ? LIMIT 1").bind(gameId).first<Record<string, unknown>>();
        return reply({ ok: true, settings: settings ?? { enabled: 0, minBet: 1, maxBet: 100000, maxBetsPerRound: 6, maxTotalBet: 600000, maxPayoutMultiplierBp: 100000 }, serverKey: key ?? null }, 200, origin, env);
      }
      if (adminEconomyMatch && request.method === "PATCH") {
        const body = await readBody(request);
        const enabled = body?.enabled;
        const minBet = body?.minBet, maxBet = body?.maxBet, maxBets = body?.maxBetsPerRound;
        const maxTotal = body?.maxTotalBet, maxMultiplier = body?.maxPayoutMultiplierBp;
        if (typeof enabled !== "boolean" || typeof minBet !== "number" || !Number.isSafeInteger(minBet) || typeof maxBet !== "number" || !Number.isSafeInteger(maxBet) ||
            typeof maxBets !== "number" || !Number.isSafeInteger(maxBets) || typeof maxTotal !== "number" || !Number.isSafeInteger(maxTotal) || typeof maxMultiplier !== "number" || !Number.isSafeInteger(maxMultiplier) ||
            Number(minBet) < 1 || Number(maxBet) < Number(minBet) || Number(maxBet) > 100000000 ||
            Number(maxBets) < 1 || Number(maxBets) > 100 || Number(maxTotal) < Number(maxBet) ||
            Number(maxTotal) > 1000000000 || Number(maxMultiplier) < 0 || Number(maxMultiplier) > 1000000) {
          return reply({ error: "invalid_game_economy_settings" }, 400, origin, env);
        }
        if (enabled) {
          const activeGame = await db.prepare("SELECT g.enabled, l.status FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.id = ? LIMIT 1").bind(gameId).first<{ enabled: number; status: string }>();
          const serverKey = await db.prepare("SELECT game_id FROM game_server_keys WHERE game_id = ? AND revoked_at IS NULL LIMIT 1").bind(gameId).first<{ game_id: string }>();
          if (!activeGame || activeGame.enabled !== 1 || activeGame.status !== "active") return reply({ error: "game_must_be_active_before_economy" }, 409, origin, env);
          if (!serverKey) return reply({ error: "game_server_key_required_before_economy" }, 409, origin, env);
        }
        const now = new Date().toISOString();
        await db.batch([
          db.prepare("INSERT INTO game_economy_settings (game_id, enabled, min_bet, max_bet, max_bets_per_round, max_total_bet, max_payout_multiplier_bp, updated_by_admin_id, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(game_id) DO UPDATE SET enabled = excluded.enabled, min_bet = excluded.min_bet, max_bet = excluded.max_bet, max_bets_per_round = excluded.max_bets_per_round, max_total_bet = excluded.max_total_bet, max_payout_multiplier_bp = excluded.max_payout_multiplier_bp, updated_by_admin_id = excluded.updated_by_admin_id, updated_at = excluded.updated_at").bind(gameId, enabled ? 1 : 0, minBet, maxBet, maxBets, maxTotal, maxMultiplier, actor.id, now),
          db.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'games.economy.update', 'game', ?, ?, ?)").bind(crypto.randomUUID(), gameId, JSON.stringify({ adminId: actor.id, adminUsername: actor.username, enabled, minBet, maxBet, maxBetsPerRound: maxBets, maxTotalBet: maxTotal, maxPayoutMultiplierBp: maxMultiplier }), now)
        ]);
        return reply({ ok: true }, 200, origin, env);
      }
      if (adminKeyMatch && request.method === "POST") {
        const serverKey = "hlgs_" + crypto.randomUUID() + "." + crypto.randomUUID();
        const now = new Date().toISOString();
        await db.batch([
          db.prepare("INSERT INTO game_server_keys (game_id, key_hash, key_prefix, created_at, rotated_at, revoked_at) VALUES (?, ?, ?, ?, ?, NULL) ON CONFLICT(game_id) DO UPDATE SET key_hash = excluded.key_hash, key_prefix = excluded.key_prefix, created_at = excluded.created_at, rotated_at = excluded.rotated_at, revoked_at = NULL").bind(gameId, await sha256(serverKey), serverKey.slice(0, 12), now, now),
          db.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'games.server_key.rotate', 'game', ?, ?, ?)").bind(crypto.randomUUID(), gameId, JSON.stringify({ adminId: actor.id, adminUsername: actor.username, keyPrefix: serverKey.slice(0, 12) }), now)
        ]);
        return reply({ ok: true, serverKey, warning: "احفظ المفتاح الآن؛ لن يمكن عرضه مرة أخرى." }, 201, origin, env);
      }
    }

    if (serverCancelMatch && request.method === "POST") {
      if (origin) return reply({ error: "server_to_server_only" }, 403, origin, env);
      const rawKey = request.headers.get("X-Happy-Live-Game-Key") ?? "";
      if (rawKey.length < 32 || rawKey.length > 512) return reply({ error: "game_server_key_required" }, 401, origin, env);
      const key = await db.prepare("SELECT game_id AS gameId FROM game_server_keys WHERE key_hash = ? AND revoked_at IS NULL LIMIT 1").bind(await sha256(rawKey)).first<{ gameId: string }>();
      if (!key) return reply({ error: "game_server_key_invalid" }, 401, origin, env);
      const roundId = serverCancelMatch[1];
      const round = await db.prepare("SELECT id, game_id AS gameId, user_id AS userId, status, total_stake AS totalStake FROM game_rounds WHERE id = ? AND game_id = ? LIMIT 1").bind(roundId, key.gameId).first<{ id: string; gameId: string; userId: string; status: string; totalStake: number }>();
      if (!round) return reply({ error: "game_round_not_found" }, 404, origin, env);
      if (round.status !== "open") return reply({ error: "game_round_already_settled" }, 409, origin, env);
      const bets = await db.prepare("SELECT id, stake FROM game_bets WHERE round_id = ? AND status = 'accepted' ORDER BY created_at, id").bind(roundId).all<{ id: string; stake: number }>();
      const betRows = bets.results ?? [];
      const refundAmount = betRows.reduce((sum, bet) => sum + bet.stake, 0);
      if (refundAmount !== round.totalStake) return reply({ error: "game_round_ledger_mismatch" }, 409, origin, env);
      const now = new Date().toISOString(), settlementId = crypto.randomUUID();
      const statements = [
        db.prepare("UPDATE game_rounds SET status = 'settling', total_payout = 0, result_json = ?, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND total_stake = ? AND (SELECT COALESCE(SUM(stake), 0) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (SELECT COUNT(*) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (? = 0 OR EXISTS (SELECT 1 FROM user_wallets WHERE user_id = ?))").bind(JSON.stringify({ cancelled: true }), now, settlementId, roundId, round.totalStake, roundId, refundAmount, roundId, betRows.length, refundAmount, round.userId),
        ...betRows.map(b => db.prepare("UPDATE game_bets SET status = 'cancelled', payout = 0, settled_at = ? WHERE id = ? AND round_id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(now, b.id, roundId, roundId, settlementId))
      ];
      if (refundAmount > 0) {
        statements.push(db.prepare("UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(refundAmount, now, round.userId, roundId, settlementId));
        statements.push(db.prepare("INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, NULL, ?, 'refund_credit', ?, w.balance, ?, ? FROM user_wallets w WHERE w.user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(crypto.randomUUID(), key.gameId, roundId, round.userId, refundAmount, "refund:" + roundId, now, round.userId, roundId, settlementId));
      }
      statements.push(db.prepare("UPDATE game_rounds SET status = 'cancelled' WHERE id = ? AND status = 'settling' AND settlement_id = ?").bind(roundId, settlementId));
      await db.batch(statements);
      const cancelled = await db.prepare("SELECT status FROM game_rounds WHERE id = ? LIMIT 1").bind(roundId).first<{ status: string }>();
      if (cancelled?.status !== "cancelled") return reply({ error: "game_round_cancellation_conflict" }, 409, origin, env);
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(round.userId).first<{ balance: number }>();
      return reply({ ok: true, roundId, status: "cancelled", refunded: refundAmount, balance: wallet?.balance ?? 0 }, 200, origin, env);
    }

    if (serverSettleMatch && request.method === "POST") {
      if (origin) return reply({ error: "server_to_server_only" }, 403, origin, env);
      const rawKey = request.headers.get("X-Happy-Live-Game-Key") ?? "";
      if (rawKey.length < 32 || rawKey.length > 512) return reply({ error: "game_server_key_required" }, 401, origin, env);
      const key = await db.prepare("SELECT game_id AS gameId FROM game_server_keys WHERE key_hash = ? AND revoked_at IS NULL LIMIT 1").bind(await sha256(rawKey)).first<{ gameId: string }>();
      if (!key) return reply({ error: "game_server_key_invalid" }, 401, origin, env);
      const body = await readBody(request, 16384);
      if (!body || !body.result || typeof body.result !== "object" || Array.isArray(body.result) || !Array.isArray(body.payouts) || body.payouts.length > 100) {
        return reply({ error: "invalid_settlement_payload" }, 400, origin, env);
      }
      const roundId = serverSettleMatch[1];
      const round = await db.prepare("SELECT id, game_id AS gameId, user_id AS userId, status, total_stake AS totalStake FROM game_rounds WHERE id = ? AND game_id = ? LIMIT 1").bind(roundId, key.gameId).first<{ id: string; gameId: string; userId: string; status: string; totalStake: number }>();
      if (!round) return reply({ error: "game_round_not_found" }, 404, origin, env);
      if (round.status !== "open") return reply({ error: "game_round_already_settled" }, 409, origin, env);
      const settings = await db.prepare("SELECT max_payout_multiplier_bp AS maxMultiplier FROM game_economy_settings WHERE game_id = ? LIMIT 1").bind(key.gameId).first<{ maxMultiplier: number }>();
      if (!settings) return reply({ error: "game_economy_not_configured" }, 409, origin, env);
      const bets = await db.prepare("SELECT id, stake FROM game_bets WHERE round_id = ? AND status = 'accepted' ORDER BY created_at, id").bind(roundId).all<{ id: string; stake: number }>();
      const betRows = bets.results ?? [];
      const acceptedStakeTotal = betRows.reduce((sum, bet) => sum + bet.stake, 0);
      if (acceptedStakeTotal !== round.totalStake) return reply({ error: "game_round_ledger_mismatch" }, 409, origin, env);
      if (betRows.length === 0 || body.payouts.length !== betRows.length) return reply({ error: "settlement_bet_set_mismatch" }, 400, origin, env);
      const betMap = new Map<string, { id: string; stake: number }>(betRows.map(b => [b.id, b] as const));
      const payoutMap = new Map<string, number>();
      let totalPayout = 0;
      for (const item of body.payouts) {
        if (!item || typeof item !== "object" || Array.isArray(item)) return reply({ error: "invalid_settlement_payout" }, 400, origin, env);
        const betId = (item as Record<string, unknown>).betId;
        const payout = (item as Record<string, unknown>).payout;
        if (typeof betId !== "string" || !betMap.has(betId) || typeof payout !== "number" || !Number.isSafeInteger(payout) || payout < 0 || payoutMap.has(betId)) {
          return reply({ error: "invalid_settlement_payout" }, 400, origin, env);
        }
        payoutMap.set(betId, Number(payout));
        totalPayout += Number(payout);
      }
      if (payoutMap.size !== betRows.length || totalPayout > Math.floor(round.totalStake * settings.maxMultiplier / 10000)) {
        return reply({ error: "settlement_payout_limit_exceeded" }, 400, origin, env);
      }
      const resultJson = JSON.stringify(body.result) ?? "{}";
      if (new TextEncoder().encode(resultJson).length > 4096) return reply({ error: "settlement_result_too_large" }, 400, origin, env);
      const now = new Date().toISOString(), settlementId = crypto.randomUUID();
      const statements = [
        db.prepare("UPDATE game_rounds SET status = 'settling', total_payout = ?, result_json = ?, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND total_stake = ? AND (SELECT COALESCE(SUM(stake), 0) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (SELECT COUNT(*) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (? = 0 OR EXISTS (SELECT 1 FROM user_wallets WHERE user_id = ?))").bind(totalPayout, resultJson, now, settlementId, roundId, round.totalStake, roundId, acceptedStakeTotal, roundId, betRows.length, totalPayout, round.userId),
        ...betRows.map(b => db.prepare("UPDATE game_bets SET status = 'settled', payout = ?, settled_at = ? WHERE id = ? AND round_id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(payoutMap.get(b.id) ?? 0, now, b.id, roundId, roundId, settlementId))
      ];
      if (totalPayout > 0) {
        statements.push(db.prepare("UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(totalPayout, now, round.userId, roundId, settlementId));
        statements.push(db.prepare("INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, NULL, ?, 'payout_credit', ?, w.balance, ?, ? FROM user_wallets w WHERE w.user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)").bind(crypto.randomUUID(), key.gameId, roundId, round.userId, totalPayout, "payout:" + roundId, now, round.userId, roundId, settlementId));
      }
      statements.push(db.prepare("UPDATE game_rounds SET status = 'settled' WHERE id = ? AND status = 'settling' AND settlement_id = ?").bind(roundId, settlementId));
      await db.batch(statements);
      const settled = await db.prepare("SELECT status, total_payout AS totalPayout FROM game_rounds WHERE id = ? LIMIT 1").bind(roundId).first<{ status: string; totalPayout: number }>();
      if (settled?.status !== "settled") return reply({ error: "game_round_settlement_conflict" }, 409, origin, env);
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(round.userId).first<{ balance: number }>();
      return reply({ ok: true, roundId, status: "settled", totalPayout: settled.totalPayout, balance: wallet?.balance ?? 0 }, 200, origin, env);
    }

    if (isFoodWheelState || isFoodWheelBet || isFoodWheelHistory || isFoodWheelTopWins) {
      const user = await authenticateUser(request, db);
      if (!user) return reply({ error: "authentication_required" }, 401, origin, env);
      const activeGame = await db.prepare(
        "SELECT g.id FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.id = ? AND g.enabled = 1 AND l.status = 'active' LIMIT 1"
      ).bind(foodWheelGameId).first<{ id: string }>();
      if (!activeGame) return reply({ error: "game_not_active" }, 403, origin, env);

      const readGlobalState = async () => {
        const round = await db.prepare(
          "SELECT id, round_no AS roundNo, status, started_at AS startedAt, betting_ends_at AS bettingEndsAt, ends_at AS endsAt, result_slot AS resultSlot, result_special AS resultSpecial, totals_json AS totalsJson, result_chosen_at AS resultChosenAt FROM food_wheel_rounds WHERE status IN ('betting', 'result') ORDER BY round_no DESC LIMIT 1"
        ).first<{
          id: string; roundNo: number; status: string; startedAt: string;
          bettingEndsAt: string; endsAt: string; resultSlot: number | null; resultSpecial: "pizza" | "salad" | null; totalsJson: string; resultChosenAt: string | null;
        }>();
        if (!round) throw new Error("food_wheel_round_missing");

        const [myRows, winnerRows, recentRows, playersRow, payoutRow, wallet, profile] = await Promise.all([
          db.prepare(
            "SELECT slot, SUM(stake) AS amount FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND status IN ('accepted', 'settled') GROUP BY slot"
          ).bind(round.id, user.id).all<{ slot: number; amount: number }>(),
          db.prepare(
            "SELECT fb.user_id AS userId, COALESCE(p.display_name, '') AS name, p.avatar_key AS avatar, SUM(fb.payout) AS amount, CASE WHEN fb.user_id = ? THEN 1 ELSE 0 END AS isMe FROM food_wheel_bets fb LEFT JOIN profiles p ON p.user_id = fb.user_id WHERE fb.round_id = ? AND fb.payout > 0 AND fb.status IN ('accepted', 'settled') GROUP BY fb.user_id, p.display_name, p.avatar_key ORDER BY amount DESC, fb.user_id ASC LIMIT 3"
          ).bind(user.id, round.id).all<{ userId: string; name: string; avatar: string | null; amount: number; isMe: number }>(),
          db.prepare(
            "SELECT COALESCE(p.display_name, '') AS name, p.avatar_key AS avatar, fb.slot AS slot, fb.stake AS amount, CASE WHEN fb.user_id = ? THEN 1 ELSE 0 END AS isMe FROM food_wheel_bets fb LEFT JOIN profiles p ON p.user_id = fb.user_id WHERE fb.round_id = ? AND fb.slot BETWEEN 0 AND 7 AND fb.status IN ('accepted', 'settled') ORDER BY fb.created_at DESC, fb.id DESC LIMIT 12"
          ).bind(user.id, round.id).all<{ name: string; avatar: string | null; slot: number; amount: number; isMe: number }>(),
          db.prepare(
            "SELECT COUNT(DISTINCT user_id) AS count FROM food_wheel_bets WHERE round_id = ? AND status IN ('accepted', 'settled')"
          ).bind(round.id).first<{ count: number }>(),
          db.prepare(
            "SELECT COALESCE(SUM(payout), 0) AS amount FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND status IN ('accepted', 'settled')"
          ).bind(round.id, user.id).first<{ amount: number }>(),
          db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1")
            .bind(user.id).first<{ balance: number }>(),
          db.prepare(
            "SELECT display_name AS name, avatar_key AS avatar, country_flag AS flag FROM profiles WHERE user_id = ? LIMIT 1"
          ).bind(user.id).first<{ name: string | null; avatar: string | null; flag: string | null }>()
        ]);

        const pools = Array(8).fill(0) as number[];
        const myBets = Array(8).fill(0) as number[];
        const myBetsByKey: Record<string, number> = {};
        const storedTotals = JSON.parse(round.totalsJson || "{}") as Record<string, unknown>;
        const orderedKeys = ["chicken", "corn", "tomato", "goat", "chili", "fish", "carrot", "shrimp"] as const;
        for (let slot = 0; slot < orderedKeys.length; slot++) {
          const value = storedTotals[orderedKeys[slot]];
          pools[slot] = typeof value === "number" && Number.isFinite(value) ? value : 0;
        }
        for (const row of myRows.results ?? []) {
          if (row.slot >= 0 && row.slot < 8) {
            myBets[row.slot] = Number(row.amount) || 0;
            myBetsByKey[["chicken", "corn", "tomato", "goat", "chili", "fish", "carrot", "shrimp"][row.slot]] = Number(row.amount) || 0;
          }
        }
        const now = Date.now();
        const endAt = Date.parse(round.endsAt);
        const bettingEndAt = Date.parse(round.bettingEndsAt);
        const resultChosenAt = round.resultChosenAt ? Date.parse(round.resultChosenAt) : null;
        const topWinners = (winnerRows.results ?? []).map((row) => ({
          name: row.name,
          avatar: row.avatar,
          amount: Number(row.amount) || 0,
          is_me: Number(row.isMe) === 1
        }));
        const recentBets = (recentRows.results ?? []).map((row) => ({
          name: row.name,
          avatar: row.avatar,
          slot: row.slot,
          amount: Number(row.amount) || 0,
          is_me: Number(row.isMe) === 1
        }));
        // Explicit food-name keys prevent clients from mixing positional
        // totals with the player's separate local bet map.
        const slotKeys = [
          "chicken", "corn", "tomato", "goat",
          "chili", "fish", "carrot", "shrimp"
        ] as const;
        const totalBetsByFood: Record<string, number> = {};
        // Pizza and Salad are rare result indicators, never bet targets.
        const totalBetsByGroup: Record<string, number> = {
          pizza_group: 0,
          salad_group: 0
        };
        for (let slot = 0; slot < slotKeys.length; slot++) {
          totalBetsByFood[slotKeys[slot]] = pools[slot] ?? 0;
        }
        return {
          ok: true,
          round_id: round.roundNo,
          round_uuid: round.id,
          round_end_at: endAt,
          betting_ends_at: bettingEndAt,
          result_chosen_at: resultChosenAt,
          server_time: now,
          seconds_left: Math.max(0, Math.min(30, Math.ceil((endAt - now) / 1000))),
          betting_seconds_left: Math.max(0, Math.min(20, Math.ceil((bettingEndAt - now) / 1000))),
          phase: round.status === "betting" ? "betting" : "result",
          pools,
          total_bets: pools,
          total_bets_by_food: totalBetsByFood,
          total_bets_by_group: totalBetsByGroup,
          my_bets_by_key: myBetsByKey,
          my_bets: myBets,
          balance: wallet?.balance ?? 0,
          my_payout: Number(payoutRow?.amount) || 0,
          result_slot: round.resultSlot,
          special: round.resultSpecial,
          history: [],
          top_winners: topWinners,
          recent_bets: recentBets,
          players: Number(playersRow?.count) || 0,
          player: {
            id: user.happy_id ?? user.id,
            name: profile?.name ?? user.display_name ?? "",
            status: "active",
            avatar: profile?.avatar ?? null,
            flag: profile?.flag ?? null
          }
        };
      };

      if (isFoodWheelHistory) {
        const rows = await db.prepare(
          "SELECT r.round_no AS round_id, SUM(fb.stake) AS bet, SUM(fb.payout) AS payout, r.result_slot FROM food_wheel_rounds r INNER JOIN food_wheel_bets fb ON fb.round_id = r.id WHERE fb.user_id = ? AND r.status = 'settled' AND fb.status = 'settled' GROUP BY r.id, r.round_no, r.result_slot ORDER BY r.round_no DESC LIMIT 20"
        ).bind(user.id).all();
        return reply({ ok: true, rounds: rows.results ?? [] }, 200, origin, env);
      }

      if (isFoodWheelTopWins) {
        const rows = await db.prepare(
          "SELECT COALESCE(p.display_name, '') AS name, p.avatar_key AS avatar, p.country_flag AS flag, SUM(fb.payout) AS amount, CASE WHEN r.result_special = 'pizza' THEN '🍕' WHEN r.result_special = 'salad' THEN '🥗' WHEN r.result_slot = 0 THEN '🐔' WHEN r.result_slot = 1 THEN '🌽' WHEN r.result_slot = 2 THEN '🍅' WHEN r.result_slot = 3 THEN '🐐' WHEN r.result_slot = 4 THEN '🌶️' WHEN r.result_slot = 5 THEN '🐟' WHEN r.result_slot = 6 THEN '🥕' ELSE '🦐' END AS food, CASE WHEN fb.user_id = ? THEN 1 ELSE 0 END AS isMe FROM food_wheel_bets fb INNER JOIN food_wheel_rounds r ON r.id = fb.round_id LEFT JOIN profiles p ON p.user_id = fb.user_id WHERE fb.status = 'settled' AND fb.payout > 0 AND r.settled_at >= strftime('%Y-%m-%dT00:00:00Z', 'now') GROUP BY fb.user_id, p.display_name, p.avatar_key, p.country_flag, r.result_slot, r.result_special ORDER BY amount DESC LIMIT 20"
        ).bind(user.id).all();
        return reply({
          ok: true,
          wins: (rows.results ?? []).map((row: any) => ({ ...row, is_me: Number(row.isMe) === 1 }))
        }, 200, origin, env);
      }

      if (isFoodWheelState || isFoodWheelBet) {
        // Normal state polls do not enter the single Durable Object queue.
        // The alarm owns round progression; only bootstrap a round if none exists.
        const serverNowIso = new Date().toISOString();
        const activeRound = await db.prepare(
          "SELECT 1 AS active FROM food_wheel_rounds WHERE (status = 'betting' AND betting_ends_at > ?) OR (status = 'result' AND ends_at > ?) LIMIT 1"
        ).bind(serverNowIso, serverNowIso).first<{ active: number }>();
        if (!activeRound) {
          if (!env.FOOD_WHEEL_ROUNDS) {
            return reply({ error: "food_wheel_scheduler_unavailable" }, 503, origin, env);
          }
          const scheduler = env.FOOD_WHEEL_ROUNDS.get(
            env.FOOD_WHEEL_ROUNDS.idFromName("food-wheel-global")
          );
          const ensured = await scheduler.fetch("https://food-wheel.internal/ensure", { method: "POST" });
          if (!ensured.ok) return reply({ error: "food_wheel_scheduler_unavailable" }, 503, origin, env);
        }
      }

      if (isFoodWheelState) {
        try {
          return reply(await readGlobalState(), 200, origin, env);
        } catch (error) {
          console.error("[food-wheel.state]", error instanceof Error ? error.message : "UnknownError");
          return reply({ error: "food_wheel_state_unavailable" }, 503, origin, env);
        }
      }

      const body = await readBody(request, 2048);
      const roundId = body?.roundId;
      const slot = body?.slot;
      const amount = body?.amount;
      const idempotencyKey = typeof body?.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
      if (!body || typeof roundId !== "number" || !Number.isSafeInteger(roundId) ||
          typeof slot !== "number" || !Number.isSafeInteger(slot) || slot < 0 || slot > 7 ||
          typeof amount !== "number" || !Number.isSafeInteger(amount) || amount <= 0 ||
          !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
        return reply({ error: "invalid_bet_data" }, 400, origin, env);
      }

      const globalRound = await db.prepare(
        "SELECT id, round_no AS roundNo, status, betting_ends_at AS bettingEndsAt FROM food_wheel_rounds WHERE round_no = ? LIMIT 1"
      ).bind(roundId).first<{ id: string; roundNo: number; status: string; bettingEndsAt: string }>();
      if (!globalRound) {
        return reply({
          error: "round_not_found",
          rejected: true,
          reason: "round_not_found"
        }, 404, origin, env);
      }

      // Check the stable request key before checking the round clock. A retry
      // after a lost response must acknowledge the original accepted bet.
      const priorGlobalBet = await db.prepare(
        "SELECT fb.slot, fb.stake, fb.status, gb.status AS gameBetStatus FROM food_wheel_bets fb INNER JOIN game_bets gb ON gb.id = fb.game_bet_id WHERE fb.round_id = ? AND fb.user_id = ? AND gb.idempotency_key = ? LIMIT 1"
      ).bind(globalRound.id, user.id, idempotencyKey).first<{
        slot: number; stake: number; status: string; gameBetStatus: string;
      }>();
      if (priorGlobalBet) {
        if (priorGlobalBet.stake !== amount || priorGlobalBet.slot !== slot) {
          return reply({
            error: "idempotency_key_reused",
            rejected: true,
            reason: "idempotency_key_reused"
          }, 409, origin, env);
        }
        if (priorGlobalBet.status === "accepted" || priorGlobalBet.status === "settled" ||
            priorGlobalBet.gameBetStatus === "accepted" || priorGlobalBet.gameBetStatus === "settled") {
          return reply(await readGlobalState(), 200, origin, env);
        }
        return reply({
          error: "bet_processing",
          retryable: true,
          reason: "bet_is_still_processing"
        }, 409, origin, env);
      }

      if (globalRound.status !== "betting" || Date.now() >= Date.parse(globalRound.bettingEndsAt)) {
        return reply({
          error: "round_closed",
          rejected: true,
          reason: "betting_window_closed"
        }, 409, origin, env);
      }

      const existingFoods = await db.prepare(
        "SELECT COUNT(DISTINCT slot) AS count FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot BETWEEN 0 AND 7 AND status IN ('accepted', 'settled')"
      ).bind(globalRound.id, user.id).first<{ count: number }>();
      const sameFood = await db.prepare(
        "SELECT 1 AS found FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot = ? AND status IN ('accepted', 'settled') LIMIT 1"
      ).bind(globalRound.id, user.id, slot).first<{ found: number }>();
      if (slot < 8 && !sameFood && Number(existingFoods?.count ?? 0) >= 6) {
        return reply({ error: "max_foods_per_round", rejected: true }, 409, origin, env);
      }

      const financialKey = "food-wheel-global-" + globalRound.roundNo;
      await db.prepare(
        "INSERT OR IGNORE INTO game_rounds (id, game_id, user_id, idempotency_key, status, total_stake, total_payout, created_at) VALUES (?, ?, ?, ?, 'open', 0, 0, ?)"
      ).bind(crypto.randomUUID(), foodWheelGameId, user.id, financialKey, new Date().toISOString()).run();
      const financialRound = await db.prepare(
        "SELECT id, status FROM game_rounds WHERE game_id = ? AND user_id = ? AND idempotency_key = ? LIMIT 1"
      ).bind(foodWheelGameId, user.id, financialKey).first<{ id: string; status: string }>();
      if (!financialRound || financialRound.status !== "open") {
        return reply({
          error: "round_closed",
          rejected: true,
          reason: "financial_round_closed"
        }, 409, origin, env);
      }

      const selectionJson = JSON.stringify({ slot });
      const prior = await db.prepare(
        "SELECT id, stake, selection_json AS selectionJson, status FROM game_bets WHERE round_id = ? AND idempotency_key = ? LIMIT 1"
      ).bind(financialRound.id, idempotencyKey).first<{
        id: string; stake: number; selectionJson: string; status: string;
      }>();
      if (prior) {
        if (prior.stake !== amount || prior.selectionJson !== selectionJson) {
          return reply({
            error: "idempotency_key_reused",
            rejected: true,
            reason: "idempotency_key_reused"
          }, 409, origin, env);
        }
        if (prior.status === "accepted" || prior.status === "settled") {
          return reply(await readGlobalState(), 200, origin, env);
        }
        return reply({
          error: "bet_processing",
          retryable: true,
          reason: "bet_is_still_processing"
        }, 409, origin, env);
      }

      const betId = crypto.randomUUID();
      const wheelBetId = crypto.randomUUID();
      const now = new Date().toISOString();
      await db.batch([
        db.prepare(
          "INSERT OR IGNORE INTO game_bets (id, round_id, game_id, user_id, idempotency_key, stake, selection_json, payout, status, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, 0, 'processing', ? WHERE EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'open') AND EXISTS (SELECT 1 FROM food_wheel_rounds WHERE id = ? AND round_no = ? AND status = 'betting' AND betting_ends_at > ?)"
        ).bind(betId, financialRound.id, foodWheelGameId, user.id, idempotencyKey, amount, selectionJson, now, financialRound.id, globalRound.id, roundId, now),
        db.prepare(
          "INSERT INTO food_wheel_bets (id, round_id, game_round_id, game_bet_id, user_id, slot, stake, payout, status, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, 0, 'processing', ? FROM game_bets b WHERE b.id = ? AND b.status = 'processing' AND EXISTS (SELECT 1 FROM food_wheel_rounds WHERE id = ? AND status = 'betting' AND betting_ends_at > ?) AND (EXISTS (SELECT 1 FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot = ? AND status IN ('accepted', 'settled')) OR ? >= 8 OR (SELECT COUNT(DISTINCT slot) FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot BETWEEN 0 AND 7 AND status IN ('accepted', 'settled')) < 6)"
        ).bind(wheelBetId, globalRound.id, financialRound.id, betId, user.id, slot, amount, now, betId, globalRound.id, now, globalRound.id, user.id, slot, slot, globalRound.id, user.id),
        db.prepare(
          "UPDATE user_wallets SET balance = balance - ?, updated_at = ? WHERE user_id = ? AND balance >= ? AND EXISTS (SELECT 1 FROM food_wheel_bets WHERE id = ? AND status = 'processing') AND EXISTS (SELECT 1 FROM food_wheel_rounds WHERE id = ? AND status = 'betting' AND betting_ends_at > ?)"
        ).bind(amount, now, user.id, amount, wheelBetId, globalRound.id, now),
        db.prepare(
          "UPDATE game_bets SET status = 'accepted' WHERE id = ? AND status = 'processing' AND changes() = 1"
        ).bind(betId),
        db.prepare(
          "UPDATE food_wheel_bets SET status = 'accepted' WHERE id = ? AND status = 'processing' AND EXISTS (SELECT 1 FROM game_bets WHERE id = ? AND status = 'accepted')"
        ).bind(wheelBetId, betId),
        db.prepare(
          "UPDATE food_wheel_rounds SET totals_json = json_set(totals_json, '$.' || ?, COALESCE(json_extract(totals_json, '$.' || ?), 0) + ?) WHERE id = ? AND EXISTS (SELECT 1 FROM food_wheel_bets WHERE id = ? AND status = 'accepted')"
        ).bind(["chicken", "corn", "tomato", "goat", "chili", "fish", "carrot", "shrimp", "pizza_group", "salad_group"][slot], ["chicken", "corn", "tomato", "goat", "chili", "fish", "carrot", "shrimp", "pizza_group", "salad_group"][slot], amount, globalRound.id, wheelBetId),
        db.prepare(
          "UPDATE game_rounds SET total_stake = total_stake + ? WHERE id = ? AND status = 'open' AND EXISTS (SELECT 1 FROM food_wheel_bets WHERE id = ? AND status = 'accepted')"
        ).bind(amount, financialRound.id, wheelBetId),
        db.prepare(
          "INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, ?, ?, 'bet_debit', ?, w.balance, ?, ? FROM user_wallets w JOIN game_bets b ON b.id = ? JOIN food_wheel_bets fb ON fb.game_bet_id = b.id WHERE w.user_id = ? AND b.status = 'accepted' AND fb.status = 'accepted'"
        ).bind(crypto.randomUUID(), foodWheelGameId, financialRound.id, betId, user.id, -amount, "food-wheel-debit:" + betId, now, betId, user.id),
        db.prepare("DELETE FROM food_wheel_bets WHERE id = ? AND status = 'processing'").bind(wheelBetId),
        db.prepare("DELETE FROM game_bets WHERE id = ? AND status = 'processing'").bind(betId)
      ]);

      const accepted = await db.prepare(
        "SELECT id, stake, selection_json AS selectionJson, status FROM game_bets WHERE round_id = ? AND idempotency_key = ? LIMIT 1"
      ).bind(financialRound.id, idempotencyKey).first<{ id: string; stake: number; selectionJson: string; status: string }>();
      if (!accepted || accepted.status !== "accepted") {
        const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1")
          .bind(user.id).first<{ balance: number }>();
        const latest = await db.prepare(
          "SELECT status, betting_ends_at AS bettingEndsAt FROM food_wheel_rounds WHERE id = ? LIMIT 1"
        ).bind(globalRound.id).first<{ status: string; bettingEndsAt: string }>();
        if (!latest || latest.status !== "betting" || Date.now() >= Date.parse(latest.bettingEndsAt)) {
          return reply({
            error: "round_closed",
            rejected: true,
            reason: "betting_window_closed"
          }, 409, origin, env);
        }
        const latestFoods = await db.prepare(
          "SELECT COUNT(DISTINCT slot) AS count FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot BETWEEN 0 AND 7 AND status IN ('accepted', 'settled')"
        ).bind(globalRound.id, user.id).first<{ count: number }>();
        const latestSameFood = await db.prepare(
          "SELECT 1 AS found FROM food_wheel_bets WHERE round_id = ? AND user_id = ? AND slot = ? AND status IN ('accepted', 'settled') LIMIT 1"
        ).bind(globalRound.id, user.id, slot).first<{ found: number }>();
        if (!latestSameFood && Number(latestFoods?.count ?? 0) >= 6) {
          return reply({ error: "max_foods_per_round", rejected: true }, 409, origin, env);
        }
        if ((wallet?.balance ?? 0) < amount) {
          return reply({
            error: "insufficient_balance",
            rejected: true,
            reason: "insufficient_balance"
          }, 409, origin, env);
        }
        return reply({
          error: "bet_processing",
          retryable: true,
          reason: "bet_is_still_processing"
        }, 409, origin, env);
      }
      return reply(await readGlobalState(), 200, origin, env);
    }

    if (isAuth) {
      const user = await authenticateUser(request, db);
      if (!user) return reply({ error: "authentication_required" }, 401, origin, env);
      const body = await readBody(request);
      const gameId = typeof body?.gameId === "string" ? body.gameId.trim() : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(gameId)) {
        return reply({ error: "invalid_game_id" }, 400, origin, env);
      }
      const game = await db.prepare(
        "SELECT g.id, g.name, g.game_url AS gameUrl, g.enabled, l.status FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.id = ? LIMIT 1"
      ).bind(gameId).first<{ id: string; name: string; gameUrl: string; enabled: number; status: string }>();
      if (!game) return reply({ error: "game_not_found" }, 404, origin, env);
      if (game.status !== "active" || game.enabled !== 1 || game.gameUrl === "https://pending-game.happylive.invalid") {
        return reply({ error: "game_not_active" }, 403, origin, env);
      }
      const gameOrigin = await gameOriginForId(db, gameId);
      if (!gameOrigin) return reply({ error: "game_url_invalid" }, 403, origin, env);
      const sessionToken = "hlg_" + crypto.randomUUID() + "." + crypto.randomUUID();
      const now = new Date();
      const expiresAt = new Date(now.getTime() + GAME_SESSION_TTL_SECONDS * 1000).toISOString();
      const gameSessionId = crypto.randomUUID();
      await db.batch([
        db.prepare(
          "INSERT INTO game_sessions (id, game_id, user_id, token_hash, permissions_json, game_origin, expires_at, created_at, rate_window_started_at, request_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)"
        ).bind(gameSessionId, gameId, user.id, await sha256(sessionToken), JSON.stringify(GAME_PERMISSIONS), gameOrigin, expiresAt, now.toISOString(), Math.floor(now.getTime() / 1000)),
        db.prepare(
          "INSERT INTO game_session_app_bindings (game_session_id, app_session_id, created_at) VALUES (?, ?, ?)"
        ).bind(gameSessionId, user.session_id, now.toISOString())
      ]);
      const playerProfile = await db.prepare(
        "SELECT avatar_key AS avatarUrl, country_name AS countryName FROM profiles WHERE user_id = ? LIMIT 1"
      ).bind(user.id).first<{ avatarUrl: string | null; countryName: string | null }>();
      const publicPlayerId = user.happy_id ?? "";
      return reply({
        ok: true,
        tokenType: "Bearer",
        sessionToken,
        expiresAt,
        expiresIn: GAME_SESSION_TTL_SECONDS,
        game: { id: game.id, name: game.name },
        player: {
          id: publicPlayerId,
          userCode: publicPlayerId,
          displayName: user.display_name ?? "",
          avatarUrl: playerProfile?.avatarUrl ?? null,
          countryName: playerProfile?.countryName ?? null,
          accountStatus: "active"
        },
        permissions: GAME_PERMISSIONS
      }, 201, origin, env);
    }

    const rawToken = tokenValue(request);
    if (!rawToken) return reply({ error: "game_session_required" }, 401, origin, env);
    const tokenHash = await sha256(rawToken);
    const session = await db.prepare(
      "SELECT s.id, s.game_id AS gameId, s.user_id AS userId, s.permissions_json AS permissionsJson, s.game_origin AS gameOrigin, s.expires_at AS expiresAt, g.name AS gameName, g.game_url AS gameUrl, g.enabled, l.status, u.status AS userStatus FROM game_sessions s INNER JOIN game_session_app_bindings app_binding ON app_binding.game_session_id = s.id INNER JOIN user_sessions app ON app.id = app_binding.app_session_id AND app.user_id = s.user_id AND app.revoked_at IS NULL AND app.expires_at > ? INNER JOIN game_registry g ON g.id = s.game_id INNER JOIN game_registry_lifecycle l ON l.game_id = g.id INNER JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? LIMIT 1"
    ).bind(new Date().toISOString(), tokenHash, new Date().toISOString()).first<{
      id: string; gameId: string; userId: string; permissionsJson: string; gameOrigin: string; expiresAt: string;
      gameName: string; gameUrl: string; enabled: number; status: string; userStatus: string;
    }>();
    if (!session) return reply({ error: "game_session_expired_or_invalid" }, 401, origin, env);
    if (session.status !== "active" || session.enabled !== 1 || session.userStatus !== "active" || session.gameUrl === "https://pending-game.happylive.invalid") {
      return reply({ error: "game_or_player_unavailable" }, 403, origin, env);
    }
    const currentGameOrigin = await gameOriginForId(db, session.gameId);
    if (!currentGameOrigin || currentGameOrigin !== session.gameOrigin) return reply({ error: "game_origin_changed" }, 403, origin, env);
    if (origin && !isAllowedSessionOrigin(session.gameOrigin, origin)) {
      console.warn("[games.api] game session origin rejected", {
        gameId: session.gameId, registeredOrigin: session.gameOrigin, requestOrigin: origin
      });
      return reply({ error: "game_origin_mismatch" }, 403, origin, env);
    }
    const nowSeconds = Math.floor(Date.now() / 1000);
    const rate = await db.prepare(
      "UPDATE game_sessions SET rate_window_started_at = CASE WHEN ? - rate_window_started_at >= ? THEN ? ELSE rate_window_started_at END, request_count = CASE WHEN ? - rate_window_started_at >= ? THEN 1 ELSE request_count + 1 END, last_seen_at = ? WHERE id = ? AND revoked_at IS NULL AND expires_at > ? RETURNING request_count"
    ).bind(nowSeconds, GAME_SESSION_RATE_WINDOW_SECONDS, nowSeconds, nowSeconds, GAME_SESSION_RATE_WINDOW_SECONDS, new Date().toISOString(), session.id, new Date().toISOString()).first<{ request_count: number }>();
    if (!rate) return reply({ error: "game_session_expired_or_invalid" }, 401, origin, env);
    if (rate.request_count > GAME_SESSION_RATE_MAX_REQUESTS) return reply({ error: "game_rate_limited" }, 429, origin, env);
    const permissions = JSON.parse(session.permissionsJson) as string[];
    const has = (permission: string) => permissions.includes(permission);
    if (isListRounds) {
      if (!has("round.read")) return reply({ error: "permission_denied" }, 403, origin, env);
      const rows = await db.prepare(
        "SELECT id, status, total_stake AS totalStake, total_payout AS totalPayout, result_json AS result, created_at AS createdAt, settled_at AS settledAt FROM game_rounds WHERE game_id = ? AND user_id = ? ORDER BY created_at DESC LIMIT 50"
      ).bind(session.gameId, session.userId).all();
      return reply({ ok: true, rounds: rows.results ?? [] }, 200, origin, env);
    }
    if (isCreateRound) {
      if (!has("round.create")) return reply({ error: "permission_denied" }, 403, origin, env);
      const body = await readBody(request);
      const idempotencyKey = typeof body?.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
      if (!/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) return reply({ error: "invalid_idempotency_key" }, 400, origin, env);
      const existing = await db.prepare("SELECT id, status, total_stake AS totalStake FROM game_rounds WHERE game_id = ? AND user_id = ? AND idempotency_key = ? LIMIT 1").bind(session.gameId, session.userId, idempotencyKey).first<Record<string, unknown>>();
      if (existing) return reply({ ok: true, round: existing, reused: true }, 200, origin, env);
      const roundId = crypto.randomUUID(), now = new Date().toISOString();
      await db.prepare("INSERT OR IGNORE INTO game_rounds (id, game_id, user_id, idempotency_key, status, total_stake, total_payout, created_at) SELECT ?, ?, ?, ?, 'open', 0, 0, ? WHERE EXISTS (SELECT 1 FROM game_economy_settings WHERE game_id = ? AND enabled = 1)").bind(roundId, session.gameId, session.userId, idempotencyKey, now, session.gameId).run();
      const created = await db.prepare("SELECT id, status, total_stake AS totalStake FROM game_rounds WHERE game_id = ? AND user_id = ? AND idempotency_key = ? LIMIT 1").bind(session.gameId, session.userId, idempotencyKey).first<Record<string, unknown>>();
      if (!created) return reply({ error: "game_economy_disabled" }, 403, origin, env);
      return reply({ ok: true, round: created, reused: false }, 201, origin, env);
    }
    if (placeBetMatch && request.method === "POST") {
      if (!has("bets.place")) return reply({ error: "permission_denied" }, 403, origin, env);
      const body = await readBody(request, 4096);
      const idempotencyKey = typeof body?.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
      const stake = body?.stake;
      const selection = body?.selection === undefined ? {} : body.selection;
      if (!/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey) || typeof stake !== "number" || !Number.isSafeInteger(stake) || stake <= 0 ||
          !selection || typeof selection !== "object" || Array.isArray(selection)) return reply({ error: "invalid_bet_data" }, 400, origin, env);
      const selectionJson = JSON.stringify(selection);
      if (new TextEncoder().encode(selectionJson).length > 1024) return reply({ error: "bet_selection_too_large" }, 400, origin, env);
      const roundId = placeBetMatch[1];
      const round = await db.prepare("SELECT id, status FROM game_rounds WHERE id = ? AND game_id = ? AND user_id = ? LIMIT 1").bind(roundId, session.gameId, session.userId).first<{ id: string; status: string }>();
      if (!round) return reply({ error: "game_round_not_found" }, 404, origin, env);
      const existing = await db.prepare("SELECT id, stake, selection_json AS selectionJson, status FROM game_bets WHERE round_id = ? AND idempotency_key = ? LIMIT 1").bind(roundId, idempotencyKey).first<{ id: string; stake: number; selectionJson: string; status: string }>();
      if (existing) {
        if (existing.stake !== Number(stake) || existing.selectionJson !== selectionJson) return reply({ error: "idempotency_key_reused" }, 409, origin, env);
        const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(session.userId).first<{ balance: number }>();
        return reply({ ok: true, bet: existing, balance: wallet?.balance ?? 0, reused: true }, 200, origin, env);
      }
      if (round.status !== "open") return reply({ error: "game_round_not_open" }, 409, origin, env);
      const settings = await db.prepare("SELECT enabled, min_bet AS minBet, max_bet AS maxBet, max_bets_per_round AS maxBets, max_total_bet AS maxTotal FROM game_economy_settings WHERE game_id = ? LIMIT 1").bind(session.gameId).first<{ enabled: number; minBet: number; maxBet: number; maxBets: number; maxTotal: number }>();
      if (!settings || settings.enabled !== 1) return reply({ error: "game_economy_disabled" }, 403, origin, env);
      if (Number(stake) < settings.minBet || Number(stake) > settings.maxBet) return reply({ error: "bet_out_of_range", minBet: settings.minBet, maxBet: settings.maxBet }, 400, origin, env);
      const betId = crypto.randomUUID(), now = new Date().toISOString();
      await db.batch([
        db.prepare("INSERT OR IGNORE INTO game_bets (id, round_id, game_id, user_id, idempotency_key, stake, selection_json, payout, status, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, 0, 'processing', ? WHERE EXISTS (SELECT 1 FROM game_rounds r JOIN game_economy_settings s ON s.game_id = r.game_id WHERE r.id = ? AND r.status = 'open' AND r.game_id = ? AND r.user_id = ? AND s.enabled = 1 AND ? BETWEEN s.min_bet AND s.max_bet AND (SELECT COUNT(*) FROM game_bets b WHERE b.round_id = r.id AND b.status IN ('accepted','settled')) < s.max_bets_per_round AND r.total_stake + ? <= s.max_total_bet) AND EXISTS (SELECT 1 FROM user_wallets w WHERE w.user_id = ? AND w.balance >= ?)").bind(betId, roundId, session.gameId, session.userId, idempotencyKey, stake, selectionJson, now, roundId, session.gameId, session.userId, stake, stake, session.userId, stake),
        db.prepare("UPDATE user_wallets SET balance = balance - ?, updated_at = ? WHERE user_id = ? AND balance >= ? AND changes() = 1").bind(stake, now, session.userId, stake),
        db.prepare("UPDATE game_bets SET status = 'accepted' WHERE id = ? AND status = 'processing' AND changes() = 1").bind(betId),
        db.prepare("UPDATE game_rounds SET total_stake = total_stake + ? WHERE id = ? AND status = 'open' AND changes() = 1").bind(stake, roundId),
        db.prepare("INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, b.id, b.user_id, 'bet_debit', -b.stake, w.balance, ?, ? FROM game_bets b JOIN user_wallets w ON w.user_id = b.user_id WHERE b.id = ? AND b.status = 'accepted' AND changes() = 1").bind(crypto.randomUUID(), session.gameId, roundId, "bet:" + betId, now, betId),
        db.prepare("DELETE FROM game_bets WHERE id = ? AND status = 'processing'").bind(betId)
      ]);
      const accepted = await db.prepare("SELECT id, stake, selection_json AS selectionJson, status FROM game_bets WHERE round_id = ? AND idempotency_key = ? LIMIT 1").bind(roundId, idempotencyKey).first<Record<string, unknown>>();
      if (!accepted) {
        const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(session.userId).first<{ balance: number }>();
        return reply({ error: (wallet?.balance ?? 0) < Number(stake) ? "insufficient_balance" : "bet_rejected" }, 409, origin, env);
      }
      // A concurrent request may win the same idempotency key after our
      // preflight lookup. Never report success for a different stake/selection.
      if (accepted.stake !== Number(stake) || accepted.selectionJson !== selectionJson) {
        return reply({ error: "idempotency_key_reused" }, 409, origin, env);
      }
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(session.userId).first<{ balance: number }>();
      return reply({ ok: true, bet: accepted, balance: wallet?.balance ?? 0, reused: false }, 201, origin, env);
    }
    if (getRoundMatch && request.method === "GET") {
      if (!has("round.read")) return reply({ error: "permission_denied" }, 403, origin, env);
      const roundId = getRoundMatch[1];
      const round = await db.prepare("SELECT id, status, total_stake AS totalStake, total_payout AS totalPayout, result_json AS result, created_at AS createdAt, settled_at AS settledAt FROM game_rounds WHERE id = ? AND game_id = ? AND user_id = ? LIMIT 1").bind(roundId, session.gameId, session.userId).first<Record<string, unknown>>();
      if (!round) return reply({ error: "game_round_not_found" }, 404, origin, env);
      const bets = await db.prepare("SELECT id, stake, selection_json AS selection, payout, status, created_at AS createdAt FROM game_bets WHERE round_id = ? ORDER BY created_at, id").bind(roundId).all();
      return reply({ ok: true, round, bets: bets.results ?? [] }, 200, origin, env);
    }
    if (isRefresh) {
      // Extend this session in place. Keeping the same bearer token makes
      // refresh retries safe if a response is lost while the player is online.
      const refreshedAt = new Date().toISOString();
      const nextExpiresAt = new Date(Date.now() + GAME_SESSION_TTL_SECONDS * 1000).toISOString();
      const refreshed = await db.prepare(
        "UPDATE game_sessions SET expires_at = ?, last_seen_at = ? WHERE id = ? AND revoked_at IS NULL AND expires_at > ? AND EXISTS (SELECT 1 FROM game_session_app_bindings binding INNER JOIN user_sessions app ON app.id = binding.app_session_id AND app.user_id = game_sessions.user_id WHERE binding.game_session_id = game_sessions.id AND app.revoked_at IS NULL AND app.expires_at > ?) AND EXISTS (SELECT 1 FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id INNER JOIN users u ON u.id = game_sessions.user_id WHERE g.id = game_sessions.game_id AND g.enabled = 1 AND l.status = 'active' AND u.status = 'active')"
      ).bind(nextExpiresAt, refreshedAt, session.id, refreshedAt, refreshedAt).run();
      if (Number(refreshed.meta?.changes ?? 0) !== 1) {
        return reply({ error: "game_session_refresh_denied" }, 401, origin, env);
      }
      return reply({
        ok: true,
        expiresAt: nextExpiresAt,
        expiresIn: GAME_SESSION_TTL_SECONDS
      }, 200, origin, env);
    }
    if (isRevoke) {
      await db.prepare("UPDATE game_sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL").bind(new Date().toISOString(), session.id).run();
      return reply({ ok: true, revoked: true }, 200, origin, env);
    }
    if (isSession) {
      if (!has("session.read")) return reply({ error: "permission_denied" }, 403, origin, env);
      return reply({ ok: true, game: { id: session.gameId, name: session.gameName }, expiresAt: session.expiresAt, permissions }, 200, origin, env);
    }
    if (isProfile) {
      if (!has("profile.read")) return reply({ error: "permission_denied" }, 403, origin, env);
      const profile = await db.prepare(
        "SELECT u.status AS accountStatus, p.display_name AS displayName, p.happy_id AS userCode, p.avatar_key AS avatarUrl, p.country_name AS countryName FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.id = ? LIMIT 1"
      ).bind(session.userId).first<{
        accountStatus: string;
        displayName: string | null;
        userCode: string | null;
        avatarUrl: string | null;
        countryName: string | null;
      }>();
      if (!profile || profile.accountStatus !== "active") {
        return reply({ error: "player_account_unavailable" }, 403, origin, env);
      }
      const publicPlayerId = profile.userCode ?? "";
      return reply({
        ok: true,
        player: {
          id: publicPlayerId,
          userCode: publicPlayerId,
          displayName: profile.displayName ?? "",
          avatarUrl: profile.avatarUrl,
          countryName: profile.countryName,
          accountStatus: profile.accountStatus
        },
        // Keep the earlier key for clients already using the phase-2 profile response.
        profile: {
          displayName: profile.displayName ?? "",
          userCode: publicPlayerId,
          avatarUrl: profile.avatarUrl,
          countryName: profile.countryName
        }
      }, 200, origin, env);
    }
    if (isWallet) {
      if (!has("wallet.read")) return reply({ error: "permission_denied" }, 403, origin, env);
      const wallet = await db.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(session.userId).first<{ balance: number }>();
      return reply({ ok: true, balance: wallet?.balance ?? 0, currency: "coins" }, 200, origin, env);
    }
    return null;
  } catch (error) {
    console.error("[games.api] request failed", error instanceof Error ? error.message : "UnknownError");
    return reply({ error: "games_api_unavailable" }, 503, origin, env);
  }
}
