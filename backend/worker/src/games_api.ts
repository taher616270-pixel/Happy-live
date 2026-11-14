type GameApiUser = { id: string; session_id: string; display_name: string | null; happy_id: string | null };
type GameApiEnv = { DB?: D1Database };
type GameApiJson = (data: unknown, status?: number, origin?: string, env?: any) => Response;
const GAME_SESSION_TTL_SECONDS = 15 * 60;
const GAME_SESSION_RATE_WINDOW_SECONDS = 60;
const GAME_SESSION_RATE_MAX_REQUESTS = 120;
const GAME_PERMISSIONS = ["session.read", "profile.read", "wallet.read"] as const;

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function tokenValue(request: Request): string {
  const match = (request.headers.get("Authorization") ?? "").match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
  return match?.[1] ?? "";
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  const length = Number(request.headers.get("Content-Length") ?? 0);
  if (Number.isFinite(length) && length > 2048) return null;
  try {
    const body = await request.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : null;
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
  json: GameApiJson
): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  const isAuth = path === "/api/v1/game/auth" && request.method === "POST";
  const isSession = path === "/api/v1/game/session" && request.method === "GET";
  const isRefresh = path === "/api/v1/game/session/refresh" && request.method === "POST";
  const isRevoke = path === "/api/v1/game/session/revoke" && request.method === "POST";
  const isProfile = path === "/api/v1/game/profile" && request.method === "GET";
  const isWallet = path === "/api/v1/game/wallet" && request.method === "GET";
  if (!isAuth && !isSession && !isRefresh && !isRevoke && !isProfile && !isWallet) return null;
  const reply = (data: unknown, status = 200, _origin?: string, _env?: any) => origin
    ? withGameCors(json(data, status, undefined, env), origin, origin)
    : json(data, status, undefined, env);
  if (!env.DB) return reply({ error: "database_unavailable" }, 503, origin, env);
  const db = env.DB;
  try {
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
    if (origin && origin !== session.gameOrigin) return reply({ error: "game_origin_mismatch" }, 403, origin, env);
    const nowSeconds = Math.floor(Date.now() / 1000);
    const rate = await db.prepare(
      "UPDATE game_sessions SET rate_window_started_at = CASE WHEN ? - rate_window_started_at >= ? THEN ? ELSE rate_window_started_at END, request_count = CASE WHEN ? - rate_window_started_at >= ? THEN 1 ELSE request_count + 1 END, last_seen_at = ? WHERE id = ? AND revoked_at IS NULL AND expires_at > ? RETURNING request_count"
    ).bind(nowSeconds, GAME_SESSION_RATE_WINDOW_SECONDS, nowSeconds, nowSeconds, GAME_SESSION_RATE_WINDOW_SECONDS, new Date().toISOString(), session.id, new Date().toISOString()).first<{ request_count: number }>();
    if (!rate) return reply({ error: "game_session_expired_or_invalid" }, 401, origin, env);
    if (rate.request_count > GAME_SESSION_RATE_MAX_REQUESTS) return reply({ error: "game_rate_limited" }, 429, origin, env);
    const permissions = JSON.parse(session.permissionsJson) as string[];
    const has = (permission: string) => permissions.includes(permission);
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
