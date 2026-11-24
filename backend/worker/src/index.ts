import { RtcTokenBuilder } from "agora-token";
import { handleGamesApiRequest, isRegisteredGameOrigin } from "./games_api";
import { handlePlatformCallbackRequest } from "./platform_callback";
import { addCannonEnergy, handleCannonRequest } from "./cannon_api";
import { addRoomContribution, handleRoomContrib } from "./room_contrib";
import { handleRoomTools } from "./room_tools";
export { RoomSeatsHub } from "./room_seats_hub";
export { GlobalGiftHub } from "./global_gift_hub";
import type { GlobalGiftHub } from "./global_gift_hub";
const GLOBAL_GIFT_SHARD_COUNT = 16;

function globalGiftShardForUser(userId: string): number {
  let hash = 2166136261;
  for (let index = 0; index < userId.length; index++) {
    hash ^= userId.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) % GLOBAL_GIFT_SHARD_COUNT;
}

export interface Env {
  DB?: D1Database;
  ROOM_CHAT?: DurableObjectNamespace;
  ROOM_SEATS?: DurableObjectNamespace;
  GLOBAL_GIFTS?: DurableObjectNamespace<GlobalGiftHub>;
  APP_ENV?: string;
  ALLOWED_ORIGINS?: string;
  IMAGEKIT_PUBLIC_KEY?: string;
  IMAGEKIT_PRIVATE_KEY?: string;
  ADMIN_SETUP_TOKEN?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_ENABLED?: string;
  GOOGLE_CLIENT_ID?: string;
  UTD_APP_KEY?: string;
}


const SESSION_TTL_DAYS = 30;
const PASSWORD_ITERATIONS = 100000;
const AUTH_RATE_WINDOW_SECONDS = 900;
const AUTH_RATE_MAX_ATTEMPTS = 8;

const ROOM_EXP_PER_LEVEL_GROUP = 3_300_000;
const MAX_ROOM_EXPERIENCE_LEVEL = 150;
const ROOM_EXP_DAILY_USER_CAP = 3_000_000;

function roomExperienceRequiredForLevel(targetLevel: number): number {
  let total = 0;
  for (let nextLevel = 2; nextLevel <= targetLevel; nextLevel++) {
    const group = Math.floor((nextLevel - 1) / 5) + 1;
    total += group * ROOM_EXP_PER_LEVEL_GROUP;
  }
  return total;
}
const ROOM_EXP_DAILY_ROOM_CAP = 14_000_000;

const SAUDI_UTC_OFFSET_MS = 3 * 60 * 60 * 1000;
function saudiDayKey(value: string): string {
  return new Date(Date.parse(value) + SAUDI_UTC_OFFSET_MS).toISOString().slice(0, 10);
}
function secondsUntilSaudiMidnight(value: string): number {
  const nowMs = Date.parse(value);
  const saudiNow = new Date(nowMs + SAUDI_UTC_OFFSET_MS);
  const nextMidnightUtcMs = Date.UTC(
    saudiNow.getUTCFullYear(), saudiNow.getUTCMonth(), saudiNow.getUTCDate() + 1
  ) - SAUDI_UTC_OFFSET_MS;
  return Math.max(0, Math.min(86400, Math.ceil((nextMidnightUtcMs - nowMs) / 1000)));
}

function roomExperienceProgress(totalExperience: number) {
  let level = 1;
  let remaining = Number.isFinite(totalExperience)
    ? Math.max(0, Math.floor(totalExperience))
    : 0;

  // The cost is determined by the level being entered:
  // levels 2-5 cost 3.3m each, 6-10 cost 6.6m each, etc.
  while (level < MAX_ROOM_EXPERIENCE_LEVEL) {
    const nextLevel = level + 1;
    const group = Math.floor((nextLevel - 1) / 5) + 1;
    const nextLevelExp = group * ROOM_EXP_PER_LEVEL_GROUP;
    if (remaining < nextLevelExp) {
      return { level, exp: remaining, nextLevelExp };
    }
    remaining -= nextLevelExp;
    level = nextLevel;
  }
  return { level: MAX_ROOM_EXPERIENCE_LEVEL, exp: 0, nextLevelExp: 0 };
}

async function resetRoomSeatExperienceTimer(
  db: D1Database,
  roomId: string,
  userId: string,
  now: string
): Promise<void> {
  await db.prepare(
    "INSERT INTO room_exp_activity (room_id, user_id, last_awarded_at) VALUES (?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET last_awarded_at = excluded.last_awarded_at"
  ).bind(roomId, userId, now).run();
}

async function awardRoomSeatExperience(
  db: D1Database,
  roomId: string,
  userId: string,
  now: string
): Promise<void> {
  const nowMs = Date.parse(now);
  const dayKey = saudiDayKey(now);
  await db.prepare(
    "INSERT OR IGNORE INTO room_exp_activity (room_id, user_id, last_awarded_at) VALUES (?, ?, ?)"
  ).bind(roomId, userId, now).run();
  const activity = await db.prepare(
    "SELECT last_awarded_at FROM room_exp_activity WHERE room_id = ? AND user_id = ? LIMIT 1"
  ).bind(roomId, userId).first<{ last_awarded_at: string }>();
  if (!activity?.last_awarded_at || nowMs - Date.parse(activity.last_awarded_at) < 300_000) return;

  const account = await db.prepare(
    "SELECT created_at FROM users WHERE id = ? LIMIT 1"
  ).bind(userId).first<{ created_at: string }>();
  const accountCreatedAt = Date.parse(account?.created_at ?? "");
  const isNewAccount = Number.isFinite(accountCreatedAt) &&
    nowMs >= accountCreatedAt &&
    nowMs - accountCreatedAt < 15 * 24 * 60 * 60 * 1000;
  const awardPoints = isNewAccount ? 1200 : 600;
  const advanced = await db.prepare(
    "UPDATE room_exp_activity SET last_awarded_at = ? WHERE room_id = ? AND user_id = ? AND last_awarded_at = ?"
  ).bind(now, roomId, userId, activity.last_awarded_at).run();
  if ((advanced.meta?.changes ?? 0) !== 1) return;

  try {
    await db.prepare(
      "INSERT OR IGNORE INTO room_exp_daily (user_id, day_key, points) VALUES (?, ?, 0)"
    ).bind(userId, dayKey).run();

    const awardId = crypto.randomUUID();
    await db.batch([
      db.prepare(
        "INSERT INTO room_exp_awards (id, room_id, user_id, day_key, points, created_at) SELECT ?, ?, ?, ?, MIN(?, ? - points, ? - COALESCE((SELECT SUM(points) FROM room_exp_awards WHERE room_id = ? AND day_key = ?), 0), ? - COALESCE((SELECT SUM(points) FROM room_exp_awards WHERE room_id = ? AND day_key = ?), 0) - COALESCE((SELECT SUM(points) FROM room_exp_gift_awards WHERE room_id = ? AND day_key = ?), 0)), ? FROM room_exp_daily WHERE user_id = ? AND day_key = ? AND points < ?"
      ).bind(awardId, roomId, userId, dayKey, awardPoints, ROOM_EXP_DAILY_USER_CAP, 1_000_000, roomId, dayKey, ROOM_EXP_DAILY_ROOM_CAP, roomId, dayKey, roomId, dayKey, now, userId, dayKey, ROOM_EXP_DAILY_USER_CAP),
      db.prepare(
        "UPDATE room_exp_daily SET points = points + COALESCE((SELECT points FROM room_exp_awards WHERE id = ?), 0) WHERE user_id = ? AND day_key = ?"
      ).bind(awardId, userId, dayKey),
      db.prepare(
        "INSERT INTO room_experience (room_id, total_exp, updated_at) SELECT ?, points, ? FROM room_exp_awards WHERE id = ? ON CONFLICT(room_id) DO UPDATE SET total_exp = room_experience.total_exp + excluded.total_exp, updated_at = excluded.updated_at"
      ).bind(roomId, now, awardId)
    ]);
  } catch (error) {
    // If D1 fails, restore the old timestamp so the user's earned mic time is not lost.
    try {
      await db.prepare(
        "UPDATE room_exp_activity SET last_awarded_at = ? WHERE room_id = ? AND user_id = ? AND last_awarded_at = ?"
      ).bind(activity.last_awarded_at, roomId, userId, now).run();
    } catch {
      // Keep the original D1 error; the next heartbeat can retry if rollback was unavailable.
    }
    throw error;
  }
}


const DEFAULT_GOOGLE_CLIENT_ID = '999298541545-5i0kn2d1emj2rohuvruj4o8ej49ho9kg.apps.googleusercontent.com';

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function fromHex(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(value.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

async function sha256(value: string): Promise<string> {
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))));
}

async function isAgoraVoiceEnabled(db: D1Database, env: Env): Promise<boolean> {
  if (env.AGORA_ENABLED === "false") return false;
  const setting = await db.prepare(
    "SELECT setting_value FROM platform_settings WHERE setting_key = 'agora_voice_enabled' LIMIT 1"
  ).first<{ setting_value: string }>();
  return setting?.setting_value !== "false";
}

function constantTimeTextEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return difference === 0;
}

async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: PASSWORD_ITERATIONS, hash: "SHA-256" },
    key,
    256
  );
  return "pbkdf2_sha256$" + PASSWORD_ITERATIONS + "$" + toHex(salt) + "$" + toHex(new Uint8Array(bits));
}

async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2_sha256") return false;
  const iterations = Number(parts[1]);
  if (!Number.isInteger(iterations) || iterations < 100000 || iterations > 500000) return false;
  const expected = fromHex(parts[3]);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: fromHex(parts[2]), iterations, hash: "SHA-256" },
    key,
    expected.length * 8
  ));
  if (bits.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < bits.length; i++) diff |= bits[i] ^ expected[i];
  return diff === 0;
}

function calculateAge(dateValue: string): number | null {
  const date = new Date(`${dateValue}T00:00:00.000Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateValue) || Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== dateValue) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  if (now.getUTCMonth() < date.getUTCMonth() || (now.getUTCMonth() === date.getUTCMonth() && now.getUTCDate() < date.getUTCDate())) age--;
  return age;
}

async function createSession(db: D1Database, userId: string): Promise<{ accessToken: string; expiresAt: string }> {
  const accessToken = `${crypto.randomUUID()}.${crypto.randomUUID()}`;
  const expiresAt = new Date(Date.now() + SESSION_TTL_DAYS * 86400000).toISOString();
  await db.prepare("INSERT INTO user_sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)")
    .bind(crypto.randomUUID(), userId, await sha256(accessToken), expiresAt).run();
  return { accessToken, expiresAt };
}

async function ensurePublicUserId(db: D1Database, userId: string, currentId?: string | null): Promise<string> {
  if (currentId && /^\d{8}$/.test(currentId)) return currentId;
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = String(10000000 + crypto.getRandomValues(new Uint32Array(1))[0] % 90000000);
    try {
      const result = await db.prepare(
        "UPDATE profiles SET happy_id = ? WHERE user_id = ? AND (happy_id IS NULL OR happy_id = '')"
      ).bind(candidate, userId).run();
      if ((result.meta?.changes ?? 0) > 0) return candidate;
      const existing = await db.prepare("SELECT happy_id FROM profiles WHERE user_id = ? LIMIT 1")
        .bind(userId).first<{ happy_id: string | null }>();
      if (existing?.happy_id) return existing.happy_id;
    } catch {
      // A duplicate public ID is extremely unlikely; safely try another.
    }
  }
  throw new Error("public_id_generation_failed");
}

async function authenticatedUser(request: Request, db: D1Database) {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
  if (!match) return null;
  const row = await db.prepare(
    "SELECT s.id AS session_id, u.id, u.email, p.display_name, p.happy_id FROM user_sessions s INNER JOIN users u ON u.id = s.user_id LEFT JOIN profiles p ON p.user_id = u.id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active' LIMIT 1"
  ).bind(await sha256(match[1]), new Date().toISOString()).first<{ session_id: string; id: string; email: string; display_name: string | null; happy_id: string | null }>();
  if (!row) return null;
  row.happy_id = await ensurePublicUserId(db, row.id, row.happy_id);
  return row;
}

async function broadcastRoomChat(env: Env, roomId: string, payload: Record<string, unknown>): Promise<void> {
  if (!env.ROOM_CHAT) return;
  try {
    const id = env.ROOM_CHAT.idFromName(roomId);
    const stub = env.ROOM_CHAT.get(id);
    await stub.fetch("https://room-chat.internal/broadcast", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload)
    });
  } catch (error) {
    console.error("[rooms.chat-broadcast] failed", error instanceof Error ? error.message : "UnknownError");
  }
}

async function removeUserFromAllRoomSeats(env: Env, db: D1Database, userId: string): Promise<void> {
  if (!env.ROOM_SEATS) return;
  const rooms = await db.prepare("SELECT id FROM rooms WHERE status = 'active'").all<{ id: string }>();
  await Promise.all((rooms.results ?? []).map((room) => {
    const stub = env.ROOM_SEATS!.get(env.ROOM_SEATS!.idFromName(room.id));
    return stub.fetch(new Request("https://room-seats.internal/remove-user", {
      method: "POST",
      headers: { "x-target-user-id": userId }
    }));
  }));
}

async function checkAuthRateLimit(db: D1Database, ip: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const cutoff = now - AUTH_RATE_WINDOW_SECONDS;
  const row = await db.prepare(
    "INSERT INTO auth_rate_limits (ip, window_start, request_count) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET window_start = CASE WHEN auth_rate_limits.window_start <= ? THEN excluded.window_start ELSE auth_rate_limits.window_start END, request_count = CASE WHEN auth_rate_limits.window_start <= ? THEN 1 ELSE auth_rate_limits.request_count + 1 END RETURNING request_count"
  ).bind(ip, now, cutoff, cutoff).first<{ request_count: number }>();
  return Boolean(row && row.request_count <= AUTH_RATE_MAX_ATTEMPTS);
}


type AdminRole = "owner" | "admin" | "moderator";
type AdminPermission = "dashboard.read" | "reports.read" | "reports.manage" | "users.read" | "users.manage" | "users.kick" | "users.roles.manage" | "rooms.read" | "rooms.manage" | "rooms.moderate" | "audit.read" | "agora.read" | "agora.manage";
type AdminActor = { id: string; username: string; display_name: string; role: AdminRole };
const ADMIN_ROLE_PERMISSIONS: Record<Exclude<AdminRole, "owner">, ReadonlySet<AdminPermission>> = {
  admin: new Set<AdminPermission>(["dashboard.read","reports.read","reports.manage","users.read","users.manage","users.kick","rooms.read","rooms.manage","rooms.moderate","audit.read","agora.read","agora.manage"]),
  moderator: new Set<AdminPermission>(["dashboard.read","reports.read","reports.manage","users.read","rooms.read","audit.read"])
};
function hasAdminPermission(actor: AdminActor, permission: AdminPermission): boolean {
  return actor.role === "owner" || ADMIN_ROLE_PERMISSIONS[actor.role].has(permission);
}
async function authenticatedAdmin(request: Request, db: D1Database): Promise<AdminActor | null> {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
  if (!match) return null;
  const row = await db.prepare(
    "SELECT a.id, a.username, a.display_name, r.role FROM admin_sessions s INNER JOIN admin_accounts a ON a.id = s.admin_id INNER JOIN admin_account_roles r ON r.admin_id = a.id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND a.status = 'active' LIMIT 1"
  ).bind(await sha256(match[1]), new Date().toISOString()).first<{ id: string; username: string; display_name: string; role: string }>();
  if (!row || !["owner", "admin", "moderator"].includes(row.role)) return null;
  return { id: row.id, username: row.username, display_name: row.display_name, role: row.role as AdminRole };
}

async function createAdminSession(db: D1Database, adminId: string) {
  const accessToken = `${crypto.randomUUID()}.${crypto.randomUUID()}`;
  const expiresAt = new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString();
  await db.prepare("INSERT INTO admin_sessions (id, admin_id, token_hash, expires_at) VALUES (?, ?, ?, ?)")
    .bind(crypto.randomUUID(), adminId, await sha256(accessToken), expiresAt).run();
  return { accessToken, expiresAt };
}

const DEFAULT_ALLOWED_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
  "http://127.0.0.1:8080",
  "https://happy-live.pages.dev"
];

function allowedOrigins(env: Env): Set<string> {
  const configured = (env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...DEFAULT_ALLOWED_ORIGINS, ...configured]);
}

function isSafeExternalHttpsUrl(value: string): boolean {
  if (!value || value.length > 2048) return false;
  try {
    const parsed = new URL(value);
    const rawHostname = parsed.hostname.toLowerCase();
    const hostname = rawHostname.startsWith("[") ? rawHostname.slice(1, -1) : rawHostname;
    const labels = hostname.split(".");
    const isIpv4Literal = labels.length === 4 && labels.every((part) =>
      part.length > 0 && part.length <= 3 && [...part].every((char) => char >= "0" && char <= "9")
    );
    const blockedSuffix = [".localhost", ".local", ".internal", ".lan", ".home", ".test", ".invalid"];
    return parsed.protocol === "https:" &&
      parsed.username === "" && parsed.password === "" &&
      (parsed.port === "" || parsed.port === "443") &&
      !hostname.includes(":") && !isIpv4Literal &&
      hostname.includes(".") &&
      !blockedSuffix.some((suffix) => hostname.endsWith(suffix)) &&
      hostname !== "localhost" &&
      !hostname.endsWith(".");
  } catch {
    return false;
  }
}

function isValidGiftSoundUrl(value: string | null): boolean {
  if (value === null) return true;
  if (value.length > 2048) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" && /\.mp3$/i.test(parsed.pathname);
  } catch {
    return false;
  }
}

function isAllowedOrigin(origin: string, env: Env): boolean {
  if (allowedOrigins(env).has(origin)) return true;
  try {
    const parsed = new URL(origin);
    return parsed.protocol === "https:" &&
      parsed.origin === origin &&
      parsed.hostname.endsWith(".happy-live.pages.dev");
  } catch {
    return false;
  }
}

function json(data: unknown, status = 200, origin?: string, env?: Env): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });

  if (origin && env && isAllowedOrigin(origin, env)) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
    headers.set("access-control-allow-credentials", "true");
    headers.set("access-control-allow-headers", "Content-Type, Authorization");
    headers.set("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  }

  return new Response(JSON.stringify(data), { status, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") ?? undefined;

    const registeredGameOrigin = Boolean(origin && env.DB && await isRegisteredGameOrigin(env.DB, origin));
    if (origin && !isAllowedOrigin(origin, env) && !registeredGameOrigin) {
      return json({ error: "origin_not_allowed" }, 403);
    }

    if (request.method === "OPTIONS") {
      const headers = new Headers();
      if (origin) {
        headers.set("access-control-allow-origin", origin);
        headers.set("vary", "Origin");
        headers.set("access-control-allow-credentials", "true");
        headers.set("access-control-allow-headers", "Content-Type, Authorization");
        headers.set("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
      }
      return new Response(null, { status: 204, headers });
    }

    const roomToolsResponse = await handleRoomTools(
      request,
      env,
      async () => {
        if (!env.DB) return null;
        const user = await authenticatedUser(request, env.DB);
        return user ? { id: user.id, display_name: user.display_name } : null;
      },
      (data, status = 200) => json(data, status, origin, env)
    );
    if (roomToolsResponse) return roomToolsResponse;

    // Authenticated room contributor ranking. The current user is derived from
    // the session token; a query-string user_id is never trusted for self-rank.
    if (url.pathname === "/api/room/contributors") {
      if (!env.DB) return json({ ok: false, error: "database_unavailable" }, 503, origin, env);
      if (request.method !== "GET") return json({ ok: false, error: "method" }, 405, origin, env);
      try {
        const contributor = await authenticatedUser(request, env.DB);
        if (!contributor) return json({ ok: false, error: "authentication_required" }, 401, origin, env);
        return await handleRoomContrib(
          request,
          env.DB,
          contributor.id,
          (data, status = 200) => json(data, status, origin, env)
        ) ?? json({ ok: false, error: "not_found" }, 404, origin, env);
      } catch (error) {
        console.error("[room.contributors] route failed", error instanceof Error ? error.message : "UnknownError");
        return json({ ok: false, error: "contributors_unavailable" }, 500, origin, env);
      }
    }

    const platformCallbackResponse = await handlePlatformCallbackRequest(
      request,
      env.DB,
      env.UTD_APP_KEY,
      (data, status = 200) => json(data, status, undefined, env)
    );
    if (platformCallbackResponse) return platformCallbackResponse;

    // Owner-only, short-lived token accepted exclusively by UTD callbacks.
    if (url.pathname === "/api/v1/admin/utd/test-session" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedAdmin(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        if (actor.role !== "owner") return json({ error: "permission_denied" }, 403, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const uid = typeof body.uid === "string" ? body.uid.trim() : "";
        if (!uid || uid.length > 128) return json({ error: "invalid_uid" }, 400, origin, env);
        const user = await env.DB.prepare(
          "SELECT u.id FROM users u LEFT JOIN profiles p ON p.user_id=u.id WHERE u.status='active' AND (p.happy_id=? OR u.id=?) LIMIT 1"
        ).bind(uid, uid).first<{id:string}>();
        if (!user) return json({ error: "user_not_found" }, 404, origin, env);

        const accessToken = `utdtest.${crypto.randomUUID()}.${crypto.randomUUID()}`;
        const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
        const tokenHash = await sha256(accessToken);
        const saved = JSON.stringify({ user_id: user.id, token_hash: tokenHash, expires_at: expiresAt });
        await env.DB.prepare(
          "INSERT INTO platform_settings (setting_key,setting_value,updated_at) VALUES ('utd_test_session',?,?) ON CONFLICT(setting_key) DO UPDATE SET setting_value=excluded.setting_value, updated_at=excluded.updated_at"
        ).bind(saved, new Date().toISOString()).run();
        return json({ ok: true, uid, test_token: accessToken, expires_at: expiresAt, scope: "UTD callbacks only" }, 200, origin, env);
      } catch (error) {
        console.error("[utd.test-session] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "utd_test_session_unavailable" }, 503, origin, env);
      }
    }

    const gamesApiResponse = await handleGamesApiRequest(request, env, origin, authenticatedUser, json, authenticatedAdmin);
    if (gamesApiResponse) return gamesApiResponse;

    const cannonApiResponse = await handleCannonRequest(
      request, env, origin, authenticatedUser, authenticatedAdmin,
      (actor, permission) => hasAdminPermission(actor as AdminActor, permission), json
    );
    if (cannonApiResponse) return cannonApiResponse;

    // Public, read-only catalogue. Only approved active game links are listed.
    if (url.pathname === "/api/v1/games/catalog" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const rows = await env.DB!.prepare(
          "SELECT g.id, g.name, g.game_url AS url, g.icon_url AS iconUrl, g.description, g.category, g.sort_order AS sortOrder " +
          "FROM game_registry g INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE l.status = 'active' AND g.enabled = 1 AND g.game_url <> 'https://pending-game.happylive.invalid' ORDER BY g.sort_order ASC, g.created_at DESC"
        ).all();
        return json({ ok: true, games: rows.results ?? [] }, 200, origin, env);
      } catch (error) {
        console.error("[games.catalog] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "games_catalog_unavailable" }, 503, origin, env);
      }
    }

    const adminGamesRoute = url.pathname.match(/^\/api\/v1\/admin\/games(?:\/([0-9a-f-]{36}))?$/i);
    if (adminGamesRoute && ["GET", "POST", "PATCH"].includes(request.method)) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedAdmin(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        if (actor.role !== "owner" && actor.role !== "admin") return json({ error: "permission_denied" }, 403, origin, env);
        const gameId = adminGamesRoute[1];
        if (request.method === "GET") {
          const rows = await env.DB!.prepare(
            "SELECT g.id, g.name, CASE WHEN g.game_url = 'https://pending-game.happylive.invalid' THEN '' ELSE g.game_url END AS url, g.icon_url AS iconUrl, g.description, g.category, COALESCE(l.status, 'disabled') AS status, g.enabled, g.sort_order AS sortOrder, g.created_at AS createdAt, g.updated_at AS updatedAt " +
            "FROM game_registry g LEFT JOIN game_registry_lifecycle l ON l.game_id = g.id ORDER BY g.sort_order ASC, g.created_at DESC"
          ).all();
          return json({ ok: true, games: rows.results ?? [] }, 200, origin, env);
        }
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        if (request.method === "POST") {
          const name = typeof body.name === "string" ? body.name.trim() : "";
          const requestedUrl = typeof body.url === "string" ? body.url.trim() : "";
          const gameUrl = requestedUrl || "https://pending-game.happylive.invalid";
          const iconUrl = typeof body.iconUrl === "string" ? body.iconUrl.trim() : "";
          const description = typeof body.description === "string" ? body.description.trim() : "";
          const category = typeof body.category === "string" ? body.category.trim() : "عام";
          const status = typeof body.status === "string" ? body.status : "development";
          const sortOrder = Number.isInteger(body.sortOrder) ? Number(body.sortOrder) : 0;
          if (name.length < 2 || name.length > 80 || (requestedUrl && !isSafeExternalHttpsUrl(gameUrl)) ||
              !["development", "disabled", "active"].includes(status) || (status === "active" && !requestedUrl) ||
              description.length > 240 || category.length < 1 || category.length > 40 ||
              (iconUrl && !isSafeExternalHttpsUrl(iconUrl)) || sortOrder < 0 || sortOrder > 9999) {
            return json({ error: "invalid_game_data", message: "تحقق من الاسم والرابط HTTPS وحالة اللعبة والوصف والأيقونة." }, 400, origin, env);
          }
          const now = new Date().toISOString();
          const id = crypto.randomUUID();
          const enabled = status === "active" ? 1 : 0;
          await env.DB!.batch([
            env.DB!.prepare("INSERT INTO game_registry (id, name, game_url, icon_url, description, category, enabled, sort_order, created_by_admin_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").bind(id, name, gameUrl, iconUrl || null, description, category, enabled, sortOrder, actor.id, now, now),
            env.DB!.prepare("INSERT INTO game_registry_lifecycle (game_id, status, updated_at) VALUES (?, ?, ?)").bind(id, status, now),
            env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'games.create', 'game', ?, ?, ?)").bind(crypto.randomUUID(), id, JSON.stringify({ adminId: actor.id, adminUsername: actor.username, name, status }), now)
          ]);
          return json({ ok: true, game: { id, name, url: requestedUrl, iconUrl: iconUrl || null, description, category, status, enabled, sortOrder } }, 201, origin, env);
        }
        if (!gameId) return json({ error: "game_id_required" }, 400, origin, env);
        const current = await env.DB!.prepare("SELECT g.id, g.game_url, COALESCE(l.status, 'disabled') AS status FROM game_registry g LEFT JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE g.id = ? LIMIT 1").bind(gameId).first<{ id: string; game_url: string; status: string }>();
        if (!current) return json({ error: "game_not_found" }, 404, origin, env);
        const name = typeof body.name === "string" ? body.name.trim() : null;
        const requestedUrl = typeof body.url === "string" ? body.url.trim() : null;
        const gameUrl = requestedUrl === null ? null : (requestedUrl || "https://pending-game.happylive.invalid");
        const iconUrl = typeof body.iconUrl === "string" ? body.iconUrl.trim() : null;
        const description = typeof body.description === "string" ? body.description.trim() : null;
        const category = typeof body.category === "string" ? body.category.trim() : null;
        const requestedStatus = typeof body.status === "string" ? body.status : null;
        const legacyEnabled = typeof body.enabled === "boolean" ? (body.enabled ? 1 : 0) : null;
        const status = requestedStatus ?? (legacyEnabled === null ? null : (legacyEnabled ? "active" : "disabled"));
        const effectiveStatus = status ?? current.status;
        const effectiveUrl = gameUrl ?? current.game_url;
        const sortOrder = Number.isInteger(body.sortOrder) ? Number(body.sortOrder) : null;
        if (name !== null && (name.length < 2 || name.length > 80)) return json({ error: "invalid_game_name" }, 400, origin, env);
        if (gameUrl !== null && gameUrl !== "https://pending-game.happylive.invalid" && !isSafeExternalHttpsUrl(gameUrl)) return json({ error: "invalid_game_url" }, 400, origin, env);
        if (status !== null && !["development", "disabled", "active"].includes(status)) return json({ error: "invalid_game_status" }, 400, origin, env);
        if (effectiveStatus === "active" && (effectiveUrl === "https://pending-game.happylive.invalid" || !isSafeExternalHttpsUrl(effectiveUrl))) return json({ error: "game_url_required_before_activation" }, 400, origin, env);
        if (iconUrl !== null && iconUrl && !isSafeExternalHttpsUrl(iconUrl)) return json({ error: "invalid_icon_url" }, 400, origin, env);
        if (sortOrder !== null && (sortOrder < 0 || sortOrder > 9999)) return json({ error: "invalid_sort_order" }, 400, origin, env);
        if (description !== null && description.length > 240) return json({ error: "invalid_description" }, 400, origin, env);
        if (category !== null && (category.length < 1 || category.length > 40)) return json({ error: "invalid_category" }, 400, origin, env);
        const updatedAt = new Date().toISOString();
        const enabled = status === null ? null : (status === "active" ? 1 : 0);
        await env.DB!.batch([
          env.DB!.prepare("UPDATE game_registry SET name = COALESCE(?, name), game_url = COALESCE(?, game_url), icon_url = COALESCE(?, icon_url), description = COALESCE(?, description), category = COALESCE(?, category), enabled = COALESCE(?, enabled), sort_order = COALESCE(?, sort_order), updated_at = ? WHERE id = ?").bind(name, gameUrl, iconUrl, description, category, enabled, sortOrder, updatedAt, gameId),
          env.DB!.prepare("UPDATE game_registry_lifecycle SET status = COALESCE(?, status), updated_at = ? WHERE game_id = ?").bind(status, updatedAt, gameId),
          env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'games.update', 'game', ?, ?, ?)").bind(crypto.randomUUID(), gameId, JSON.stringify({ adminId: actor.id, adminUsername: actor.username, changed: { name, url: requestedUrl, iconUrl, description, category, status, sortOrder } }), updatedAt)
        ]);
        return json({ ok: true }, 200, origin, env);
      } catch (error) {
        console.error("[admin.games] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_games_unavailable" }, 503, origin, env);
      }
    }
    if (url.pathname === "/api/v1/admin/auth/setup-status" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const state = await env.DB!.prepare("SELECT id FROM admin_setup_state WHERE id = 'primary-owner' LIMIT 1").first();
      return json({ setupRequired: !state }, 200, origin, env);
    }

    if (url.pathname === "/api/v1/admin/auth/setup" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      if (!env.ADMIN_SETUP_TOKEN) return json({ error: "admin_setup_not_configured" }, 503, origin, env);
      try {
        const state = await env.DB!.prepare("SELECT id FROM admin_setup_state WHERE id = 'primary-owner' LIMIT 1").first();
        if (state) return json({ error: "admin_setup_already_completed" }, 409, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const suppliedToken = typeof body.setupToken === "string" ? body.setupToken : "";
        const password = typeof body.password === "string" ? body.password : "";
        const confirmation = typeof body.confirmation === "string" ? body.confirmation : "";
        if (!constantTimeTextEqual(await sha256(suppliedToken), await sha256(env.ADMIN_SETUP_TOKEN))) {
          return json({ error: "invalid_setup_token", message: "رمز التهيئة غير صحيح" }, 403, origin, env);
        }
        if (password.length < 12 || password.length > 128 || password !== confirmation) {
          return json({ error: "invalid_password", message: "استخدم كلمة مرور من 12 حرفًا على الأقل وتأكد من تطابق الحقلين" }, 400, origin, env);
        }
        const owner = await env.DB!.prepare("SELECT id FROM admin_accounts WHERE username = 'owner' COLLATE NOCASE AND status = 'active' LIMIT 1")
          .first<{ id: string }>();
        if (!owner) return json({ error: "primary_admin_not_found" }, 404, origin, env);
        const nonce = crypto.randomUUID();
        const now = new Date().toISOString();
        const passwordHash = await hashPassword(password);
        const results = await env.DB!.batch([
          env.DB!.prepare("INSERT OR IGNORE INTO admin_setup_state (id, setup_nonce, completed_at) VALUES ('primary-owner', ?, ?)")
            .bind(nonce, now),
          env.DB!.prepare("UPDATE admin_accounts SET password_hash = ?, updated_at = ? WHERE id = ? AND EXISTS (SELECT 1 FROM admin_setup_state WHERE id = 'primary-owner' AND setup_nonce = ?)")
            .bind(passwordHash, now, owner.id, nonce),
          env.DB!.prepare("UPDATE admin_sessions SET revoked_at = ? WHERE admin_id = ? AND revoked_at IS NULL")
            .bind(now, owner.id)
        ]);
        if ((results[1]?.meta?.changes ?? 0) !== 1) {
          return json({ error: "admin_setup_already_completed", message: "تم إعداد كلمة مرور المدير مسبقًا" }, 409, origin, env);
        }
        return json({ ok: true, message: "تم إنشاء كلمة مرور المدير الرئيسي بنجاح" }, 200, origin, env);
      } catch (error) {
        console.error("[admin.auth.setup] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_setup_unavailable" }, 503, origin, env);
      }
    }

    if (url.pathname === "/api/v1/admin/auth/login" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      try {
        if (!(await checkAuthRateLimit(env.DB, "admin:" + ip))) return json({ error: "rate_limit_exceeded" }, 429, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const username = typeof body.username === "string" ? body.username.trim().toLowerCase().slice(0, 80) : "";
        const password = typeof body.password === "string" ? body.password : "";
        if (!username || password.length < 1 || password.length > 256) return json({ error: "invalid_credentials" }, 401, origin, env);
        const account = await env.DB!.prepare("SELECT id, password_hash FROM admin_accounts WHERE username = ? COLLATE NOCASE AND status = 'active' LIMIT 1")
          .bind(username).first<{ id: string; password_hash: string }>();
        if (!account || !(await verifyPassword(password, account.password_hash))) return json({ error: "invalid_credentials", message: "اسم المستخدم أو كلمة المرور غير صحيحة" }, 401, origin, env);
        const session = await createAdminSession(env.DB, account.id);
        return json({ ok: true, ...session }, 200, origin, env);
      } catch (error) {
        console.error("[admin.auth.login] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_login_unavailable" }, 503, origin, env);
      }
    }
    if (url.pathname === "/api/v1/admin/auth/logout" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const authorization = request.headers.get("Authorization") ?? "";
      const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
      if (match) await env.DB!.prepare("UPDATE admin_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
        .bind(new Date().toISOString(), await sha256(match[1])).run();
      return json({ ok: true }, 200, origin, env);
    }

    if (url.pathname === "/api/v1/admin/reports/rooms" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const admin = await authenticatedAdmin(request, env.DB);
        if (!admin) return json({ error: "authentication_required" }, 401, origin, env);
        if (!hasAdminPermission(admin, "reports.read")) return json({ error: "permission_denied" }, 403, origin, env);
        const status = url.searchParams.get("status") || "pending";
        if (!["pending", "reviewed", "dismissed", "all"].includes(status)) return json({ error: "invalid_report_status" }, 400, origin, env);
        const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 50), 1), 100);
        const rows = await env.DB!.prepare(
          "SELECT r.id, r.room_code, r.room_name, r.targets_json, r.violation, r.status, r.created_at, r.reviewed_at, " +
          "p.display_name AS reporter_name, p.happy_id AS reporter_code, a.display_name AS reviewer_name " +
          "FROM room_profile_reports r LEFT JOIN profiles p ON p.user_id = r.reporter_id LEFT JOIN admin_accounts a ON a.id = r.reviewed_by " +
          (status === "all" ? "" : "WHERE r.status = ? ") + "ORDER BY r.created_at DESC LIMIT ?"
        ).bind(...(status === "all" ? [limit] : [status, limit])).all();
        return json({ ok: true, reports: rows.results ?? [] }, 200, origin, env);
      } catch (error) {
        console.error("[admin.room-reports.list] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_reports_unavailable" }, 500, origin, env);
      }
    }

    const roomReportStatusRoute = url.pathname.match(/^\/api\/v1\/admin\/reports\/rooms\/([0-9a-f-]{36})\/status$/i);
    if (roomReportStatusRoute && request.method === "PATCH") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const admin = await authenticatedAdmin(request, env.DB);
        if (!admin) return json({ error: "authentication_required" }, 401, origin, env);
        if (!hasAdminPermission(admin, "reports.manage")) return json({ error: "permission_denied" }, 403, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const status = typeof body.status === "string" ? body.status : "";
        if (!["reviewed", "dismissed"].includes(status)) return json({ error: "invalid_report_status" }, 400, origin, env);
        const result = await env.DB!.prepare("UPDATE room_profile_reports SET status = ?, reviewed_at = ?, reviewed_by = ? WHERE id = ?")
          .bind(status, new Date().toISOString(), admin.id, roomReportStatusRoute[1]).run();
        if ((result.meta?.changes ?? 0) === 0) return json({ error: "report_not_found" }, 404, origin, env);
        return json({ ok: true, status }, 200, origin, env);
      } catch (error) {
        console.error("[admin.room-reports.update] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_report_update_failed" }, 500, origin, env);
      }
    }

    // Public PK presentation settings; all mutations remain owner-only in the admin route.
    if (url.pathname === "/api/v1/pk/settings" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const row = await env.DB.prepare("SELECT setting_value FROM platform_settings WHERE setting_key = 'pk_battle_settings' LIMIT 1")
          .first<{ setting_value: string }>();
        let saved: Record<string, unknown> = {};
        try { saved = row?.setting_value ? JSON.parse(row.setting_value) as Record<string, unknown> : {}; } catch { saved = {}; }
        const defaults = { enabled: true, challengeTitle: "تحدي PK", mediaUrl: "", mediaType: "", showChallengeTitle: true, showStartText: true, showTimer: true, squareRadius: 26, squareWidthPercent: 100, squareHeight: 284, mediaOpacity: 85, durationOptions: [5, 15, 30, 120], defaultDurationMinutes: 5, startMediaUrl: "", startMediaType: "", startShowDurationSeconds: 3, startHideDurationSeconds: 0.5 };
        const options = Array.isArray(saved.durationOptions) ? saved.durationOptions : defaults.durationOptions;
        return json({ ok: true, settings: { ...defaults, ...saved, durationOptions: options } }, 200, origin, env);
      } catch (error) {
        console.error("[pk.settings.public] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "pk_settings_unavailable" }, 500, origin, env);
      }
    }

    // Admin API: authentication uses a separate admin-only session table.
    if (
      url.pathname === "/api/v1/admin/me" ||
      url.pathname === "/api/v1/admin/overview" ||
      url.pathname === "/api/v1/admin/stats" ||
      url.pathname === "/api/v1/admin/users" ||
      url.pathname === "/api/v1/admin/wallets" ||
      url.pathname === "/api/v1/admin/pk/settings" ||
      url.pathname === "/api/v1/admin/gifts/settings" ||
      url.pathname === "/api/v1/admin/gifts/banner-settings" ||
      url.pathname === "/api/v1/admin/gifts/catalog" ||
      url.pathname === "/api/v1/admin/gifts/custom-requests" ||
      /^\/api\/v1\/admin\/gifts\/custom-requests\/[0-9a-f-]{36}$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/gifts\/catalog\/[a-z0-9-]{1,80}$/i.test(url.pathname) ||
      url.pathname === "/api/v1/admin/moderators" ||
      url.pathname === "/api/v1/admin/rooms" ||
      /^\/api\/v1\/admin\/rooms\/[0-9a-f-]{36}\/level$/i.test(url.pathname) ||
      url.pathname === "/api/v1/admin/audit" ||
      url.pathname === "/api/v1/admin/agora/status" ||
      url.pathname === "/api/v1/admin/agora/voice" ||
      url.pathname === "/api/v1/admin/integrations/happy-food-wheel" ||
      /^\/api\/v1\/admin\/users\/[0-9a-f-]{36}\/status$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/users\/[0-9a-f-]{36}\/kick$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/users\/[0-9a-f-]{36}\/role$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/users\/[0-9a-f-]{36}\/wallet\/credit$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/rooms\/[0-9a-f-]{36}\/status$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/rooms\/[0-9a-f-]{36}\/moderation$/i.test(url.pathname)
    ) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedAdmin(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        if (url.pathname === "/api/v1/admin/pk/settings" && (request.method === "GET" || request.method === "PATCH")) {
          if (actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const defaults = {
            enabled: true, challengeTitle: "تحدي PK", mediaUrl: "", mediaType: "",
            showChallengeTitle: true, showStartText: true, showTimer: true,
            squareRadius: 26, mediaOpacity: 85, durationOptions: [5, 15, 30, 120],
            defaultDurationMinutes: 5, startMediaUrl: "", startMediaType: "",
            startShowDurationSeconds: 3, startHideDurationSeconds: 0.5,
            normalMicBorderColor: "#FFFFFF", normalMicBorderWidth: 1.5, normalMicFillColor: "#FFFFFF", normalMicFillOpacity: 14,
            pkMicBorderColor: "#FFFFFF", pkMicBorderWidth: 2.4, pkMicFillColor: "#FFFFFF", pkMicFillOpacity: 12,
            pkBlueMicBorderColor: "#258BFF", pkRedMicBorderColor: "#FF4B5C"
          };
          const readSettings = async () => {
            const row = await env.DB!.prepare(
              "SELECT setting_value FROM platform_settings WHERE setting_key = 'pk_battle_settings' LIMIT 1"
            ).first<{ setting_value: string }>();
            let saved: Record<string, unknown> = {};
            try { saved = row?.setting_value ? JSON.parse(row.setting_value) as Record<string, unknown> : {}; } catch { saved = {}; }
            return { ...defaults, ...saved };
          };
          if (request.method === "GET") {
            const settings = await readSettings();
            return json({ ok: true, settings }, 200, origin, env);
          }
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const current = await readSettings();
          const enabled = body.enabled === undefined ? current.enabled === true : body.enabled;
          const challengeTitle = body.challengeTitle === undefined ? String(current.challengeTitle ?? defaults.challengeTitle) : typeof body.challengeTitle === "string" ? body.challengeTitle.trim() : "";
          const mediaUrl = body.mediaUrl === undefined ? String(current.mediaUrl ?? "") : typeof body.mediaUrl === "string" ? body.mediaUrl.trim() : "";
          const mediaType = body.mediaType === undefined ? String(current.mediaType ?? "") : typeof body.mediaType === "string" ? body.mediaType.toLowerCase() : "";
          const showChallengeTitle = body.showChallengeTitle === undefined ? current.showChallengeTitle === true : body.showChallengeTitle;
          const showStartText = body.showStartText === undefined ? current.showStartText === true : body.showStartText;
          const showTimer = body.showTimer === undefined ? current.showTimer === true : body.showTimer;
          const squareRadius = body.squareRadius === undefined ? Number(current.squareRadius) : Number(body.squareRadius);
          const squareWidthPercent = body.squareWidthPercent === undefined ? Number(current.squareWidthPercent ?? 100) : Number(body.squareWidthPercent);
          const squareHeight = body.squareHeight === undefined ? Number(current.squareHeight ?? 284) : Number(body.squareHeight);
          const mediaOpacity = body.mediaOpacity === undefined ? Number(current.mediaOpacity) : Number(body.mediaOpacity);
          const durationOptions = body.durationOptions === undefined ? current.durationOptions : body.durationOptions;
          const defaultDurationMinutes = body.defaultDurationMinutes === undefined ? Number(current.defaultDurationMinutes) : Number(body.defaultDurationMinutes);
          const startMediaUrl = body.startMediaUrl === undefined ? String(current.startMediaUrl ?? "") : typeof body.startMediaUrl === "string" ? body.startMediaUrl.trim() : "";
          const startMediaType = body.startMediaType === undefined ? String(current.startMediaType ?? "") : typeof body.startMediaType === "string" ? body.startMediaType.toLowerCase() : "";
          const startShowDurationSeconds = body.startShowDurationSeconds === undefined ? Number(current.startShowDurationSeconds ?? 3) : Number(body.startShowDurationSeconds);
          const startHideDurationSeconds = body.startHideDurationSeconds === undefined ? Number(current.startHideDurationSeconds ?? 0.5) : Number(body.startHideDurationSeconds);
          const normalMicBorderColor = body.normalMicBorderColor === undefined ? String(current.normalMicBorderColor ?? "#FFFFFF") : String(body.normalMicBorderColor);
          const normalMicBorderWidth = body.normalMicBorderWidth === undefined ? Number(current.normalMicBorderWidth ?? 1.5) : Number(body.normalMicBorderWidth);
          const normalMicFillColor = body.normalMicFillColor === undefined ? String(current.normalMicFillColor ?? "#FFFFFF") : String(body.normalMicFillColor);
          const normalMicFillOpacity = body.normalMicFillOpacity === undefined ? Number(current.normalMicFillOpacity ?? 14) : Number(body.normalMicFillOpacity);
          const pkMicBorderColor = body.pkMicBorderColor === undefined ? String(current.pkMicBorderColor ?? "#FFFFFF") : String(body.pkMicBorderColor);
          const pkMicBorderWidth = body.pkMicBorderWidth === undefined ? Number(current.pkMicBorderWidth ?? 2.4) : Number(body.pkMicBorderWidth);
          const pkMicFillColor = body.pkMicFillColor === undefined ? String(current.pkMicFillColor ?? "#FFFFFF") : String(body.pkMicFillColor);
          const pkMicFillOpacity = body.pkMicFillOpacity === undefined ? Number(current.pkMicFillOpacity ?? 12) : Number(body.pkMicFillOpacity);
          const pkBlueMicBorderColor = body.pkBlueMicBorderColor === undefined ? String(current.pkBlueMicBorderColor ?? "#258BFF") : String(body.pkBlueMicBorderColor);
          const pkRedMicBorderColor = body.pkRedMicBorderColor === undefined ? String(current.pkRedMicBorderColor ?? "#FF4B5C") : String(body.pkRedMicBorderColor);
          if (typeof enabled !== "boolean" || typeof showChallengeTitle !== "boolean" || typeof showStartText !== "boolean" || typeof showTimer !== "boolean" ||
              !challengeTitle || challengeTitle.length > 80 || (mediaUrl && (mediaUrl.length > 2048 || !/^https:\/\//i.test(mediaUrl))) ||
              !["", "gif", "svga"].includes(mediaType) || (mediaUrl && !mediaType) || (!mediaUrl && mediaType) ||
              !Number.isInteger(squareRadius) || squareRadius < 0 || squareRadius > 60 ||
              !Number.isInteger(squareWidthPercent) || squareWidthPercent < 50 || squareWidthPercent > 100 ||
              !Number.isInteger(squareHeight) || squareHeight < 240 || squareHeight > 500 ||
              !Number.isInteger(mediaOpacity) || mediaOpacity < 0 || mediaOpacity > 100 ||
              !Array.isArray(durationOptions) || durationOptions.length < 1 || durationOptions.length > 8 ||
              durationOptions.some((value) => !Number.isInteger(value) || Number(value) < 1 || Number(value) > 120) ||
              new Set(durationOptions).size !== durationOptions.length ||
              !Number.isInteger(defaultDurationMinutes) || !durationOptions.includes(defaultDurationMinutes) ||
              (startMediaUrl && (startMediaUrl.length > 2048 || !/^https:\/\//i.test(startMediaUrl))) ||
              !["", "gif", "svga"].includes(startMediaType) || (startMediaUrl && !startMediaType) || (!startMediaUrl && startMediaType) ||
              !Number.isFinite(startShowDurationSeconds) || startShowDurationSeconds < 1 || startShowDurationSeconds > 30 ||
              !Number.isFinite(startHideDurationSeconds) || startHideDurationSeconds < 0 || startHideDurationSeconds > 5 ||
              !/^#[0-9a-f]{6}$/i.test(normalMicBorderColor) || !Number.isFinite(normalMicBorderWidth) || normalMicBorderWidth < 0 || normalMicBorderWidth > 8 ||
              !/^#[0-9a-f]{6}$/i.test(normalMicFillColor) || !Number.isInteger(normalMicFillOpacity) || normalMicFillOpacity < 0 || normalMicFillOpacity > 100 ||
              !/^#[0-9a-f]{6}$/i.test(pkMicBorderColor) || !Number.isFinite(pkMicBorderWidth) || pkMicBorderWidth < 0 || pkMicBorderWidth > 8 ||
              !/^#[0-9a-f]{6}$/i.test(pkMicFillColor) || !Number.isInteger(pkMicFillOpacity) || pkMicFillOpacity < 0 || pkMicFillOpacity > 100 ||
              !/^#[0-9a-f]{6}$/i.test(pkBlueMicBorderColor) || !/^#[0-9a-f]{6}$/i.test(pkRedMicBorderColor)) {
            return json({ error: "invalid_pk_settings", message: "تحقق من إعدادات PK والمدد والوسائط." }, 400, origin, env);
          }
          const settings = { enabled, challengeTitle, mediaUrl, mediaType, showChallengeTitle, showStartText, showTimer, squareRadius, squareWidthPercent, squareHeight, mediaOpacity, durationOptions, defaultDurationMinutes, startMediaUrl, startMediaType, startShowDurationSeconds, startHideDurationSeconds, normalMicBorderColor, normalMicBorderWidth, normalMicFillColor, normalMicFillOpacity, pkMicBorderColor, pkMicBorderWidth, pkMicFillColor, pkMicFillOpacity, pkBlueMicBorderColor, pkRedMicBorderColor };
          const now = new Date().toISOString();
          await env.DB!.prepare(
            "INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('pk_battle_settings', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at"
          ).bind(JSON.stringify(settings), now).run();
          await env.DB!.prepare(
            "INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'pk.settings.update', 'platform', 'pk_battle_settings', ?, ?)"
          ).bind(crypto.randomUUID(), JSON.stringify({ adminId: actor.id, adminUsername: actor.username }), now).run();
          return json({ ok: true, settings }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/integrations/happy-food-wheel") {
          if (actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          if (request.method === "GET") {
            const rows = await env.DB!.prepare(
              "SELECT setting_key, setting_value FROM platform_settings WHERE setting_key IN ('happy_food_wheel_app_id', 'happy_food_wheel_token_hash', 'happy_food_wheel_token_prefix', 'happy_food_wheel_created_at')"
            ).all<{ setting_key: string; setting_value: string }>();
            const settings = new Map((rows.results ?? []).map((row) => [row.setting_key, row.setting_value]));
            const appId = settings.get("happy_food_wheel_app_id") ?? "";
            const tokenPrefix = settings.get("happy_food_wheel_token_prefix") ?? "";
            const createdAt = settings.get("happy_food_wheel_created_at") ?? "";
            const tokenConfigured = settings.has("happy_food_wheel_token_hash");
            return json({
              ok: true,
              configured: tokenConfigured,
              tokenConfigured,
              appIdBound: Boolean(appId),
              appId,
              tokenPrefix,
              createdAt,
              apiBaseUrl: "https://happy-live-api.taher616270.workers.dev",
              callbackBaseUrl: "https://happy-live-api.taher616270.workers.dev"
            }, 200, origin, env);
          }
          if (request.method === "POST") {
            let body: Record<string, unknown>;
            try { body = await request.json() as Record<string, unknown>; }
            catch { return json({ error: "invalid_json" }, 400, origin, env); }
            // Issue the credential before the external platform has assigned its App ID.
            // The first authenticated handshake will bind the App ID to this token.
            const apiToken = "hfw_live_" + crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
            const tokenHash = await sha256(apiToken);
            const tokenPrefix = apiToken.slice(0, 17);
            const now = new Date().toISOString();
            await env.DB!.batch([
              env.DB!.prepare("DELETE FROM platform_settings WHERE setting_key = 'happy_food_wheel_app_id'"),
              env.DB!.prepare("INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('happy_food_wheel_token_hash', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at").bind(tokenHash, now),
              env.DB!.prepare("INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('happy_food_wheel_token_prefix', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at").bind(tokenPrefix, now),
              env.DB!.prepare("INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('happy_food_wheel_created_at', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at").bind(now, now)
            ]);
            return json({
              ok: true,
              appId: "",
              apiToken,
              tokenPrefix,
              createdAt: now,
              apiBaseUrl: "https://happy-live-api.taher616270.workers.dev",
              callbackBaseUrl: "https://happy-live-api.taher616270.workers.dev"
            }, 201, origin, env);
          }
          if (request.method === "DELETE") {
            await env.DB!.batch([
              env.DB!.prepare("DELETE FROM platform_settings WHERE setting_key = 'happy_food_wheel_app_id'"),
              env.DB!.prepare("DELETE FROM platform_settings WHERE setting_key = 'happy_food_wheel_token_hash'"),
              env.DB!.prepare("DELETE FROM platform_settings WHERE setting_key = 'happy_food_wheel_token_prefix'"),
              env.DB!.prepare("DELETE FROM platform_settings WHERE setting_key = 'happy_food_wheel_created_at'")
            ]);
            return json({ ok: true }, 200, origin, env);
          }
          return json({ error: "method_not_allowed" }, 405, origin, env);
        }
        if (url.pathname === "/api/v1/admin/gifts/settings" && (request.method === "GET" || request.method === "PATCH")) {
          if (actor.role !== "owner" && actor.role !== "admin") return json({ error: "permission_denied" }, 403, origin, env);
          if (request.method === "PATCH" && actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          if (request.method === "GET") {
            const [settings, withdrawal, totals] = await Promise.all([
              env.DB!.prepare("SELECT app_percent AS appPercent, recipient_percent AS recipientPercent, updated_at AS updatedAt FROM gift_revenue_settings WHERE id = 'current'").first<Record<string, unknown>>(),
              env.DB!.prepare("SELECT enabled, agency_integration_ready AS agencyIntegrationReady, minimum_coins AS minimumCoins FROM gift_withdrawal_settings WHERE id = 'current'").first<Record<string, unknown>>(),
              env.DB!.prepare("SELECT COUNT(*) AS giftCount, COALESCE(SUM(coin_cost), 0) AS totalGiftCoins, COALESCE(SUM(app_coins), 0) AS appCoins, COALESCE(SUM(recipient_coins), 0) AS recipientCoins FROM gift_transactions WHERE status = 'succeeded'").first<Record<string, unknown>>()
            ]);
            return json({
              ok: true,
              settings: settings ?? { appPercent: 30, recipientPercent: 70 },
              withdrawals: { ...(withdrawal ?? {}), enabled: false, agencyIntegrationReady: false, ready: false },
              totals: totals ?? { giftCount: 0, totalGiftCoins: 0, appCoins: 0, recipientCoins: 0 }
            }, 200, origin, env);
          }
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const appPercent = Number(body.appPercent);
          const recipientPercent = Number(body.recipientPercent);
          if (!Number.isInteger(appPercent) || !Number.isInteger(recipientPercent) || appPercent < 0 || appPercent > 100 || recipientPercent < 0 || recipientPercent > 100 || appPercent + recipientPercent !== 100) {
            return json({ error: "invalid_revenue_split", message: "يجب أن تكون النسب أعدادًا صحيحة ومجموعها 100%" }, 400, origin, env);
          }
          const current = await env.DB!.prepare("SELECT app_percent, recipient_percent FROM gift_revenue_settings WHERE id = 'current'").first<{ app_percent: number; recipient_percent: number }>();
          if (!current) return json({ error: "gift_settings_not_initialized" }, 503, origin, env);
          const now = new Date().toISOString();
          const auditId = crypto.randomUUID();
          const results = await env.DB!.batch([
            env.DB!.prepare("UPDATE gift_revenue_settings SET app_percent = ?, recipient_percent = ?, updated_by_admin_id = ?, updated_at = ? WHERE id = 'current' AND app_percent = ? AND recipient_percent = ?")
              .bind(appPercent, recipientPercent, actor.id, now, current.app_percent, current.recipient_percent),
            env.DB!.prepare(
              "INSERT INTO gift_revenue_settings_audit (id, admin_id, old_app_percent, old_recipient_percent, new_app_percent, new_recipient_percent, created_at) " +
              "SELECT ?, ?, ?, ?, ?, ?, ? FROM gift_revenue_settings WHERE id = 'current' AND app_percent = ? AND recipient_percent = ? AND updated_by_admin_id = ? AND updated_at = ?"
            ).bind(auditId, actor.id, current.app_percent, current.recipient_percent, appPercent, recipientPercent, now, appPercent, recipientPercent, actor.id, now)
          ]);
          if ((results[0]?.meta?.changes ?? 0) !== 1) return json({ error: "gift_settings_conflict", message: "تم تعديل النسب بالتزامن. حدّث الصفحة وحاول مجددًا." }, 409, origin, env);
          return json({ ok: true, settings: { appPercent, recipientPercent, updatedAt: now } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/gifts/banner-settings" && (request.method === "GET" || request.method === "PATCH")) {
          if (actor.role !== "owner" && actor.role !== "admin") return json({ error: "permission_denied" }, 403, origin, env);
          if (request.method === "GET") {
            const settings = await env.DB!.prepare(
              "SELECT enabled, minimum_coins AS minimumCoins, updated_at AS updatedAt FROM gift_banner_settings WHERE id = 'current'"
            ).first<Record<string, unknown>>();
            return json({ ok: true, settings: settings ?? { enabled: 0, minimumCoins: 0, updatedAt: null } }, 200, origin, env);
          }
          if (actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const enabled = body.enabled === true || body.enabled === 1;
          const minimumCoins = Number(body.minimumCoins);
          if (!Number.isSafeInteger(minimumCoins) || minimumCoins < 0 || minimumCoins > 1000000000) {
            return json({ error: "invalid_banner_minimum", message: "أدخل حدًا صحيحًا من 0 إلى مليار كوينز" }, 400, origin, env);
          }
          const now = new Date().toISOString();
          await env.DB!.prepare(
            "INSERT INTO gift_banner_settings (id, enabled, minimum_coins, updated_by_admin_id, updated_at) VALUES ('current', ?, ?, ?, ?) " +
            "ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled, minimum_coins = excluded.minimum_coins, updated_by_admin_id = excluded.updated_by_admin_id, updated_at = excluded.updated_at"
          ).bind(enabled ? 1 : 0, minimumCoins, actor.id, now).run();
          return json({ ok: true, settings: { enabled, minimumCoins, updatedAt: now } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/gifts/catalog" || /^\/api\/v1\/admin\/gifts\/catalog\/[a-z0-9-]{1,80}$/i.test(url.pathname)) {
          if (actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const itemRoute = url.pathname.match(/^\/api\/v1\/admin\/gifts\/catalog\/([a-z0-9-]{1,80})$/i);
          if (request.method === "GET" && !itemRoute) {
            const rows = await env.DB!.prepare("SELECT id, name, icon_emoji AS iconEmoji, media_url AS mediaUrl, media_type AS mediaType, thumbnail_url AS thumbnailUrl, sound_url AS soundUrl, duration_seconds AS durationSeconds, coin_price AS coinPrice, is_active AS isActive, sort_order AS sortOrder, category, country_code AS countryCode, starts_at AS startsAt, ends_at AS endsAt, created_at AS createdAt, updated_at AS updatedAt FROM gift_catalog ORDER BY category ASC, sort_order ASC, created_at ASC").all();
            return json({ ok: true, gifts: rows.results ?? [] }, 200, origin, env);
          }
          if (request.method === "POST" && !itemRoute) {
            let body: Record<string, unknown>;
            try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
            const name = typeof body.name === "string" ? body.name.trim() : "";
            const iconEmoji = typeof body.iconEmoji === "string" ? body.iconEmoji.trim() : "🎁";
            const coinPrice = Number(body.coinPrice);
            const sortOrder = Number(body.sortOrder ?? 0);
            const isActive = body.isActive === false ? 0 : 1;
            const category = typeof body.category === "string" ? body.category : "trending";
            const countryCode = typeof body.countryCode === "string" && body.countryCode.trim() ? body.countryCode.trim().toUpperCase() : null;
            const startsAt = typeof body.startsAt === "string" && body.startsAt ? body.startsAt : null;
            const endsAt = typeof body.endsAt === "string" && body.endsAt ? body.endsAt : null;
            const mediaUrl = typeof body.mediaUrl === "string" && body.mediaUrl.trim() ? body.mediaUrl.trim() : null;
            const thumbnailUrl = typeof body.thumbnailUrl === "string" && body.thumbnailUrl.trim() ? body.thumbnailUrl.trim() : null;
            const mediaType = mediaUrl ? String(body.mediaType ?? "").toLowerCase() : "emoji";
            const soundUrl = typeof body.soundUrl === "string" && body.soundUrl.trim() ? body.soundUrl.trim() : null;
            const durationSeconds = Number(body.durationSeconds ?? 5);
            if (!Number.isFinite(durationSeconds) || durationSeconds < 0.1 || durationSeconds > 60) return json({ error: "invalid_gift_duration", message: "مدة حركة الهدية يجب أن تكون من 1 إلى 60 ثانية." }, 400, origin, env);
            if (!isValidGiftSoundUrl(soundUrl)) return json({ error: "invalid_gift_sound", message: "ملف الصوت يجب أن يكون MP3 برابط HTTPS." }, 400, origin, env);
            if ((mediaUrl && (mediaUrl.length > 2048 || !/^https:\/\//i.test(mediaUrl))) || (thumbnailUrl && (thumbnailUrl.length > 2048 || !/^https:\/\//i.test(thumbnailUrl))) || !["emoji", "svga", "gif", "pag", "apng", "webp"].includes(mediaType) || (mediaUrl && mediaType === "emoji") || (!mediaUrl && mediaType !== "emoji")) return json({ error: "invalid_gift_media", message: "رابط الوسائط يجب أن يكون HTTPS ونوعه SVGA أو GIF أو PAG أو APNG أو WEBP." }, 400, origin, env);
            if (!name || name.length > 80 || !iconEmoji || iconEmoji.length > 16 || !Number.isSafeInteger(coinPrice) || coinPrice < 1 || coinPrice > 1000000000 || !Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000 || !["event", "trending", "country", "lucky", "custom"].includes(category) || (category === "country" && !countryCode) || (countryCode !== null && !/^[A-Z0-9_-]{2,24}$/.test(countryCode)) || (startsAt && Number.isNaN(Date.parse(startsAt))) || (endsAt && Number.isNaN(Date.parse(endsAt))) || (startsAt && endsAt && Date.parse(endsAt) <= Date.parse(startsAt))) return json({ error: "invalid_gift", message: "تحقق من اسم الهدية ورمزها وسعرها وتصنيفها والدولة وفترة العرض." }, 400, origin, env);
            const id = crypto.randomUUID(), now = new Date().toISOString();
            await env.DB!.prepare("INSERT INTO gift_catalog (id, name, icon_emoji, asset_key, media_url, media_type, thumbnail_url, sound_url, duration_seconds, coin_price, is_active, sort_order, created_at, updated_at, category, country_code, starts_at, ends_at) VALUES (?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
              .bind(id, name, iconEmoji, mediaUrl, mediaType, thumbnailUrl, soundUrl, durationSeconds, coinPrice, isActive, sortOrder, now, now, category, countryCode, startsAt, endsAt).run();
            return json({ ok: true, gift: { id, name, iconEmoji, mediaUrl, mediaType, thumbnailUrl, soundUrl, durationSeconds, coinPrice, isActive: Boolean(isActive), sortOrder, category, countryCode, startsAt, endsAt, createdAt: now, updatedAt: now } }, 201, origin, env);
          }
          if (request.method === "PATCH" && itemRoute) {
            let body: Record<string, unknown>;
            try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
            const current = await env.DB!.prepare("SELECT id, name, icon_emoji AS iconEmoji, media_url AS mediaUrl, media_type AS mediaType, thumbnail_url AS thumbnailUrl, sound_url AS soundUrl, duration_seconds AS durationSeconds, coin_price AS coinPrice, is_active AS isActive, sort_order AS sortOrder, category, country_code AS countryCode, starts_at AS startsAt, ends_at AS endsAt FROM gift_catalog WHERE id = ?").bind(itemRoute[1]).first<Record<string, unknown>>();
            if (!current) return json({ error: "gift_not_found" }, 404, origin, env);
            const name = body.name === undefined ? String(current.name) : (typeof body.name === "string" ? body.name.trim() : "");
            const iconEmoji = body.iconEmoji === undefined ? String(current.iconEmoji) : (typeof body.iconEmoji === "string" ? body.iconEmoji.trim() : "");
            const coinPrice = body.coinPrice === undefined ? Number(current.coinPrice) : Number(body.coinPrice);
            const sortOrder = body.sortOrder === undefined ? Number(current.sortOrder) : Number(body.sortOrder);
            const isActive = body.isActive === undefined ? Number(current.isActive) : (body.isActive === true ? 1 : body.isActive === false ? 0 : -1);
            const category = body.category === undefined ? String(current.category ?? "trending") : (typeof body.category === "string" ? body.category : "");
            const countryCode = body.countryCode === undefined ? (current.countryCode ? String(current.countryCode) : null) : (typeof body.countryCode === "string" && body.countryCode.trim() ? body.countryCode.trim().toUpperCase() : null);
            const startsAt = body.startsAt === undefined ? (current.startsAt ? String(current.startsAt) : null) : (typeof body.startsAt === "string" && body.startsAt ? body.startsAt : null);
            const endsAt = body.endsAt === undefined ? (current.endsAt ? String(current.endsAt) : null) : (typeof body.endsAt === "string" && body.endsAt ? body.endsAt : null);
            const mediaUrl = body.mediaUrl === undefined ? (current.mediaUrl ? String(current.mediaUrl) : null) : (typeof body.mediaUrl === "string" && body.mediaUrl.trim() ? body.mediaUrl.trim() : null);
            const thumbnailUrl = body.thumbnailUrl === undefined ? (current.thumbnailUrl ? String(current.thumbnailUrl) : null) : (typeof body.thumbnailUrl === "string" && body.thumbnailUrl.trim() ? body.thumbnailUrl.trim() : null);
            const mediaType = body.mediaType === undefined ? String(current.mediaType ?? (mediaUrl ? "webp" : "emoji")) : String(body.mediaType).toLowerCase();
            const soundUrl = body.soundUrl === undefined ? (current.soundUrl ? String(current.soundUrl) : null) : (typeof body.soundUrl === "string" && body.soundUrl.trim() ? body.soundUrl.trim() : null);
            const durationSeconds = body.durationSeconds === undefined ? Number(current.durationSeconds ?? 5) : Number(body.durationSeconds);
            if (!Number.isFinite(durationSeconds) || durationSeconds < 0.1 || durationSeconds > 60) return json({ error: "invalid_gift_duration", message: "مدة حركة الهدية يجب أن تكون من 1 إلى 60 ثانية." }, 400, origin, env);
            if (!isValidGiftSoundUrl(soundUrl)) return json({ error: "invalid_gift_sound", message: "ملف الصوت يجب أن يكون MP3 برابط HTTPS." }, 400, origin, env);
            if ((mediaUrl && (mediaUrl.length > 2048 || !/^https:\/\//i.test(mediaUrl))) || (thumbnailUrl && (thumbnailUrl.length > 2048 || !/^https:\/\//i.test(thumbnailUrl))) || !["emoji", "svga", "gif", "pag", "apng", "webp"].includes(mediaType) || (mediaUrl && mediaType === "emoji") || (!mediaUrl && mediaType !== "emoji")) return json({ error: "invalid_gift_media", message: "روابط صور ووسائط الهدية يجب أن تكون HTTPS وبصيغة مدعومة." }, 400, origin, env);
            if (!name || name.length > 80 || !iconEmoji || iconEmoji.length > 16 || !Number.isSafeInteger(coinPrice) || coinPrice < 1 || coinPrice > 1000000000 || !Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000 || ![0, 1].includes(isActive) || !["event", "trending", "country", "lucky", "custom"].includes(category) || (category === "country" && !countryCode) || (countryCode !== null && !/^[A-Z0-9_-]{2,24}$/.test(countryCode)) || (startsAt && Number.isNaN(Date.parse(startsAt))) || (endsAt && Number.isNaN(Date.parse(endsAt))) || (startsAt && endsAt && Date.parse(endsAt) <= Date.parse(startsAt))) return json({ error: "invalid_gift", message: "تحقق من بيانات الهدية." }, 400, origin, env);
            const now = new Date().toISOString();
            await env.DB!.prepare("UPDATE gift_catalog SET name = ?, icon_emoji = ?, media_url = ?, media_type = ?, thumbnail_url = ?, sound_url = ?, duration_seconds = ?, coin_price = ?, is_active = ?, sort_order = ?, category = ?, country_code = ?, starts_at = ?, ends_at = ?, updated_at = ? WHERE id = ?")
              .bind(name, iconEmoji, mediaUrl, mediaType, thumbnailUrl, soundUrl, durationSeconds, coinPrice, isActive, sortOrder, category, countryCode, startsAt, endsAt, now, itemRoute[1]).run();
            return json({ ok: true, gift: { id: itemRoute[1], name, iconEmoji, mediaUrl, mediaType, thumbnailUrl, soundUrl, durationSeconds, coinPrice, isActive: Boolean(isActive), sortOrder, category, countryCode, startsAt, endsAt, updatedAt: now } }, 200, origin, env);
          }
          if (request.method === "DELETE" && itemRoute) {
            const result = await env.DB!.prepare("UPDATE gift_catalog SET is_active = 0, updated_at = ? WHERE id = ?").bind(new Date().toISOString(), itemRoute[1]).run();
            if ((result.meta?.changes ?? 0) === 0) return json({ error: "gift_not_found" }, 404, origin, env);
            return json({ ok: true, deactivated: true }, 200, origin, env);
          }
          return json({ error: "method_not_allowed" }, 405, origin, env);
        }
        if (url.pathname === "/api/v1/admin/gifts/custom-requests" || /^\/api\/v1\/admin\/gifts\/custom-requests\/[0-9a-f-]{36}$/i.test(url.pathname)) {
          if (actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const requestRoute = url.pathname.match(/^\/api\/v1\/admin\/gifts\/custom-requests\/([0-9a-f-]{36})$/i);
          if (request.method === "GET" && !requestRoute) {
            const rows = await env.DB!.prepare("SELECT r.id, r.requested_name AS requestedName, r.description, r.media_url AS mediaUrl, r.media_type AS mediaType, r.media_duration_ms AS mediaDurationMs, r.media_file_id AS mediaFileId, r.sound_url AS soundUrl, r.status, r.admin_note AS adminNote, r.created_at AS createdAt, p.display_name AS displayName, p.happy_id AS happyId FROM gift_custom_requests r LEFT JOIN profiles p ON p.user_id = r.user_id ORDER BY CASE r.status WHEN 'pending' THEN 0 ELSE 1 END, r.created_at DESC LIMIT 200").all();
            return json({ ok: true, requests: rows.results ?? [] }, 200, origin, env);
          }
          if (request.method === "PATCH" && requestRoute) {
            let body: Record<string, unknown>;
            try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
            const status = body.status;
            const adminNote = typeof body.adminNote === "string" ? body.adminNote.trim() : "";
            if (!["approved", "rejected"].includes(String(status)) || adminNote.length > 500) return json({ error: "invalid_request_review" }, 400, origin, env);
            const pending = await env.DB!.prepare("SELECT id, requested_name AS requestedName FROM gift_custom_requests WHERE id = ? AND status = 'pending'").bind(requestRoute[1]).first<{ id: string; requestedName: string }>();
            if (!pending) return json({ error: "request_not_pending" }, 409, origin, env);
            const now = new Date().toISOString();
            if (status === "rejected") {
              const result = await env.DB!.prepare("UPDATE gift_custom_requests SET status = 'rejected', admin_note = ?, reviewed_by_admin_id = ?, reviewed_at = ? WHERE id = ? AND status = 'pending'")
                .bind(adminNote, actor.id, now, requestRoute[1]).run();
              if ((result.meta?.changes ?? 0) !== 1) return json({ error: "request_not_pending" }, 409, origin, env);
              return json({ ok: true, status: "rejected" }, 200, origin, env);
            }
            const iconEmoji = typeof body.iconEmoji === "string" && body.iconEmoji.trim() ? body.iconEmoji.trim() : "🎁";
            const coinPrice = Number(body.coinPrice);
            const sortOrder = Number(body.sortOrder ?? 500);
            if (iconEmoji.length > 16 || !Number.isSafeInteger(coinPrice) || coinPrice < 1 || coinPrice > 1000000000 || !Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000) return json({ error: "invalid_approved_gift" }, 400, origin, env);
            const giftId = crypto.randomUUID();
            const results = await env.DB!.batch([
              env.DB!.prepare("INSERT INTO gift_catalog (id, name, icon_emoji, asset_key, coin_price, is_active, sort_order, created_at, updated_at, category, media_url, media_type, sound_url) " +
                "SELECT ?, requested_name, ?, '', ?, 1, ?, ?, ?, 'custom', media_url, " +
                "CASE WHEN media_type = 'gif' THEN 'gif' WHEN media_type = 'svga' THEN 'svga' ELSE 'emoji' END, sound_url " +
                "FROM gift_custom_requests WHERE id = ? AND status = 'pending'")
                .bind(giftId, iconEmoji, coinPrice, sortOrder, now, now, requestRoute[1]),
              env.DB!.prepare("UPDATE gift_custom_requests SET status = 'approved', admin_note = ?, approved_gift_id = ?, reviewed_by_admin_id = ?, reviewed_at = ? WHERE id = ? AND status = 'pending'")
                .bind(adminNote, giftId, actor.id, now, requestRoute[1])
            ]);
            if ((results[1]?.meta?.changes ?? 0) !== 1) return json({ error: "request_not_pending" }, 409, origin, env);
            return json({ ok: true, status: "approved", giftId }, 200, origin, env);
          }
          return json({ error: "method_not_allowed" }, 405, origin, env);
        }
        const adminWalletCreditRoute = url.pathname.match(new RegExp("^/api/v1/admin/users/([0-9a-f-]{36})/wallet/credit$", "i"));
        if (adminWalletCreditRoute && request.method === "POST") {
          if (actor.role !== "owner") return json({ error: "owner_permission_required", message: "إضافة العملات متاحة لمالك التطبيق فقط" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const amount = Number(body.amount);
          if (!Number.isSafeInteger(amount) || amount < 1 || amount > 1000000000) return json({ error: "invalid_credit_amount" }, 400, origin, env);
          const targetUserId = adminWalletCreditRoute[1];
          const target = await env.DB!.prepare("SELECT id FROM users WHERE id = ? AND status = 'active' LIMIT 1").bind(targetUserId).first<{ id: string }>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          const now = new Date().toISOString();
          const transactionId = crypto.randomUUID();
          await env.DB!.batch([
            env.DB!.prepare("INSERT OR IGNORE INTO user_wallets (user_id, balance, updated_at) VALUES (?, 0, ?)").bind(targetUserId, now),
            env.DB!.prepare("UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ?").bind(amount, now, targetUserId),
            env.DB!.prepare("INSERT INTO wallet_transactions (id, user_id, amount, balance_after, transaction_type, reference_id, description, created_at) SELECT ?, user_id, ?, balance, 'admin_credit', ?, 'إضافة رصيد يدوية من الإدارة', ? FROM user_wallets WHERE user_id = ?").bind(transactionId, amount, actor.id, now, targetUserId),
            env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'wallet.credit', 'user', ?, ?, ?)").bind(crypto.randomUUID(), targetUserId, JSON.stringify({ amount, adminId: actor.id, adminUsername: actor.username }), now)
          ]);
          const wallet = await env.DB!.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(targetUserId).first<{ balance: number }>();
          return json({ ok: true, userId: targetUserId, credited: amount, balance: wallet?.balance ?? 0 }, 200, origin, env);
        }

        if (url.pathname === "/api/v1/admin/agora/status" && request.method === "GET") {
          if (!hasAdminPermission(actor, "agora.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const voiceEnabled = await isAgoraVoiceEnabled(env.DB, env);
          return json({ ok: true, agora: {
            enabled: env.AGORA_ENABLED !== "false",
            voiceEnabled,
            appId: env.AGORA_APP_ID ?? "",
            certificateConfigured: Boolean(env.AGORA_APP_CERTIFICATE)
          } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/agora/voice" && request.method === "PATCH") {
          if (!hasAdminPermission(actor, "agora.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          if (typeof body.enabled !== "boolean") {
            return json({ error: "invalid_voice_state" }, 400, origin, env);
          }
          if (body.enabled && (!env.AGORA_APP_ID || !env.AGORA_APP_CERTIFICATE || env.AGORA_ENABLED === "false")) {
            return json({ error: "agora_not_configured", message: "لا يمكن تشغيل الصوت قبل اكتمال إعداد Agora على الخادم" }, 409, origin, env);
          }
          const now = new Date().toISOString();
          const statements = [
            env.DB!.prepare(
              "INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('agora_voice_enabled', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at"
            ).bind(body.enabled ? "true" : "false", now)
          ];
          if (!body.enabled) {
            statements.push(env.DB!.prepare("DELETE FROM room_seats"));
          }
          statements.push(env.DB!.prepare(
            "INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, ?, 'platform', 'agora_voice', ?, ?)"
          ).bind(
            crypto.randomUUID(),
            body.enabled ? "agora.voice.enable" : "agora.voice.disable",
            JSON.stringify({ enabled: body.enabled, adminUsername: actor.username, adminId: actor.id, effect: body.enabled ? "voice_service_resumed" : "all_microphone_seats_released" }),
            now
          ));
          await env.DB!.batch(statements);
          if (env.ROOM_SEATS) {
            const activeRooms = await env.DB!.prepare("SELECT id FROM rooms WHERE status = 'active'").all<{ id: string }>();
            const path = body.enabled ? "/enable" : "/clear";
            await Promise.all((activeRooms.results ?? []).map((room) => {
              const stub = env.ROOM_SEATS!.get(env.ROOM_SEATS!.idFromName(room.id));
              return stub.fetch(new Request(`https://room-seats.internal${path}`, { method: "POST" }));
            }));
          }
          return json({ ok: true, voiceEnabled: body.enabled }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/me" && request.method === "GET") {
          return json({ ok: true, admin: { id: actor.id, name: actor.display_name, username: actor.username, role: actor.role } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/overview" && request.method === "GET") {
          if (!hasAdminPermission(actor, "dashboard.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const [users, rooms, posts] = await Promise.all([
            env.DB!.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active FROM users").first<{total:number;active:number}>(),
            env.DB!.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active FROM rooms").first<{total:number;active:number}>(),
            env.DB!.prepare("SELECT COUNT(*) AS total FROM posts WHERE status = 'published'").first<{total:number}>()
          ]);
          return json({ ok: true, overview: {
            users: { total: users?.total ?? 0, active: users?.active ?? 0 },
            rooms: { total: rooms?.total ?? 0, active: rooms?.active ?? 0 },
            publishedPosts: posts?.total ?? 0
          } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/users" && request.method === "GET") {
          if (!hasAdminPermission(actor, "users.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const q = (url.searchParams.get("q") ?? "").trim().slice(0, 80);
          const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit") ?? 50) || 50));
          const result = await env.DB!.prepare(
            "SELECT u.id, u.email, u.status, u.auth_provider, u.created_at, p.display_name, p.happy_id, ar.role AS admin_role " +
            "FROM users u LEFT JOIN profiles p ON p.user_id = u.id LEFT JOIN admin_roles ar ON ar.user_id = u.id " +
            "WHERE (? = '' OR u.email LIKE '%' || ? || '%' OR p.display_name LIKE '%' || ? || '%' OR p.happy_id LIKE '%' || ? || '%') " +
            "ORDER BY u.created_at DESC LIMIT ?"
          ).bind(q, q, q, q, limit).all();
          return json({ ok: true, users: result.results ?? [] }, 200, origin, env);
        }
        // Wallet read API is required by the admin wallet screen; keep it in the production route table.
        // Keep the admin wallet endpoint in the deployed Worker route table.
        if (url.pathname === "/api/v1/admin/wallets" && request.method === "GET") {
          if (actor.role !== "owner" && actor.role !== "admin") return json({ error: "permission_denied" }, 403, origin, env);
          const q = (url.searchParams.get("q") ?? "").trim().slice(0, 80);
          const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit") ?? 100) || 100));
          const [summary, result] = await Promise.all([
            env.DB!.prepare(
              "SELECT COUNT(*) AS users, COALESCE(SUM(COALESCE(w.balance, 0)), 0) AS totalBalance, " +
              "SUM(CASE WHEN COALESCE(w.balance, 0) > 0 THEN 1 ELSE 0 END) AS fundedUsers " +
              "FROM users u LEFT JOIN user_wallets w ON w.user_id = u.id WHERE u.status = 'active'"
            ).first<{ users: number; totalBalance: number; fundedUsers: number }>(),
            env.DB!.prepare(
              "SELECT u.id, u.email, p.display_name, p.happy_id, COALESCE(w.balance, 0) AS balance, w.updated_at " +
              "FROM users u LEFT JOIN profiles p ON p.user_id = u.id LEFT JOIN user_wallets w ON w.user_id = u.id " +
              "WHERE u.status = 'active' AND (? = '' OR u.email LIKE '%' || ? || '%' OR p.display_name LIKE '%' || ? || '%' OR p.happy_id LIKE '%' || ? || '%') " +
              "ORDER BY balance DESC, u.created_at DESC LIMIT ?"
            ).bind(q, q, q, q, limit).all()
          ]);
          const userId = url.searchParams.get("userId") ?? "";
          let selectedWallet: Record<string, unknown> | null = null;
          let transactions: unknown[] = [];
          if (userId) {
            selectedWallet = await env.DB!.prepare(
              "SELECT u.id, u.email, p.display_name, p.happy_id, COALESCE(w.balance, 0) AS balance, w.updated_at " +
              "FROM users u LEFT JOIN profiles p ON p.user_id = u.id LEFT JOIN user_wallets w ON w.user_id = u.id " +
              "WHERE u.id = ? AND u.status = 'active' LIMIT 1"
            ).bind(userId).first<Record<string, unknown>>();
            if (selectedWallet) {
              const history = await env.DB!.prepare(
                "SELECT id, amount, balance_after AS balanceAfter, transaction_type AS type, reference_id AS referenceId, description, created_at AS createdAt " +
                "FROM wallet_transactions WHERE user_id = ? " +
                "UNION ALL " +
                "SELECT id, amount, balance_after AS balanceAfter, transaction_type AS type, reference_id AS referenceId, description, created_at AS createdAt " +
                "FROM wallet_transactions WHERE user_id = ? ORDER BY createdAt DESC LIMIT 50"
              ).bind(userId).all();
              transactions = history.results ?? [];
            }
          }
          return json({
            ok: true,
            summary: { users: summary?.users ?? 0, totalBalance: summary?.totalBalance ?? 0, fundedUsers: summary?.fundedUsers ?? 0 },
            wallets: result.results ?? [],
            selectedWallet,
            transactions
          }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/rooms" && request.method === "GET") {
          if (!hasAdminPermission(actor, "rooms.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const result = await env.DB!.prepare(
            "SELECT r.id, r.room_code, r.name, r.status, r.visibility, r.created_at, u.id AS owner_id, p.display_name AS owner_name, COALESCE(rx.total_exp, 0) AS total_exp " +
            "FROM rooms r INNER JOIN users u ON u.id = r.owner_user_id LEFT JOIN profiles p ON p.user_id = u.id LEFT JOIN room_experience rx ON rx.room_id = r.id " +
            "ORDER BY r.created_at DESC LIMIT 100"
          ).all<{ id: string; total_exp: number }>();
          const rooms = (result.results ?? []).map((room) => ({
            ...room,
            experience_level: roomExperienceProgress(Number(room.total_exp ?? 0)).level
          }));
          return json({ ok: true, rooms }, 200, origin, env);
        }
        const adminRoomLevelRoute = url.pathname.match(/^\/api\/v1\/admin\/rooms\/([0-9a-f-]{36})\/level$/i);
        if (adminRoomLevelRoute && request.method === "PATCH") {
          if (!hasAdminPermission(actor, "rooms.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const targetLevel = Number(body.level);
          if (!Number.isInteger(targetLevel) || targetLevel < 1 || targetLevel > MAX_ROOM_EXPERIENCE_LEVEL) {
            return json({ error: "invalid_room_experience_level", message: "مستوى الغرفة يجب أن يكون بين 1 و150" }, 400, origin, env);
          }
          const roomId = adminRoomLevelRoute[1];
          const existing = await env.DB!.prepare(
            "SELECT r.id, r.name, COALESCE(rx.total_exp, 0) AS total_exp FROM rooms r LEFT JOIN room_experience rx ON rx.room_id = r.id WHERE r.id = ? AND r.status <> 'deleted' LIMIT 1"
          ).bind(roomId).first<{ id: string; name: string; total_exp: number }>();
          if (!existing) return json({ error: "room_not_found", message: "الغرفة غير موجودة" }, 404, origin, env);
          const requiredExp = roomExperienceRequiredForLevel(targetLevel);
          const nextTotalExp = Math.max(Number(existing.total_exp ?? 0), requiredExp);
          const now = new Date().toISOString();
          await env.DB!.prepare(
            "INSERT INTO room_experience (room_id, total_exp, updated_at) VALUES (?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET total_exp = excluded.total_exp, updated_at = excluded.updated_at"
          ).bind(roomId, nextTotalExp, now).run();
          const progress = roomExperienceProgress(nextTotalExp);
          return json({ ok: true, roomId, roomName: existing.name, level: progress.level, totalExperience: nextTotalExp, requiredExperience: requiredExp }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/audit" && request.method === "GET") {
          if (!hasAdminPermission(actor, "audit.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const result = await env.DB!.prepare(
            "SELECT l.id, l.action, l.target_type, l.target_id, l.details_json, l.created_at, p.display_name AS actor_name, u.email AS actor_email " +
            "FROM admin_audit_logs l LEFT JOIN users u ON u.id = l.actor_user_id LEFT JOIN profiles p ON p.user_id = l.actor_user_id " +
            "ORDER BY l.created_at DESC LIMIT 100"
          ).all();
          const entries = (result.results ?? []).map((entry) => {
            let details: Record<string, unknown> = {};
            try { details = JSON.parse(String(entry.details_json ?? "{}")) as Record<string, unknown>; } catch { /* Ignore malformed legacy details. */ }
            return { ...entry, actor_name: entry.actor_name || String(details.adminUsername ?? entry.actor_email ?? "—") };
          });
          return json({ ok: true, entries }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/stats" && request.method === "GET") {
          if (!hasAdminPermission(actor, "dashboard.read")) return json({ error: "permission_denied" }, 403, origin, env);
          const since = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
          const [users, rooms, posts, messages, dailyUsers, dailyMessages, topFollowers] = await Promise.all([
            env.DB!.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active, SUM(CASE WHEN status = 'suspended' THEN 1 ELSE 0 END) AS suspended FROM users").first<{ total: number; active: number; suspended: number }>(),
            env.DB!.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active FROM rooms").first<{ total: number; active: number }>(),
            env.DB!.prepare("SELECT COUNT(*) AS total FROM posts WHERE status = 'published'").first<{ total: number }>(),
            env.DB!.prepare("SELECT COUNT(*) AS total FROM room_messages WHERE created_at >= ?").bind(since).first<{ total: number }>(),
            env.DB!.prepare("SELECT substr(created_at, 1, 10) AS day, COUNT(*) AS total FROM users WHERE created_at >= ? GROUP BY substr(created_at, 1, 10) ORDER BY day").bind(since).all(),
            env.DB!.prepare("SELECT substr(created_at, 1, 10) AS day, COUNT(*) AS total FROM room_messages WHERE created_at >= ? GROUP BY substr(created_at, 1, 10) ORDER BY day").bind(since).all(),
            env.DB!.prepare("SELECT p.display_name AS name, COUNT(*) AS count FROM user_follows f INNER JOIN profiles p ON p.user_id = f.following_id GROUP BY f.following_id, p.display_name ORDER BY count DESC, p.display_name ASC LIMIT 10").all()
          ]);
          return json({ ok: true, stats: { summary: {
            users: { total: users?.total ?? 0, active: users?.active ?? 0, suspended: users?.suspended ?? 0 },
            rooms: { total: rooms?.total ?? 0, active: rooms?.active ?? 0 },
            publishedPosts: posts?.total ?? 0, roomMessagesLast7Days: messages?.total ?? 0
          }, daily: { users: dailyUsers.results ?? [], messages: dailyMessages.results ?? [] }, topFollowers: topFollowers.results ?? [] } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/moderators" && request.method === "GET") {
          if (!hasAdminPermission(actor, "users.roles.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          const result = await env.DB!.prepare("SELECT u.id, u.email, u.status, p.display_name, p.happy_id, ar.role, ar.granted_at FROM admin_roles ar INNER JOIN users u ON u.id = ar.user_id LEFT JOIN profiles p ON p.user_id = u.id WHERE ar.role IN ('admin', 'moderator') ORDER BY ar.granted_at DESC LIMIT 200").all();
          return json({ ok: true, moderators: result.results ?? [] }, 200, origin, env);
        }
        const userRoleRoute = url.pathname.match(/^\/api\/v1\/admin\/users\/([0-9a-f-]{36})\/role$/i);
        if (userRoleRoute && request.method === "PATCH") {
          if (!hasAdminPermission(actor, "users.roles.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const nextRole = body.role === "admin" || body.role === "moderator" ? body.role : body.role === null ? null : undefined;
          if (nextRole === undefined) return json({ error: "invalid_admin_role" }, 400, origin, env);
          const targetId = userRoleRoute[1];
          const target = await env.DB!.prepare("SELECT u.id, u.status, ar.role FROM users u LEFT JOIN admin_roles ar ON ar.user_id = u.id WHERE u.id = ? LIMIT 1").bind(targetId).first<{ id: string; status: string; role: string | null }>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          if (target.status !== "active") return json({ error: "user_must_be_active" }, 409, origin, env);
          if (target.role === "owner") return json({ error: "owner_role_is_protected" }, 403, origin, env);
          const now = new Date().toISOString(), action = nextRole ? "user.role.assign" : "user.role.remove";
          const statements: D1PreparedStatement[] = [];
          if (nextRole) statements.push(env.DB!.prepare("INSERT INTO admin_roles (user_id, role, granted_by, granted_at) VALUES (?, ?, NULL, ?) ON CONFLICT(user_id) DO UPDATE SET role = excluded.role, granted_by = NULL, granted_at = excluded.granted_at").bind(targetId, nextRole, now));
          else statements.push(env.DB!.prepare("DELETE FROM admin_roles WHERE user_id = ? AND role <> 'owner'").bind(targetId));
          statements.push(env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, ?, 'user', ?, ?, ?)").bind(crypto.randomUUID(), action, targetId, JSON.stringify({ role: nextRole, adminUsername: actor.username, adminId: actor.id }), now));
          await env.DB!.batch(statements);
          return json({ ok: true, userId: targetId, role: nextRole }, 200, origin, env);
        }
        const userStatusRoute = url.pathname.match(/^\/api\/v1\/admin\/users\/([0-9a-f-]{36})\/status$/i);
        if (userStatusRoute && request.method === "PATCH") {
          if (!hasAdminPermission(actor, "users.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          const targetId = userStatusRoute[1];
          
          const body = await request.json() as Record<string, unknown>;
          const status = body.status === "active" || body.status === "suspended" ? body.status : null;
          if (!status) return json({ error: "invalid_status" }, 400, origin, env);
          const target = await env.DB!.prepare("SELECT u.id, u.status, ar.role FROM users u LEFT JOIN admin_roles ar ON ar.user_id = u.id WHERE u.id = ? LIMIT 1")
            .bind(targetId).first<{id:string;status:string;role:string|null}>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          if (target.status === "deleted") return json({ error: "deleted_user_cannot_be_reactivated" }, 409, origin, env);
          if (target.role && actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const now = new Date().toISOString();
          const statements = [env.DB!.prepare("UPDATE users SET status = ?, updated_at = ? WHERE id = ?").bind(status, now, targetId)];
          if (status === "suspended") {
            statements.push(env.DB!.prepare("UPDATE user_sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL").bind(now, targetId));
            statements.push(env.DB!.prepare("DELETE FROM room_seats WHERE user_id = ?").bind(targetId));
            statements.push(env.DB!.prepare("UPDATE room_chat_visits SET exited_at = ? WHERE user_id = ? AND exited_at IS NULL").bind(now, targetId));
          }
          statements.push(env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, ?, 'user', ?, ?, ?)").bind(crypto.randomUUID(), status === "suspended" ? "user.suspend" : "user.activate", targetId, JSON.stringify({ status, adminUsername: actor.username, adminId: actor.id }), now));
          await env.DB!.batch(statements);
          if (status === "suspended") await removeUserFromAllRoomSeats(env, env.DB, targetId);
          return json({ ok: true, userId: targetId, status }, 200, origin, env);
        }
        const userKickRoute = url.pathname.match(/^\/api\/v1\/admin\/users\/([0-9a-f-]{36})\/kick$/i);
        if (userKickRoute && request.method === "POST") {
          if (!hasAdminPermission(actor, "users.kick")) return json({ error: "permission_denied" }, 403, origin, env);
          const targetId = userKickRoute[1];
          const target = await env.DB!.prepare("SELECT u.id, u.status, ar.role FROM users u LEFT JOIN admin_roles ar ON ar.user_id = u.id WHERE u.id = ? LIMIT 1").bind(targetId).first<{ id: string; status: string; role: string | null }>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          if (target.status === "deleted") return json({ error: "deleted_user_cannot_be_kicked" }, 409, origin, env);
          if (target.role && actor.role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const now = new Date().toISOString();
          const results = await env.DB!.batch([
            env.DB!.prepare("UPDATE user_sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL").bind(now, targetId),
            env.DB!.prepare("DELETE FROM room_seats WHERE user_id = ?").bind(targetId),
            env.DB!.prepare("UPDATE room_chat_visits SET exited_at = ? WHERE user_id = ? AND exited_at IS NULL").bind(now, targetId),
            env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'user.kick', 'user', ?, ?, ?)").bind(crypto.randomUUID(), targetId, JSON.stringify({ adminUsername: actor.username, adminId: actor.id, effect: "all_sessions_revoked" }), now)
          ]);
          await removeUserFromAllRoomSeats(env, env.DB, targetId);
          return json({ ok: true, userId: targetId, revokedSessions: results[0]?.meta?.changes ?? 0 }, 200, origin, env);
        }
        const roomModerationRoute = url.pathname.match(/^\/api\/v1\/admin\/rooms\/([0-9a-f-]{36})\/moderation$/i);
        if (roomModerationRoute && (request.method === "GET" || request.method === "POST")) {
          if (!env.ROOM_SEATS) return json({ error: "room_seats_unavailable" }, 503, origin, env);
          const roomId = roomModerationRoute[1];
          const room = await env.DB!.prepare(
            "SELECT id, owner_user_id, name FROM rooms WHERE id = ? LIMIT 1"
          ).bind(roomId).first<{ id: string; owner_user_id: string; name: string }>();
          if (!room) return json({ error: "room_not_found" }, 404, origin, env);

          if (request.method === "GET") {
            if (!hasAdminPermission(actor, "rooms.read")) return json({ error: "permission_denied" }, 403, origin, env);
            const now = new Date().toISOString();
            const q = (url.searchParams.get("q") ?? "").trim().slice(0, 80);
            const [members, moderators, bans, kicks] = await Promise.all([
              env.DB!.prepare(
                "SELECT s.user_id, s.seat_number, s.joined_at, u.email, p.display_name, p.happy_id, " +
                "CASE WHEN rm.user_id IS NULL THEN 0 ELSE 1 END AS is_moderator, COALESCE(c.is_muted, 0) AS is_muted " +
                "FROM room_seats s INNER JOIN users u ON u.id = s.user_id " +
                "LEFT JOIN profiles p ON p.user_id = u.id " +
                "LEFT JOIN room_moderators rm ON rm.room_id = s.room_id AND rm.user_id = s.user_id " +
                "LEFT JOIN room_user_controls c ON c.room_id = s.room_id AND c.user_id = s.user_id " +
                "WHERE s.room_id = ? AND s.expires_at > ? ORDER BY s.seat_number"
              ).bind(roomId, now).all(),
              env.DB!.prepare(
                "SELECT rm.user_id, rm.created_at, u.email, p.display_name, p.happy_id " +
                "FROM room_moderators rm INNER JOIN users u ON u.id = rm.user_id " +
                "LEFT JOIN profiles p ON p.user_id = u.id WHERE rm.room_id = ? ORDER BY rm.created_at DESC"
              ).bind(roomId).all(),
              env.DB!.prepare(
                "SELECT b.user_id, b.created_at, u.email, p.display_name, p.happy_id " +
                "FROM room_bans b INNER JOIN users u ON u.id = b.user_id " +
                "LEFT JOIN profiles p ON p.user_id = u.id WHERE b.room_id = ? ORDER BY b.created_at DESC"
              ).bind(roomId).all(),
              env.DB!.prepare(
                "SELECT k.user_id, k.kicked_until, k.created_at, u.email, p.display_name, p.happy_id " +
                "FROM room_kicks k INNER JOIN users u ON u.id = k.user_id " +
                "LEFT JOIN profiles p ON p.user_id = u.id WHERE k.room_id = ? AND k.kicked_until > ? ORDER BY k.kicked_until DESC"
              ).bind(roomId, now).all()
            ]);
            if (!env.ROOM_SEATS) return json({ error: "room_seats_unavailable" }, 503, origin, env);
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            const seatSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
            const seatSnapshot = await seatSnapshotResponse.json() as { seats?: Array<Record<string, unknown>> };
            const activeSeats = seatSnapshot.seats ?? [];
            const activeSeatIds = new Set(activeSeats.map((seat) => String(seat.userId ?? "")));
            let roomMembers: unknown[] = [];
            if (activeSeats.length > 0) {
              const ids = activeSeats.map((seat) => String(seat.userId ?? ""));
              const placeholders = ids.map(() => "?").join(",");
              const details = await env.DB!.prepare(
                "SELECT u.id, u.email, p.display_name, p.happy_id FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.id IN (" + placeholders + ")"
              ).bind(...ids).all<{ id: string; email: string; display_name: string | null; happy_id: string | null }>();
              const detailsById = new Map<string, { id: string; email: string; display_name: string | null; happy_id: string | null }>();
              for (const row of details.results ?? []) detailsById.set(row.id, row);
              roomMembers = activeSeats.map((seat) => {
                const detail = detailsById.get(String(seat.userId ?? ""));
                return {
                  user_id: seat.userId,
                  seat_number: seat.seatNumber,
                  joined_at: seat.joinedAt ?? null,
                  email: detail?.email ?? "",
                  display_name: detail?.display_name ?? seat.name ?? "مستخدم",
                  happy_id: detail?.happy_id ?? seat.userCode ?? "",
                  is_moderator: seat.isRoomModerator === true ? 1 : 0,
                  is_muted: seat.isMuted === true ? 1 : 0
                };
              });
            }
            let userResults: unknown[] = [];
            if (q.length >= 2) {
              const found = await env.DB!.prepare(
                "SELECT u.id AS user_id, u.email, p.display_name, p.happy_id, " +
                "CASE WHEN rm.user_id IS NULL THEN 0 ELSE 1 END AS is_moderator, " +
                "CASE WHEN b.user_id IS NULL THEN 0 ELSE 1 END AS is_banned, " +
                "CASE WHEN s.user_id IS NULL THEN 0 ELSE 1 END AS is_seated, COALESCE(c.is_muted, 0) AS is_muted " +
                "FROM users u LEFT JOIN profiles p ON p.user_id = u.id " +
                "LEFT JOIN room_moderators rm ON rm.room_id = ? AND rm.user_id = u.id " +
                "LEFT JOIN room_bans b ON b.room_id = ? AND b.user_id = u.id " +
                "LEFT JOIN room_seats s ON s.room_id = ? AND s.user_id = u.id AND s.expires_at > ? " +
                "LEFT JOIN room_user_controls c ON c.room_id = ? AND c.user_id = u.id " +
                "WHERE u.status = 'active' AND u.id <> ? AND " +
                "(u.email LIKE '%' || ? || '%' OR p.display_name LIKE '%' || ? || '%' OR p.happy_id LIKE '%' || ? || '%') " +
                "ORDER BY p.display_name COLLATE NOCASE LIMIT 20"
              ).bind(roomId, roomId, roomId, now, roomId, room.owner_user_id, q, q, q).all();
              userResults = (found.results ?? []).map((entry) => {
                const row = entry as Record<string, unknown>;
                return { ...row, is_seated: activeSeatIds.has(String(row.user_id ?? "")) ? 1 : 0 };
              });
            }
            return json({
              ok: true,
              room: { id: room.id, name: room.name, ownerUserId: room.owner_user_id },
              members: roomMembers,
              moderators: moderators.results ?? [],
              bans: bans.results ?? [],
              kicks: kicks.results ?? [],
              userResults
            }, 200, origin, env);
          }

          if (!hasAdminPermission(actor, "rooms.moderate")) return json({ error: "permission_denied" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const action = typeof body.action === "string" ? body.action : "";
          const targetUserId = typeof body.targetUserId === "string" ? body.targetUserId : "";
          const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 240) : "";
          const allowedActions = ["assign_moderator", "remove_moderator", "kick", "ban", "unban", "mute", "unmute"];
          if (!allowedActions.includes(action) || !/^[0-9a-f-]{36}$/i.test(targetUserId)) {
            return json({ error: "invalid_room_moderation_action" }, 400, origin, env);
          }
          const target = await env.DB!.prepare(
            "SELECT u.id, u.status, ar.role AS admin_role FROM users u LEFT JOIN admin_roles ar ON ar.user_id = u.id WHERE u.id = ? LIMIT 1"
          ).bind(targetUserId).first<{ id: string; status: string; admin_role: string | null }>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          if (target.status === "deleted" || (target.status !== "active" && action !== "unban" && action !== "remove_moderator")) {
            return json({ error: "user_not_active" }, 409, origin, env);
          }
          if (targetUserId === room.owner_user_id || target.admin_role === "owner") {
            return json({ error: "protected_room_owner" }, 403, origin, env);
          }
          const currentModerator = await env.DB!.prepare(
            "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
          ).bind(roomId, targetUserId).first<{ user_id: string }>();
          if (["kick", "ban", "mute", "unmute"].includes(action) && currentModerator) {
            return json({ error: "cannot_moderate_room_moderator", message: "أزل صفة مشرف الغرفة أولًا قبل تنفيذ هذا الإجراء" }, 403, origin, env);
          }
          const now = new Date().toISOString();
          const statements: D1PreparedStatement[] = [];
          let auditAction = "";
          let kickedUntil: string | null = null;

          if (action === "assign_moderator") {
            if (currentModerator) return json({ error: "already_room_moderator" }, 409, origin, env);
            // Legacy room_moderators.assigned_by is constrained to an application-user FK.
            // The actual administrator identity is recorded in admin_audit_logs below.
            statements.push(env.DB!.prepare(
              "INSERT INTO room_moderators (room_id, user_id, assigned_by, created_at) VALUES (?, ?, ?, ?)"
            ).bind(roomId, targetUserId, room.owner_user_id, now));
            auditAction = "room.moderator.assign";
          } else if (action === "remove_moderator") {
            if (!currentModerator) return json({ error: "room_moderator_not_found" }, 404, origin, env);
            statements.push(env.DB!.prepare(
              "DELETE FROM room_moderators WHERE room_id = ? AND user_id = ?"
            ).bind(roomId, targetUserId));
            auditAction = "room.moderator.remove";
          } else if (action === "kick") {
            kickedUntil = new Date(Date.now() + 60000).toISOString();
            statements.push(
              env.DB!.prepare("DELETE FROM room_seats WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId),
              env.DB!.prepare("UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL").bind(now, roomId, targetUserId),
              // Legacy room_kicks.kicked_by is constrained to an application-user FK.
              env.DB!.prepare(
                "INSERT INTO room_kicks (room_id, user_id, kicked_by, kicked_until, created_at) VALUES (?, ?, ?, ?, ?) " +
                "ON CONFLICT(room_id, user_id) DO UPDATE SET kicked_by = excluded.kicked_by, kicked_until = excluded.kicked_until, created_at = excluded.created_at"
              ).bind(roomId, targetUserId, room.owner_user_id, kickedUntil, now)
            );
            auditAction = "room.user.kick";
          } else if (action === "ban") {
            statements.push(
              env.DB!.prepare("DELETE FROM room_seats WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId),
              env.DB!.prepare("UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL").bind(now, roomId, targetUserId),
              env.DB!.prepare("DELETE FROM room_kicks WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId),
              // Legacy room_bans.banned_by is constrained to an application-user FK.
              env.DB!.prepare(
                "INSERT INTO room_bans (room_id, user_id, banned_by, created_at) VALUES (?, ?, ?, ?) " +
                "ON CONFLICT(room_id, user_id) DO UPDATE SET banned_by = excluded.banned_by, created_at = excluded.created_at"
              ).bind(roomId, targetUserId, room.owner_user_id, now)
            );
            auditAction = "room.user.ban";
          } else if (action === "unban") {
            const existingBan = await env.DB!.prepare(
              "SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1"
            ).bind(roomId, targetUserId).first();
            if (!existingBan) return json({ error: "room_ban_not_found" }, 404, origin, env);
            statements.push(env.DB!.prepare("DELETE FROM room_bans WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId));
            auditAction = "room.user.unban";
          } else if (action === "mute" || action === "unmute") {
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            const seatSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
            const seatSnapshot = await seatSnapshotResponse.json() as { seats?: Array<{ userId: string }> };
            const isSeated = (seatSnapshot.seats ?? []).some((seat) => seat.userId === targetUserId);
            if (!isSeated) return json({ error: "user_not_on_active_mic_seat" }, 409, origin, env);
            const muted = action === "mute" ? 1 : 0;
            statements.push(env.DB!.prepare(
              "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, ?, ?) " +
              "ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = excluded.muted_by, updated_at = excluded.updated_at"
            ).bind(roomId, targetUserId, muted, muted ? room.owner_user_id : null, now));
            auditAction = muted ? "room.user.mute" : "room.user.unmute";
          }

          statements.push(env.DB!.prepare(
            "INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, ?, 'room_user', ?, ?, ?)"
          ).bind(
            crypto.randomUUID(),
            auditAction,
            targetUserId,
            JSON.stringify({
              roomId,
              targetUserId,
              reason,
              adminId: actor.id,
              adminUsername: actor.username,
              durationSeconds: action === "kick" ? 60 : null
            }),
            now
          ));
          await env.DB!.batch(statements);
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
        if (action === "assign_moderator" || action === "remove_moderator") {
            await seatHub.fetch(new Request("https://room-seats.internal/set-moderator", {
              method: "POST",
              headers: {
                "x-target-user-id": targetUserId,
                "x-is-moderator": action === "assign_moderator" ? "true" : "false"
              }
            }));
          } else if (action === "kick" || action === "ban") {
            await seatHub.fetch(new Request("https://room-seats.internal/remove-user", {
              method: "POST",
              headers: { "x-target-user-id": targetUserId }
            }));
          } else if (action === "mute" || action === "unmute") {
            await seatHub.fetch(new Request("https://room-seats.internal/set-muted", {
              method: "POST",
              headers: {
                "x-target-user-id": targetUserId,
                "x-is-muted": action === "mute" ? "true" : "false"
              }
            }));
          }
          return json({ ok: true, roomId, targetUserId, action, kickedUntil }, 200, origin, env);
        }

        const roomStatusRoute = url.pathname.match(/^\/api\/v1\/admin\/rooms\/([0-9a-f-]{36})\/status$/i);
        if (roomStatusRoute && request.method === "PATCH") {
          if (!hasAdminPermission(actor, "rooms.manage")) return json({ error: "permission_denied" }, 403, origin, env);
          const targetId = roomStatusRoute[1];
          const body = await request.json() as Record<string, unknown>;
          const status = body.status === "active" || body.status === "closed" ? body.status : null;
          if (!status) return json({ error: "invalid_status" }, 400, origin, env);
          const exists = await env.DB!.prepare("SELECT id FROM rooms WHERE id = ? LIMIT 1").bind(targetId).first();
          if (!exists) return json({ error: "room_not_found" }, 404, origin, env);
          const now = new Date().toISOString();
          await env.DB!.batch([
            env.DB!.prepare("UPDATE rooms SET status = ?, updated_at = ? WHERE id = ?").bind(status, now, targetId),
            env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, 'room', ?, ?, ?)")
              .bind(crypto.randomUUID(), null, status === "closed" ? "room.close" : "room.reopen", targetId, JSON.stringify({ status, adminUsername: actor.username }), now)
          ]);
          if (status === "closed" && env.ROOM_SEATS) {
            const stub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(targetId));
            await stub.fetch(new Request("https://room-seats.internal/clear", { method: "POST" }));
          }
          return json({ ok: true, roomId: targetId, status }, 200, origin, env);
        }
        return json({ error: "admin_route_not_found" }, 404, origin, env);
      } catch (error) {
        console.error("[admin.api] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_operation_failed" }, 500, origin, env);
      }
    }



    if (url.pathname === "/api/v1/auth/google" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const expectedGoogleClientId = env.GOOGLE_CLIENT_ID ?? DEFAULT_GOOGLE_CLIENT_ID;
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      try {
        if (!await checkAuthRateLimit(env.DB, ip)) return json({ error: "too_many_attempts" }, 429, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }

        const idToken = typeof body.idToken === "string" ? body.idToken : "";
        if (!idToken || idToken.length > 10000) return json({ error: "invalid_google_token" }, 401, origin, env);

        // Ask Google's token validation endpoint to verify the signed ID token,
        // then independently enforce this project's audience and identity claims.
        const verifyResponse = await fetch(
          "https://oauth2.googleapis.com/tokeninfo?id_token=" + encodeURIComponent(idToken),
          { headers: { "accept": "application/json" } }
        );
        if (!verifyResponse.ok) return json({ error: "invalid_google_token", message: "تعذر التحقق من حساب Google" }, 401, origin, env);
        const claims = await verifyResponse.json() as Record<string, unknown>;
        const issuer = String(claims.iss ?? "");
        const audience = String(claims.aud ?? "");
        const expiresAt = Number(claims.exp ?? 0);
        const subject = String(claims.sub ?? "");
        const email = String(claims.email ?? "").trim().toLowerCase();
        const emailVerified = claims.email_verified === true || claims.email_verified === "true";
        const displayName = String(claims.name ?? "").trim().slice(0, 50);

        if (
          audience !== expectedGoogleClientId ||
          !["accounts.google.com", "https://accounts.google.com"].includes(issuer) ||
          !Number.isFinite(expiresAt) || expiresAt <= Math.floor(Date.now() / 1000) ||
          !subject || subject.length > 255 ||
          !emailVerified || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
        ) {
          return json({ error: "invalid_google_identity", message: "بيانات حساب Google غير صالحة" }, 401, origin, env);
        }

        let user = await env.DB!.prepare(
          "SELECT u.id, u.email, u.status, p.display_name, p.happy_id FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.auth_provider = 'google' AND u.auth_subject = ? LIMIT 1"
        ).bind(subject).first<{ id: string; email: string; status: string; display_name: string | null; happy_id: string | null }>();

        let isNewUser = false;
        if (!user) {
          const existingEmail = await env.DB!.prepare(
            "SELECT id, auth_provider FROM users WHERE email = ? COLLATE NOCASE LIMIT 1"
          ).bind(email).first<{ id: string; auth_provider: string }>();
          if (existingEmail) {
            return json({
              error: "email_already_registered",
              message: "هذا البريد مرتبط بحساب موجود. سجّل الدخول بالطريقة التي أنشأت بها حسابك أولاً."
            }, 409, origin, env);
          }
          if (body.acceptedTerms !== true) {
            return json({ error: "terms_required", message: "يجب تأكيد العمر والموافقة على الشروط والخصوصية لإنشاء حساب جديد" }, 400, origin, env);
          }

          const userId = crypto.randomUUID();
          let publicId = "";
          for (let attempt = 0; attempt < 20; attempt++) {
            const candidate = String(10000000 + crypto.getRandomValues(new Uint32Array(1))[0] % 90000000);
            const exists = await env.DB!.prepare("SELECT 1 FROM profiles WHERE happy_id = ? LIMIT 1").bind(candidate).first();
            if (!exists) { publicId = candidate; break; }
          }
          if (!publicId) throw new Error("public_id_generation_failed");

          const now = new Date().toISOString();
          try {
            await env.DB!.batch([
              env.DB!.prepare(
                "INSERT INTO users (id, email, password_hash, auth_provider, auth_subject, status, email_verified_at, terms_accepted_at) VALUES (?, ?, NULL, 'google', ?, 'active', ?, ?)"
              ).bind(userId, email, subject, now, now),
              env.DB!.prepare(
                "INSERT INTO profiles (user_id, display_name, happy_id) VALUES (?, ?, ?)"
              ).bind(userId, displayName || email.split("@")[0], publicId)
            ]);
          } catch (error) {
            const racedUser = await env.DB!.prepare(
              "SELECT u.id, u.email, u.status, p.display_name, p.happy_id FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.auth_provider = 'google' AND u.auth_subject = ? LIMIT 1"
            ).bind(subject).first<{ id: string; email: string; status: string; display_name: string | null; happy_id: string | null }>();
            if (!racedUser) throw error;
            user = racedUser;
          }
          if (!user) {
            user = {
              id: userId, email, status: "active",
              display_name: displayName || email.split("@")[0], happy_id: publicId
            };
            isNewUser = true;
          }
        }

        if (user.status !== "active") return json({ error: "account_unavailable", message: "هذا الحساب موقوف حاليًا" }, 403, origin, env);
        user.happy_id = await ensurePublicUserId(env.DB, user.id, user.happy_id);
        const session = await createSession(env.DB, user.id);
        return json({
          ok: true, ...session, isNewUser,
          user: { id: user.id, happy_id: user.happy_id ?? "", email: user.email, name: user.display_name ?? displayName ?? "" }
        }, 200, origin, env);
      } catch (error) {
        console.error("[auth.google] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "google_login_failed", message: "تعذر تسجيل الدخول عبر Google حاليًا" }, 503, origin, env);
      }
    }

    if (url.pathname === "/api/v1/auth/register" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      try {
        if (!await checkAuthRateLimit(env.DB, ip)) return json({ error: "too_many_attempts" }, 429, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        const password = typeof body.password === "string" ? body.password : "";
        const birthday = typeof body.birthday === "string" ? body.birthday : "";
        const acceptedTerms = body.acceptedTerms === true;
        if (name.length < 2 || name.length > 50) return json({ error: "invalid_name", message: "الاسم يجب أن يكون بين حرفين و50 حرفًا" }, 400, origin, env);
        if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "invalid_email", message: "البريد الإلكتروني غير صحيح" }, 400, origin, env);
        if (password.length < 8 || password.length > 128) return json({ error: "invalid_password", message: "كلمة المرور يجب أن تكون 8 أحرف على الأقل" }, 400, origin, env);
        const age = calculateAge(birthday);
        if (age === null || age < 18) return json({ error: "age_restriction", message: "يجب أن يكون عمرك 18 سنة أو أكثر" }, 400, origin, env);
        if (!acceptedTerms) return json({ error: "terms_required", message: "يجب الموافقة على الشروط والأحكام" }, 400, origin, env);

        const userId = crypto.randomUUID();
        let publicId = "";
        for (let attempt = 0; attempt < 10; attempt++) {
          const candidate = String(10000000 + crypto.getRandomValues(new Uint32Array(1))[0] % 90000000);
          const existingId = await env.DB!.prepare("SELECT 1 FROM profiles WHERE happy_id = ? LIMIT 1").bind(candidate).first();
          if (!existingId) {
            publicId = candidate;
            break;
          }
        }
        if (!publicId) throw new Error("public_id_generation_failed");
        const passwordHash = await hashPassword(password);
        const now = new Date().toISOString();
        const sessionToken = `${crypto.randomUUID()}.${crypto.randomUUID()}`;
        const expiresAt = new Date(Date.now() + SESSION_TTL_DAYS * 86400000).toISOString();
        const tokenHash = await sha256(sessionToken);
        try {
          await env.DB!.batch([
            env.DB!.prepare("INSERT INTO users (id, email, password_hash, auth_provider, status, terms_accepted_at) VALUES (?, ?, ?, 'email', 'active', ?)").bind(userId, email, passwordHash, now),
            env.DB!.prepare("INSERT INTO profiles (user_id, display_name, birthday, happy_id) VALUES (?, ?, ?, ?)").bind(userId, name, birthday, publicId),
            env.DB!.prepare("INSERT INTO user_sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)").bind(crypto.randomUUID(), userId, tokenHash, expiresAt)
          ]);
        } catch (error) {
          const existing = await env.DB!.prepare("SELECT id FROM users WHERE email = ? LIMIT 1").bind(email).first();
          if (existing) return json({ error: "email_already_registered", message: "هذا البريد مسجل بالفعل، سجّل الدخول بدلًا من ذلك" }, 409, origin, env);
          throw error;
        }
        return json({ ok: true, accessToken: sessionToken, expiresAt, user: { id: userId, happy_id: publicId, email, name } }, 201, origin, env);
      } catch (error) {
        // Diagnostic only: never log request bodies, email addresses, passwords, or session tokens.
        const diagnostic = error instanceof Error
          ? { name: error.name, message: error.message }
          : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[auth.register] failed", diagnostic);
        return json({ error: "registration_failed", message: "تعذر إنشاء الحساب حاليًا" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/auth/login" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      try {
        if (!await checkAuthRateLimit(env.DB, ip)) return json({ error: "too_many_attempts" }, 429, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        const password = typeof body.password === "string" ? body.password : "";
        if (!email || !password || password.length > 128) return json({ error: "invalid_credentials", message: "البريد أو كلمة المرور غير صحيحة" }, 401, origin, env);
        const user = await env.DB!.prepare(
          "SELECT u.id, u.email, u.password_hash, u.status, p.display_name, p.happy_id FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.email = ? AND u.auth_provider = 'email' LIMIT 1"
        ).bind(email).first<{ id: string; email: string; password_hash: string | null; status: string; display_name: string | null; happy_id: string | null }>();
        if (!user || user.status !== "active" || !user.password_hash || !await verifyPassword(password, user.password_hash)) {
          return json({ error: "invalid_credentials", message: "البريد أو كلمة المرور غير صحيحة" }, 401, origin, env);
        }
        user.happy_id = await ensurePublicUserId(env.DB, user.id, user.happy_id);
        const session = await createSession(env.DB, user.id);
        return json({ ok: true, ...session, user: { id: user.id, happy_id: user.happy_id ?? "", email: user.email, name: user.display_name ?? "" } }, 200, origin, env);
      } catch {
        return json({ error: "login_failed", message: "تعذر تسجيل الدخول حاليًا" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/auth/me" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const profile = await env.DB!.prepare("SELECT display_name, bio, avatar_key, birthday, gender, country_name FROM profiles WHERE user_id = ? LIMIT 1")
          .bind(user.id).first<{ display_name: string; bio: string; avatar_key: string | null; birthday: string | null; gender: string | null; country_name: string | null }>();
        return json({ ok: true, user: {
          id: user.id, happy_id: user.happy_id ?? "", email: user.email,
          name: profile?.display_name ?? user.display_name ?? "", bio: profile?.bio ?? "",
          avatar_url: profile?.avatar_key ?? null, birthday: profile?.birthday ?? "2000-01-01",
          gender: profile?.gender ?? "male", country_name: profile?.country_name ?? ""
        } }, 200, origin, env);
      } catch {
        return json({ error: "session_check_failed" }, 503, origin, env);
      }
    }

    if (url.pathname === "/api/v1/profile" && request.method === "PATCH") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const bio = typeof body.bio === "string" ? body.bio.trim() : "";
        const birthday = typeof body.birthday === "string" ? body.birthday.trim() : "2000-01-01";
        const gender = body.gender === "female" ? "female" : body.gender === "male" ? "male" : "";
        const countryName = typeof body.countryName === "string" ? body.countryName.trim() : "";
        const avatarUrl = body.avatarUrl == null ? null : typeof body.avatarUrl === "string" ? body.avatarUrl.trim() : "";
        if (name.length < 2 || name.length > 30) return json({ error: "invalid_name", message: "الاسم يجب أن يكون بين حرفين و30 حرفًا" }, 400, origin, env);
        if (bio.length > 100) return json({ error: "invalid_bio", message: "النبذة يجب ألا تتجاوز 100 حرف" }, 400, origin, env);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(birthday) || Number.isNaN(Date.parse(birthday)) || Date.parse(birthday) > Date.now()) return json({ error: "invalid_birthday", message: "تاريخ الميلاد غير صالح" }, 400, origin, env);
        if (!gender) return json({ error: "invalid_gender", message: "اختر الجنس بشكل صحيح" }, 400, origin, env);
        if (!countryName || countryName.length > 80) return json({ error: "invalid_country", message: "الدولة غير صالحة" }, 400, origin, env);
        if (avatarUrl !== null) {
          try {
            const parsed = new URL(avatarUrl);
            if (parsed.protocol !== "https:" || !parsed.hostname.endsWith("imagekit.io")) throw new Error("invalid");
          } catch {
            return json({ error: "invalid_avatar_url", message: "رابط الصورة غير صالح" }, 400, origin, env);
          }
        }
        await env.DB!.prepare("UPDATE profiles SET display_name = ?, bio = ?, avatar_key = ?, birthday = ?, gender = ?, country_name = ?, updated_at = ? WHERE user_id = ?")
          .bind(name, bio, avatarUrl, birthday, gender, countryName, new Date().toISOString(), user.id).run();
        return json({ ok: true, user: { id: user.id, happy_id: user.happy_id ?? "", email: user.email, name, bio, avatar_url: avatarUrl, birthday, gender, country_name: countryName } }, 200, origin, env);
      } catch (error) {
        console.error("[profile.update] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "profile_update_failed", message: "تعذر حفظ الملف الشخصي حاليًا" }, 500, origin, env);
      }
    }


    // Authenticated application-wide gift banner stream. The global hub is shared by all signed-in users.
    if (url.pathname === "/api/v1/gifts/global-stream" && request.method === "GET") {
      if (!env.DB || !env.GLOBAL_GIFTS) return json({ error: "global_gift_stream_unavailable" }, 503, origin, env);
      try {
        if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
          return json({ error: "websocket_upgrade_required" }, 426, origin, env);
        }
        const protocols = (request.headers.get("Sec-WebSocket-Protocol") ?? "").split(",").map((value) => value.trim()).filter(Boolean);
        if (!protocols.includes("happy-live-gifts")) return json({ error: "websocket_protocol_required" }, 400, origin, env);
        const streamToken = protocols.find((value) => value !== "happy-live-gifts");
        if (!streamToken || !/^[A-Za-z0-9._~-]{32,512}$/.test(streamToken)) {
          return json({ error: "authentication_required" }, 401, origin, env);
        }
        const authHeaders = new Headers(request.headers);
        authHeaders.set("Authorization", `Bearer ${streamToken}`);
        const user = await authenticatedUser(new Request(request, { headers: authHeaders }), env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const shard = globalGiftShardForUser(user.id);
        const stub = env.GLOBAL_GIFTS.get(env.GLOBAL_GIFTS.idFromName(`application-global-${shard}`));
        return await stub.fetch(new Request("https://global-gifts.internal/connect", {
          method: "GET",
          headers: new Headers({
            "Upgrade": "websocket",
            "Sec-WebSocket-Protocol": "happy-live-gifts"
          })
        }));
      } catch (error) {
        console.error("[gifts.global-stream] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "global_gift_stream_failed" }, 503, origin, env);
      }
    }

    // Authenticated, room-scoped WebSocket for atomic microphone-seat state.
    const seatStreamRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/seat-stream$/);
    if (seatStreamRoute && request.method === "GET") {
      if (!env.DB || !env.ROOM_SEATS) return json({ error: "room_seats_realtime_unavailable" }, 503, origin, env);
      try {
        if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
          return json({ error: "websocket_upgrade_required" }, 426, origin, env);
        }
        const protocols = (request.headers.get("Sec-WebSocket-Protocol") ?? "").split(",").map((value) => value.trim()).filter(Boolean);
        if (!protocols.includes("happy-live-seats")) return json({ error: "websocket_protocol_required" }, 400, origin, env);
        const streamToken = protocols.find((value) => value !== "happy-live-seats");
        if (!streamToken || !/^[A-Za-z0-9._~-]{32,512}$/.test(streamToken)) {
          return json({ error: "authentication_required" }, 401, origin, env);
        }
        const authHeaders = new Headers(request.headers);
        authHeaders.set("Authorization", `Bearer ${streamToken}`);
        const user = await authenticatedUser(new Request(request, { headers: authHeaders }), env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(seatStreamRoute[1]);
        const room = await env.DB!.prepare("SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const now = new Date().toISOString();
        // Keep the room realtime socket available for gifts and room state even
        // when Agora voice is globally disabled. Voice publishing is gated separately.
        const [ban, kick, controlKick, profile, control, moderator, settingsRow] = await Promise.all([
          env.DB!.prepare("SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_kicks WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT avatar_key, country_name FROM profiles WHERE user_id = ? LIMIT 1").bind(user.id).first<{ avatar_key: string | null; country_name: string | null }>(),
          env.DB!.prepare("SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first<{ is_muted: number }>(),
          env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first(),
          env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1").bind(roomId).first<{ settings_json: string }>()
        ]);
        if (kick || controlKick) return json({ error: "room_kicked" }, 403, origin, env);
        if (ban) return json({ error: "room_banned" }, 403, origin, env);
        let roomSettings: Record<string, unknown> = {};
        try { roomSettings = settingsRow?.settings_json ? JSON.parse(settingsRow.settings_json) as Record<string, unknown> : {}; } catch { roomSettings = {}; }
        const isRoomOwner = room.owner_user_id === user.id;
        if (String(roomSettings.whoEnter ?? "everyone") === "ownerAndAdmins" && !isRoomOwner && !moderator) {
          return json({ error: "room_entry_restricted", message: "دخول هذه الغرفة متاح للمالك والمشرفين فقط" }, 403, origin, env);
        }

        const stub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
        await stub.fetch(new Request("https://room-seats.internal/set-mic-policy", {
          method: "POST",
          headers: { "x-who-mic": String(roomSettings.whoMic ?? "membersOnly") }
        }));
        await stub.fetch(new Request("https://room-seats.internal/enable", { method: "POST" }));
        const headers = new Headers({
          "Upgrade": "websocket",
          "Sec-WebSocket-Protocol": "happy-live-seats",
          "x-room-id": roomId,
          "x-user-id": user.id,
          "x-user-name": user.display_name?.trim() || "مستخدم",
          "x-user-code": user.happy_id ?? "",
          "x-avatar-url": profile?.avatar_key ?? "",
          "x-country-name": profile?.country_name ?? "",
          "x-is-muted": control?.is_muted === 1 ? "true" : "false",
          "x-is-room-owner": room.owner_user_id === user.id ? "true" : "false",
          "x-is-room-moderator": moderator ? "true" : "false"
        });
        return await stub.fetch(new Request("https://room-seats.internal/connect", { method: "GET", headers }));
      } catch (error) {
        console.error("[rooms.seat-stream] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_seat_stream_failed" }, 503, origin, env);
      }
    }

    // Authenticated text and image chat scoped to a single active room.
    const chatStreamRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/chat-stream$/);
    if (chatStreamRoute && request.method === "GET") {
      if (!env.DB || !env.ROOM_CHAT) return json({ error: "chat_realtime_unavailable" }, 503, origin, env);
      try {
        if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
          return json({ error: "websocket_upgrade_required" }, 426, origin, env);
        }
        const protocols = (request.headers.get("Sec-WebSocket-Protocol") ?? "").split(",").map((value) => value.trim()).filter(Boolean);
        if (!protocols.includes("happy-live-chat")) {
          return json({ error: "websocket_protocol_required" }, 400, origin, env);
        }
        const streamToken = protocols.find((value) => value !== "happy-live-chat");
        if (!streamToken || !/^[A-Za-z0-9._~-]{32,512}$/.test(streamToken)) {
          return json({ error: "authentication_required" }, 401, origin, env);
        }
        const authHeaders = new Headers(request.headers);
        authHeaders.set("Authorization", `Bearer ${streamToken}`);
        const authRequest = new Request(request, { headers: authHeaders });
        const user = await authenticatedUser(authRequest, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(chatStreamRoute[1]);
        const room = await env.DB!.prepare("SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const [settingsRow, roomModerator] = await Promise.all([
          env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1").bind(roomId).first<{ settings_json: string }>(),
          env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first()
        ]);
        let roomSettings: Record<string, unknown> = {};
        try { roomSettings = settingsRow?.settings_json ? JSON.parse(settingsRow.settings_json) as Record<string, unknown> : {}; } catch { roomSettings = {}; }
        if (String(roomSettings.whoEnter ?? "everyone") === "ownerAndAdmins" && room.owner_user_id !== user.id && !roomModerator) {
          return json({ error: "room_entry_restricted", message: "دخول هذه الغرفة متاح للمالك والمشرفين فقط" }, 403, origin, env);
        }
        if (String(roomSettings.whoChat ?? "everyone") === "ownerAndAdmins" && room.owner_user_id !== user.id && !roomModerator) {
          return json({ error: "room_chat_restricted", message: "الدردشة متاحة للمالك والمشرفين فقط" }, 403, origin, env);
        }
        const visit = await env.DB!.prepare(
          "SELECT id FROM room_chat_visits WHERE room_id = ? AND user_id = ? AND exited_at IS NULL ORDER BY entered_at DESC LIMIT 1"
        ).bind(roomId, user.id).first<{ id: string }>();
        if (!visit) return json({ error: "chat_session_not_active" }, 409, origin, env);
        const id = env.ROOM_CHAT.idFromName(roomId);
        const stub = env.ROOM_CHAT.get(id);
        const upgradeHeaders = new Headers({ "Upgrade": "websocket", "Sec-WebSocket-Protocol": "happy-live-chat" });
        return await stub.fetch(new Request("https://room-chat.internal/connect", { method: "GET", headers: upgradeHeaders }));
      } catch (error) {
        console.error("[rooms.chat-stream] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "chat_stream_failed" }, 503, origin, env);
      }
    }

    const chatSessionRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/chat-session$/);
    if (chatSessionRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(chatSessionRoute[1]);
        const room = await env.DB!.prepare(
          "SELECT id, owner_user_id, COALESCE(locked, 0) AS locked FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string; locked: number }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const [entrySettingsRow, entryModerator] = await Promise.all([
          env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1").bind(roomId).first<{ settings_json: string }>(),
          env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first()
        ]);
        let entrySettings: Record<string, unknown> = {};
        try { entrySettings = entrySettingsRow?.settings_json ? JSON.parse(entrySettingsRow.settings_json) as Record<string, unknown> : {}; } catch { entrySettings = {}; }
        if (String(entrySettings.whoEnter ?? "everyone") === "ownerAndAdmins" && room.owner_user_id !== user.id && !entryModerator) {
          return json({ error: "room_entry_restricted", message: "دخول هذه الغرفة متاح للمالك والمشرفين فقط" }, 403, origin, env);
        }
        const activeBan = await env.DB!.prepare(
          "SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, user.id).first<{ user_id: string }>();
        const activeKick = await env.DB!.prepare(
          "SELECT kicked_until FROM room_kicks WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1"
        ).bind(roomId, user.id, new Date().toISOString()).first<{ kicked_until: string }>();
        const controlKick = await env.DB!.prepare(
          "SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1"
        ).bind(roomId, user.id, new Date().toISOString()).first<{ kicked_until: string }>();
        if (activeKick || controlKick) return json({ error: "room_kicked", message: "تم طردك مؤقتاً من الغرفة" }, 403, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const action = body.action === "leave" ? "leave" : body.action === "join" ? "join" : "";
        if (!action) return json({ error: "invalid_chat_session_action" }, 400, origin, env);
        if (action === "join" && room.locked === 1 && room.owner_user_id !== user.id && !entryModerator) {
          const password = typeof body.password === "string" ? body.password : "";
          const saltHex = typeof entrySettings.roomPasswordSalt === "string" ? entrySettings.roomPasswordSalt : "";
          const hashExpected = typeof entrySettings.roomPasswordHash === "string" ? entrySettings.roomPasswordHash : "";
          if (!/^\\d{6}$/.test(password) || !/^[0-9a-f]{32}$/i.test(saltHex) || !/^[0-9a-f]{64}$/i.test(hashExpected)) {
            return json({ error: "room_password_required", message: "أدخل كلمة مرور الغرفة المكوّنة من 6 أرقام" }, 423, origin, env);
          }
          const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map((byte) => parseInt(byte, 16)));
          const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
          const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 120000, hash: "SHA-256" }, key, 256);
          const actual = Array.from(new Uint8Array(bits)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
          if (actual !== hashExpected) return json({ error: "room_password_incorrect", message: "كلمة المرور غير صحيحة" }, 403, origin, env);
        }
        const now = new Date().toISOString();
        if (action === "join") {
          // A new visit starts with a clean view of chat history. Any abandoned
          // visit (for example after a closed browser tab) is ended first.
          await env.DB!.prepare(
            "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
          ).bind(now, roomId, user.id).run();
          const visitId = crypto.randomUUID();
          await env.DB!.prepare(
            "INSERT INTO room_chat_visits (id, room_id, user_id, entered_at, last_seen_at) VALUES (?, ?, ?, ?, ?)"
          ).bind(visitId, roomId, user.id, now, now).run();
          const entryMessageId = crypto.randomUUID();
          const entryProfile = await env.DB!.prepare(
            "SELECT avatar_key FROM profiles WHERE user_id = ? LIMIT 1"
          ).bind(user.id).first<{ avatar_key: string | null }>();
          const entryMessage = {
            id: entryMessageId,
            userId: user.id,
            name: user.display_name?.trim() || "مستخدم",
            avatarUrl: entryProfile?.avatar_key ?? "",
            message: "انضم للغرفة",
            imageUrl: null,
            createdAt: now,
            isMe: false
          };
          // Chat is live-only; preserve legacy message rows in every room.
          // Broadcast this join event only to users currently connected.
          await broadcastRoomChat(env, roomId, {
            type: "system",
            message: entryMessage
          });
          return json({ ok: true, enteredAt: now }, 200, origin, env);
        }
        await env.DB!.prepare(
          "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
        ).bind(now, roomId, user.id).run();
        const exitProfile = await env.DB!.prepare(
          "SELECT avatar_key FROM profiles WHERE user_id = ? LIMIT 1"
        ).bind(user.id).first<{ avatar_key: string | null }>();
        await broadcastRoomChat(env, roomId, {
          type: "system",
          message: {
            id: crypto.randomUUID(), userId: user.id,
            name: user.display_name?.trim() || "مستخدم",
            avatarUrl: exitProfile?.avatar_key ?? "",
            message: "غادر الغرفة", imageUrl: null, createdAt: now, isMe: false
          }
        });
        return json({ ok: true }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.chat-session] failed", diagnostic);
        return json({ error: "room_chat_session_failed" }, 500, origin, env);
      }
    }

    const chatRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/messages$/);
    if (chatRoute && (request.method === "GET" || request.method === "POST" || request.method === "DELETE")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(chatRoute[1]);
        const room = await env.DB!.prepare(
          "SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const visit = await env.DB!.prepare(
          "SELECT entered_at FROM room_chat_visits WHERE room_id = ? AND user_id = ? AND exited_at IS NULL ORDER BY entered_at DESC LIMIT 1"
        ).bind(roomId, user.id).first<{ entered_at: string }>();
        if (!visit) return json({ error: "chat_session_not_active" }, 409, origin, env);

        if (request.method === "DELETE") {
          const moderator = await env.DB!.prepare(
            "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
          ).bind(roomId, user.id).first();
          if (room.owner_user_id !== user.id && !moderator) {
            return json({ error: "room_moderator_required", message: "مسح الدردشة متاح لمالك الغرفة والمشرفين فقط" }, 403, origin, env);
          }
          await broadcastRoomChat(env, roomId, {
            type: "clear_chat",
            clearedBy: user.id,
            clearedAt: new Date().toISOString()
          });
          return json({ ok: true, cleared: true }, 200, origin, env);
        }

        if (request.method === "POST") {
          const [settingsRow, roomModerator] = await Promise.all([
            env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1").bind(roomId).first<{ settings_json: string }>(),
            env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first()
          ]);
          let roomSettings: Record<string, unknown> = {};
          try { roomSettings = settingsRow?.settings_json ? JSON.parse(settingsRow.settings_json) as Record<string, unknown> : {}; } catch { roomSettings = {}; }
          if (String(roomSettings.whoChat ?? "everyone") === "ownerAndAdmins" && room.owner_user_id !== user.id && !roomModerator) {
            return json({ error: "room_chat_restricted", message: "الدردشة متاحة للمالك والمشرفين فقط" }, 403, origin, env);
          }
          const activeBan = await env.DB!.prepare(
            "SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1"
          ).bind(roomId, user.id).first<{ user_id: string }>();
          if (activeBan) return json({ error: "room_banned", message: "أنت محظور من الكتابة في هذه الغرفة" }, 403, origin, env);
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }
          const message = typeof body.message === "string" ? body.message.trim() : "";
          const imageUrl = typeof body.imageUrl === "string" ? body.imageUrl.trim() : "";
          if (message.length > 200) return json({ error: "message_too_long", message: "الرسالة يجب ألا تتجاوز 200 حرف" }, 400, origin, env);
          if (imageUrl) {
            try {
              const parsed = new URL(imageUrl);
              if (parsed.protocol !== "https:" || !parsed.hostname.endsWith("imagekit.io")) {
                return json({ error: "invalid_message_image" }, 400, origin, env);
              }
            } catch {
              return json({ error: "invalid_message_image" }, 400, origin, env);
            }
          }
          if (!message && !imageUrl) return json({ error: "empty_message" }, 400, origin, env);
          const now = new Date().toISOString();
          const cutoff = new Date(Date.now() - 1000).toISOString();
          const rate = await env.DB!.prepare(
            "INSERT INTO room_chat_rate_limits (room_id, user_id, last_sent_at) VALUES (?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET last_sent_at = excluded.last_sent_at WHERE room_chat_rate_limits.last_sent_at <= ? RETURNING last_sent_at"
          ).bind(roomId, user.id, now, cutoff).first<{ last_sent_at: string }>();
          if (!rate) return json({ error: "chat_rate_limited", message: "انتظر ثانية قبل إرسال رسالة أخرى" }, 429, origin, env);
          const senderProfile = await env.DB!.prepare(
            "SELECT avatar_key FROM profiles WHERE user_id = ? LIMIT 1"
          ).bind(user.id).first<{ avatar_key: string | null }>();
          const id = crypto.randomUUID();
          const createdMessage = {
            id, userId: user.id, name: user.display_name?.trim() || "مستخدم",
            avatarUrl: senderProfile?.avatar_key ?? "",
            message, imageUrl: imageUrl || null, createdAt: now, isMe: false
          };
          // Never write chat content to D1. Deliver it only to live room sockets.
          await broadcastRoomChat(env, roomId, { type: "message", message: createdMessage });
          // Echo only this just-sent message to its sender; never return room history.
          return json({ ok: true, messages: [createdMessage], enteredAt: visit.entered_at }, 200, origin, env);
        }

        // A new visit always starts with an empty chat view.
        return json({ ok: true, messages: [], enteredAt: visit.entered_at }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.messages] failed", diagnostic);
        return json({ error: "room_messages_failed" }, 500, origin, env);
      }
    }

    // Only the authenticated room owner can update the persistent room announcement.
    const announcementRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/announcement$/);
    if (announcementRoute && request.method === "PATCH") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(announcementRoute[1]);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const announcement = typeof body.announcement === "string" ? body.announcement.trim() : null;
        if (announcement === null) return json({ error: "invalid_announcement" }, 400, origin, env);
        if (announcement.length > 200) return json({ error: "announcement_too_long", message: "الإعلان يجب ألا يتجاوز 200 حرف" }, 400, origin, env);
        const room = await env.DB!.prepare(
          "SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        if (room.owner_user_id !== user.id) return json({ error: "room_owner_only", message: "تعديل الإعلان متاح لمالك الغرفة فقط" }, 403, origin, env);
        const updatedAt = new Date().toISOString();
        await env.DB!.prepare(
          "INSERT INTO room_announcements (room_id, announcement, updated_at) VALUES (?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET announcement = excluded.announcement, updated_at = excluded.updated_at"
        ).bind(roomId, announcement, updatedAt).run();
        const now = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, action, details_json, created_at) VALUES (?, ?, ?, 'setting.update', ?, ?)")
          .bind(crypto.randomUUID(), roomId, user.id, JSON.stringify({ key: "announcement", value: announcement }), now).run();
        const announcementMessage = {
          id: crypto.randomUUID(), userId: user.id,
          name: user.display_name?.trim() || "مالك الغرفة",
          senderId: user.id, senderName: user.display_name?.trim() || "مالك الغرفة",
          message: announcement, text: announcement, imageUrl: null, createdAt: now, isMe: false
        };
        await broadcastRoomChat(env, roomId, { type: "announcement", message: announcementMessage });
        return json({ ok: true, announcement, updatedAt: now }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.announcement] failed", diagnostic);
        return json({ error: "room_announcement_failed" }, 500, origin, env);
      }
    }

    // Authenticated wallet balance and immutable transaction history.
    if (url.pathname === "/api/v1/gifts/catalog" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const tab = url.searchParams.get("tab");
        if (tab && !["event", "trending", "country", "lucky", "custom"].includes(tab)) return json({ error: "invalid_gift_category" }, 400, origin, env);
        let countryCode: string | null = null;
        if (tab === "country") {
          const user = await authenticatedUser(request, env.DB);
          if (!user) return json({ error: "authentication_required" }, 401, origin, env);
          const profile = await env.DB!.prepare("SELECT country_code, country_name FROM profiles WHERE user_id = ? LIMIT 1").bind(user.id).first<{ country_code: string | null; country_name: string | null }>();
          const countryName = (profile?.country_name ?? "").trim().toUpperCase();
          countryCode = ["SOUTH_ARABIA", "SOUTH ARABIA", "الجنوب العربي"].includes(countryName)
            ? "SOUTH_ARABIA"
            : profile?.country_code?.trim().toUpperCase() ?? null;
          if (!countryCode) return json({ ok: true, gifts: [], countryCode: null }, 200, origin, env);
        }
        const now = new Date().toISOString();
        const rows = await env.DB!.prepare(
          "SELECT id, name, icon_emoji AS iconEmoji, media_url AS mediaUrl, media_type AS mediaType, thumbnail_url AS thumbnailUrl, sound_url AS soundUrl, duration_seconds AS durationSeconds, coin_price AS coinPrice, sort_order AS sortOrder, category, country_code AS countryCode, starts_at AS startsAt, ends_at AS endsAt " +
          "FROM gift_catalog WHERE is_active = 1 AND (starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?) " +
          "AND (? IS NULL OR category = ?) AND (category <> 'country' OR country_code = ?) ORDER BY sort_order ASC, created_at ASC"
        ).bind(now, now, tab, tab, countryCode).all();
        return json({ ok: true, gifts: rows.results ?? [], countryCode }, 200, origin, env);
      } catch (error) {
        console.error("[gifts.catalog] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "gift_catalog_unavailable" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/gifts/custom-requests" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const requestedName = typeof body.requestedName === "string" ? body.requestedName.trim() : "";
        const description = typeof body.description === "string" ? body.description.trim() : "";
        const mediaUrl = typeof body.mediaUrl === "string" ? body.mediaUrl.trim() : "";
        const mediaType = typeof body.mediaType === "string" ? body.mediaType.trim().toLowerCase() : "";
        const mediaFileId = typeof body.mediaFileId === "string" ? body.mediaFileId.trim() : "";
        const mediaDurationMs = Number(body.mediaDurationMs);
        const soundUrl = typeof body.soundUrl === "string" ? body.soundUrl.trim() : "";
        const soundFileId = typeof body.soundFileId === "string" ? body.soundFileId.trim() : "";
        if (requestedName.length < 2 || requestedName.length > 80 || description.length > 500) return json({ error: "invalid_custom_gift_request", message: "اكتب اسم الهدية ووصفًا لا يتجاوز 500 حرف." }, 400, origin, env);
        const hasMedia = Boolean(mediaUrl || mediaType || mediaFileId || body.mediaDurationMs !== undefined);
        let parsedMediaUrl: URL | null = null;
        if (hasMedia) {
          try { parsedMediaUrl = new URL(mediaUrl); } catch { parsedMediaUrl = null; }
          if (!parsedMediaUrl || parsedMediaUrl.protocol !== "https:" || parsedMediaUrl.hostname !== "ik.imagekit.io" ||
              !["gif", "svga"].includes(mediaType) || !mediaFileId || !Number.isInteger(mediaDurationMs) ||
              mediaDurationMs < 1 || mediaDurationMs > 5000) {
            return json({ error: "invalid_custom_gift_media", message: "يُسمح بملفات GIF أو SVGA فقط، وبمدة لا تتجاوز 5 ثوانٍ، عبر ImageKit." }, 400, origin, env);
          }
          const mediaPath = parsedMediaUrl.pathname + parsedMediaUrl.search;
          if ((mediaType === "gif" && !/\.gif(?:$|[?#])/i.test(mediaPath)) ||
              (mediaType === "svga" && !/\.svga(?:$|[?#])/i.test(mediaPath))) {
            return json({ error: "invalid_custom_gift_media_type" }, 400, origin, env);
          }
          // Confirm that the submitted URL and file ID belong to a real ImageKit upload.
          if (!env.IMAGEKIT_PRIVATE_KEY?.trim()) return json({ error: "imagekit_not_configured" }, 503, origin, env);
          // Both the upload-signing endpoint and this lookup use this exact Worker
          // IMAGEKIT_PRIVATE_KEY. ImageKit's file-management index can lag behind a
          // successful upload, so allow a longer bounded window for a fresh file to appear.
          let imageKitFileResponse: Response | null = null;
          const lookupDelaysMs = [400, 700, 1000, 1300, 1600, 2000, 2500];
          for (let attempt = 0; attempt <= lookupDelaysMs.length; attempt++) {
            imageKitFileResponse = await fetch("https://api.imagekit.io/v1/files/" + encodeURIComponent(mediaFileId) + "/details", {
              headers: { Authorization: "Basic " + btoa(env.IMAGEKIT_PRIVATE_KEY.trim() + ":") }
            });
            if (imageKitFileResponse.ok || (imageKitFileResponse.status !== 404 && imageKitFileResponse.status < 500)) break;
            if (attempt < lookupDelaysMs.length) {
              await new Promise(resolve => setTimeout(resolve, lookupDelaysMs[attempt]));
            }
          }
          if (!imageKitFileResponse?.ok) {
            const providerStatus = imageKitFileResponse?.status ?? 0;
            let providerMessage = "";
            try {
              const providerBody = await imageKitFileResponse!.json() as Record<string, unknown>;
              providerMessage = String(providerBody.message ?? providerBody.help ?? providerBody.error ?? "").slice(0, 240);
            } catch {
              try { providerMessage = (await imageKitFileResponse!.text()).slice(0, 240); } catch { /* no provider body */ }
            }
            const credentialsRejected = providerStatus === 401 || providerStatus === 403;
            return json({
              error: credentialsRejected ? "imagekit_credentials_invalid" : providerStatus === 404 ? "imagekit_file_not_found" : "imagekit_file_lookup_failed",
              message: credentialsRejected
                ? "مفاتيح ImageKit في الخادم لا تملك صلاحية التحقق من الملف. تأكد من تطابق المفتاحين العام والخاص."
                : providerStatus === 404
                  ? "تم رفع الملف، لكن ImageKit لم يعثر على معرّفه بعد إعادة المحاولة. تحقق من أن الرفع والتحقق يستخدمان حساب ImageKit نفسه."
                  : "تعذر التحقق من الملف لدى ImageKit. حاول مرة أخرى.",
              providerStatus,
              providerMessage
            }, 400, origin, env);
          }
          const imageKitFile = await imageKitFileResponse.json() as Record<string, unknown>;
          const uploadedName = typeof imageKitFile.name === "string" ? imageKitFile.name : "";
          const uploadedUrl = typeof imageKitFile.url === "string" ? imageKitFile.url : "";
          const uploadedPath = typeof imageKitFile.filePath === "string" ? imageKitFile.filePath : "";
          const expectedExtension = mediaType === "gif" ? /\.gif$/i : /\.svga$/i;
          let uploadedUrlMatches = false;
          try {
            const verifiedUrl = new URL(uploadedUrl);
            const submittedUrl = new URL(mediaUrl);
            const verifiedPath = decodeURIComponent(verifiedUrl.pathname).replace(/\/+$/, "");
            const submittedPath = decodeURIComponent(submittedUrl.pathname).replace(/\/+$/, "");
            uploadedUrlMatches = verifiedUrl.protocol === "https:" && verifiedUrl.hostname === "ik.imagekit.io" &&
              submittedUrl.protocol === "https:" && submittedUrl.hostname === "ik.imagekit.io" &&
              verifiedPath === submittedPath;
          } catch {
            uploadedUrlMatches = false;
          }
          const extensionMatches = [uploadedName, uploadedPath, uploadedUrl].some(value => {
            if (!value) return false;
            try {
              const path = value.startsWith("https://") ? new URL(value).pathname : value.split(/[?#]/, 1)[0];
              return expectedExtension.test(path);
            } catch {
              return false;
            }
          });
          const uploadedSize = Number(imageKitFile.size);
          if (imageKitFile.fileId !== mediaFileId || !uploadedUrlMatches || !extensionMatches ||
              !Number.isFinite(uploadedSize) || uploadedSize < 1 || uploadedSize > 10 * 1024 * 1024) {
            return json({ error: "imagekit_file_validation_failed" }, 400, origin, env);
          }
        }
        if (Boolean(soundUrl) !== Boolean(soundFileId)) {
          return json({ error: "invalid_custom_gift_sound", message: "ارفع ملف الصوت MP3 من نفس النموذج أو اتركه فارغًا." }, 400, origin, env);
        }
        if (soundUrl || soundFileId) {
          let parsedSoundUrl: URL | null = null;
          try { parsedSoundUrl = new URL(soundUrl); } catch { parsedSoundUrl = null; }
          if (!parsedSoundUrl || parsedSoundUrl.protocol !== "https:" || parsedSoundUrl.hostname !== "ik.imagekit.io" ||
              !/\.mp3$/i.test(parsedSoundUrl.pathname) || !/^[A-Za-z0-9_-]{5,160}$/.test(soundFileId)) {
            return json({ error: "invalid_custom_gift_sound", message: "ملف الصوت يجب أن يكون MP3 مرفوعًا عبر ImageKit." }, 400, origin, env);
          }
          if (!env.IMAGEKIT_PRIVATE_KEY?.trim()) return json({ error: "imagekit_not_configured" }, 503, origin, env);
          let soundLookup: Response | null = null;
          const soundLookupDelaysMs = [400, 700, 1000, 1300, 1600, 2000, 2500];
          for (let attempt = 0; attempt <= soundLookupDelaysMs.length; attempt++) {
            soundLookup = await fetch("https://api.imagekit.io/v1/files/" + encodeURIComponent(soundFileId) + "/details", {
              headers: { Authorization: "Basic " + btoa(env.IMAGEKIT_PRIVATE_KEY.trim() + ":") }
            });
            if (soundLookup.ok || (soundLookup.status !== 404 && soundLookup.status < 500)) break;
            if (attempt < soundLookupDelaysMs.length) await new Promise(resolve => setTimeout(resolve, soundLookupDelaysMs[attempt]));
          }
          if (!soundLookup?.ok) {
            const status = soundLookup?.status ?? 0;
            return json({
              error: status === 401 || status === 403 ? "imagekit_credentials_invalid" : status === 404 ? "imagekit_file_not_found" : "imagekit_file_lookup_failed",
              message: status === 404
                ? "تم رفع الصوت، لكن ImageKit لم يعثر على معرّفه بعد إعادة المحاولة. تحقق من تطابق حساب الرفع والتحقق."
                : "تعذر التحقق من ملف الصوت في ImageKit. حاول مرة أخرى.",
              providerStatus: status
            }, 400, origin, env);
          }
          const uploadedSound = await soundLookup.json() as Record<string, unknown>;
          const uploadedSoundUrl = typeof uploadedSound.url === "string" ? uploadedSound.url : "";
          const uploadedSoundName = typeof uploadedSound.name === "string" ? uploadedSound.name : "";
          const uploadedSoundPath = typeof uploadedSound.filePath === "string" ? uploadedSound.filePath : "";
          let soundUrlMatches = false;
          try {
            const verified = new URL(uploadedSoundUrl), submitted = new URL(soundUrl);
            soundUrlMatches = verified.protocol === "https:" && verified.hostname === "ik.imagekit.io" &&
              submitted.protocol === "https:" && submitted.hostname === "ik.imagekit.io" &&
              decodeURIComponent(verified.pathname).replace(/\/+$/, "") === decodeURIComponent(submitted.pathname).replace(/\/+$/, "");
          } catch { soundUrlMatches = false; }
          const soundExtensionMatches = [uploadedSoundName, uploadedSoundPath, uploadedSoundUrl].some(value => {
            if (!value) return false;
            try { return /\.mp3$/i.test(value.startsWith("https://") ? new URL(value).pathname : value.split(/[?#]/, 1)[0]); }
            catch { return false; }
          });
          const soundSize = Number(uploadedSound.size);
          if (uploadedSound.fileId !== soundFileId || !soundUrlMatches || !soundExtensionMatches ||
              !Number.isFinite(soundSize) || soundSize < 1 || soundSize > 5 * 1024 * 1024) {
            return json({ error: "imagekit_file_validation_failed", message: "تعذر مطابقة ملف الصوت مع الملف المرفوع." }, 400, origin, env);
          }
        }
        const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
        const recent = await env.DB!.prepare("SELECT COUNT(*) AS count FROM gift_custom_requests WHERE user_id = ? AND created_at >= ?").bind(user.id, since).first<{ count: number }>();
        if (Number(recent?.count ?? 0) >= 5) return json({ error: "custom_gift_request_limit" }, 429, origin, env);
        const id = crypto.randomUUID(), now = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO gift_custom_requests (id, user_id, requested_name, description, media_url, media_type, media_duration_ms, media_file_id, sound_url, sound_file_id, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)")
          .bind(id, user.id, requestedName, description, hasMedia ? mediaUrl : null, hasMedia ? mediaType : null, hasMedia ? mediaDurationMs : null, hasMedia ? mediaFileId : null, soundUrl || null, soundFileId || null, now).run();
        return json({ ok: true, request: { id, requestedName, description, mediaUrl, mediaType, mediaDurationMs, mediaFileId, soundUrl: soundUrl || null, status: "pending", createdAt: now } }, 201, origin, env);
      } catch (error) {
        console.error("[gifts.custom-request] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "custom_gift_request_failed" }, 500, origin, env);
      }
    }

    // Battle state is controlled by the room owner or a room-scoped moderator.
    // Gift XP reads this server-side state; client flags can never enable the 2x multiplier.
    // Authenticated PK lifecycle and durable score snapshot.
    const roomBattleRoute = url.pathname.match(/^\/api\/v1\/rooms\/([0-9a-f-]{36})\/battle$/i);
    if (roomBattleRoute && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedUser(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = roomBattleRoute[1];
        const room = await env.DB.prepare("SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);

        if (request.method === "GET") {
          let activeBattle = await env.DB.prepare(
            "SELECT id, started_at AS startedAt, duration_seconds AS durationSeconds, expires_at AS expiresAt " +
            "FROM room_battles WHERE room_id = ? AND status = 'active' LIMIT 1"
          ).bind(roomId).first<{ id: string; startedAt: string; durationSeconds: number; expiresAt: string | null }>();
          let expiredBattleId: string | null = null;
          let expiredBattleDurationSeconds = 300;
          if (activeBattle) {
            const expiresAt = activeBattle.expiresAt ??
              new Date(Date.parse(activeBattle.startedAt) + Number(activeBattle.durationSeconds || 300) * 1000).toISOString();
            if (Date.parse(expiresAt) <= Date.now()) {
              const now = new Date().toISOString();
              expiredBattleId = activeBattle.id;
              expiredBattleDurationSeconds = Number(activeBattle.durationSeconds || 300);
              await env.DB.prepare("UPDATE room_battles SET status = 'finished', ended_at = ?, expires_at = COALESCE(expires_at, ?) WHERE id = ? AND status = 'active'")
                .bind(now, expiresAt, activeBattle.id).run();
              activeBattle = null;
            } else if (!activeBattle.expiresAt) {
              await env.DB.prepare("UPDATE room_battles SET expires_at = ? WHERE id = ? AND status = 'active'")
                .bind(expiresAt, activeBattle.id).run();
            }
          }
          if (!env.ROOM_SEATS) return json({ error: "room_seats_unavailable" }, 503, origin, env);
          const hub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          if (activeBattle || expiredBattleId) {
            const battle = activeBattle;
            const stateResponse = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
              method: "POST",
              headers: { "Content-Type": "application/json", "x-room-id": roomId },
              body: JSON.stringify({
                teamMode: true, active: battle != null,
                battleId: battle?.id ?? expiredBattleId,
                endsAt: battle
                  ? (battle.expiresAt ?? new Date(Date.parse(battle.startedAt) + Number(battle.durationSeconds || 300) * 1000).toISOString())
                  : null,
                durationSeconds: Number(battle?.durationSeconds || expiredBattleDurationSeconds)
              })
            }));
            if (!stateResponse.ok) return json({ error: "room_battle_state_sync_failed" }, 503, origin, env);
          }
          const stateResponse = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
            headers: { "x-room-id": roomId }
          }));
          const state = await stateResponse.json().catch(() => null) as Record<string, unknown> | null;
          if (!stateResponse.ok || !state) return json({ error: "room_battle_state_unavailable" }, 503, origin, env);
          return json({ ok: true, ...state }, 200, origin, env);
        }

        const moderator = await env.DB.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1")
          .bind(roomId, actor.id).first<{ user_id: string }>();
        if (room.owner_user_id !== actor.id && !moderator) return json({ error: "room_moderator_permission_required" }, 403, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const action = body.action;
        if (action !== "prepare" && action !== "start" && action !== "end" && action !== "reset") {
          return json({ error: "invalid_battle_action" }, 400, origin, env);
        }
        const pkConfigRow = await env.DB.prepare("SELECT setting_value FROM platform_settings WHERE setting_key = 'pk_battle_settings' LIMIT 1")
          .first<{ setting_value: string }>();
        let pkConfig: Record<string, unknown> = {};
        try { pkConfig = pkConfigRow?.setting_value ? JSON.parse(pkConfigRow.setting_value) as Record<string, unknown> : {}; } catch { pkConfig = {}; }
        if (pkConfig.enabled === false && (action === "prepare" || action === "start")) {
          return json({ error: "pk_disabled_by_admin", message: "تحدي PK متوقف من الإدارة" }, 403, origin, env);
        }
        const configuredDurationOptions = Array.isArray(pkConfig.durationOptions)
          ? pkConfig.durationOptions.map(Number).filter((n) => Number.isInteger(n) && n >= 1 && n <= 120)
          : [5, 15, 30, 120];
        const configuredDefaultDuration = Number(pkConfig.defaultDurationMinutes ?? 5);

        if (!env.ROOM_SEATS) return json({ error: "room_seats_unavailable" }, 503, origin, env);
        const hub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
        const now = new Date().toISOString();

        if (action === "prepare") {
          let activeBattle = await env.DB.prepare(
            "SELECT id, started_at AS startedAt, duration_seconds AS durationSeconds, expires_at AS expiresAt FROM room_battles WHERE room_id = ? AND status = 'active' LIMIT 1"
          ).bind(roomId).first<{ id: string; startedAt: string; durationSeconds: number; expiresAt: string | null }>();
          if (activeBattle) {
            const expiresAt = activeBattle.expiresAt ?? new Date(Date.parse(activeBattle.startedAt) + Number(activeBattle.durationSeconds || 300) * 1000).toISOString();
            if (Date.parse(expiresAt) <= Date.now()) {
              await env.DB.prepare("UPDATE room_battles SET status = 'finished', ended_at = ?, expires_at = COALESCE(expires_at, ?) WHERE id = ? AND status = 'active'")
                .bind(now, expiresAt, activeBattle.id).run();
              activeBattle = null;
            }
          }
          if (activeBattle) {
            const expiresAt = activeBattle.expiresAt ?? new Date(Date.parse(activeBattle.startedAt) + Number(activeBattle.durationSeconds || 300) * 1000).toISOString();
            const response = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
              method: "POST", headers: { "Content-Type": "application/json", "x-room-id": roomId },
              body: JSON.stringify({ teamMode: true, active: true, battleId: activeBattle.id, endsAt: expiresAt, durationSeconds: Number(activeBattle.durationSeconds || 300) })
            }));
            if (!response.ok) return json({ error: "room_battle_state_sync_failed" }, 503, origin, env);
            return json({ ok: true, teamMode: true, active: true, battleId: activeBattle.id, endsAt: expiresAt, durationSeconds: Number(activeBattle.durationSeconds || 300) }, 200, origin, env);
          }
          const durationMinutes = Number(body.durationMinutes ?? configuredDefaultDuration);
          if (!configuredDurationOptions.includes(durationMinutes)) return json({ error: "invalid_battle_duration" }, 400, origin, env);
          const response = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
            method: "POST", headers: { "Content-Type": "application/json", "x-room-id": roomId },
            body: JSON.stringify({ teamMode: true, active: false, battleId: null, endsAt: null, durationSeconds: durationMinutes * 60 })
          }));
          if (!response.ok) return json({ error: "room_battle_state_sync_failed" }, 503, origin, env);
          return json({ ok: true, teamMode: true, active: false, battleId: null, endsAt: null, durationSeconds: durationMinutes * 60 }, 200, origin, env);
        }

        if (action === "start") {
          const durationMinutes = Number(body.durationMinutes ?? configuredDefaultDuration);
          if (!configuredDurationOptions.includes(durationMinutes)) return json({ error: "invalid_battle_duration" }, 400, origin, env);
          let activeBattle = await env.DB.prepare(
            "SELECT id, started_at AS startedAt, duration_seconds AS durationSeconds, expires_at AS expiresAt FROM room_battles WHERE room_id = ? AND status = 'active' LIMIT 1"
          ).bind(roomId).first<{ id: string; startedAt: string; durationSeconds: number; expiresAt: string | null }>();
          if (activeBattle) {
            const oldExpiry = activeBattle.expiresAt ?? new Date(Date.parse(activeBattle.startedAt) + Number(activeBattle.durationSeconds || 300) * 1000).toISOString();
            if (Date.parse(oldExpiry) <= Date.now()) {
              await env.DB.prepare("UPDATE room_battles SET status = 'finished', ended_at = ?, expires_at = COALESCE(expires_at, ?) WHERE id = ? AND status = 'active'")
                .bind(now, oldExpiry, activeBattle.id).run();
              activeBattle = null;
            }
          }
          if (!activeBattle) {
            const battleId = crypto.randomUUID();
            const expiresAt = new Date(Date.now() + durationMinutes * 60_000).toISOString();
            const created = await env.DB.prepare(
              "INSERT OR IGNORE INTO room_battles (id, room_id, status, started_at, ended_at, created_by_user_id, duration_seconds, expires_at) " +
              "SELECT ?, ?, 'active', ?, NULL, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM room_battles WHERE room_id = ? AND status = 'active')"
            ).bind(battleId, roomId, now, actor.id, durationMinutes * 60, expiresAt, roomId).run();
            if ((created.meta?.changes ?? 0) === 1) {
              activeBattle = { id: battleId, startedAt: now, durationSeconds: durationMinutes * 60, expiresAt };
            } else {
              activeBattle = await env.DB.prepare(
                "SELECT id, started_at AS startedAt, duration_seconds AS durationSeconds, expires_at AS expiresAt " +
                "FROM room_battles WHERE room_id = ? AND status = 'active' LIMIT 1"
              ).bind(roomId).first<{ id: string; startedAt: string; durationSeconds: number; expiresAt: string | null }>();
              if (!activeBattle) return json({ error: "battle_state_conflict" }, 409, origin, env);
            }
          }
          const expiresAt = activeBattle.expiresAt ?? new Date(Date.parse(activeBattle.startedAt) + Number(activeBattle.durationSeconds || 300) * 1000).toISOString();
          const response = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
            method: "POST", headers: { "Content-Type": "application/json", "x-room-id": roomId },
            body: JSON.stringify({
              teamMode: true, active: true, battleId: activeBattle.id,
              endsAt: expiresAt, durationSeconds: Number(activeBattle.durationSeconds || durationMinutes * 60)
            })
          }));
          if (!response.ok) return json({ error: "room_battle_state_sync_failed" }, 503, origin, env);
          return json({
            ok: true, teamMode: true, active: true, battleId: activeBattle.id,
            startedAt: activeBattle.startedAt, endsAt: expiresAt,
            durationSeconds: Number(activeBattle.durationSeconds || durationMinutes * 60)
          }, 200, origin, env);
        }

        const activeBattle = await env.DB.prepare(
          "SELECT id, duration_seconds AS durationSeconds FROM room_battles WHERE room_id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; durationSeconds: number }>();
        await env.DB.prepare(
          "UPDATE room_battles SET status = 'finished', ended_at = COALESCE(ended_at, ?) WHERE room_id = ? AND status = 'active'"
        ).bind(now, roomId).run();
        // Both end and reset leave PK layout mode; end preserves the finished battle record.
        const teamMode = false;
        const keepBattleId = action === "end" ? (activeBattle?.id ?? null) : null;
        const response = await hub.fetch(new Request("https://room-seats.internal/battle-state", {
          method: "POST", headers: { "Content-Type": "application/json", "x-room-id": roomId },
          body: JSON.stringify({
            teamMode, active: false, battleId: keepBattleId, endsAt: null,
            durationSeconds: Number(activeBattle?.durationSeconds ?? 300)
          })
        }));
        if (!response.ok) return json({ error: "room_battle_state_sync_failed" }, 503, origin, env);
        return json({
          ok: true, roomId, status: action === "reset" ? "reset" : "finished",
          teamMode, active: false, battleId: keepBattleId, endedAt: now
        }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.battle] failed", diagnostic);
        return json({ error: "room_battle_unavailable" }, 500, origin, env);
      }
    }

    // Room gifts only. Private gifts intentionally remain unavailable until a separately
    // authorized private-conversation system exists.
    const roomGiftSendRoute = url.pathname.match(/^\/api\/v1\/rooms\/([0-9a-f-]{36})\/gifts\/send$/i);
    if (roomGiftSendRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = roomGiftSendRoute[1];
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const recipientUserId = typeof body.recipientUserId === "string" ? body.recipientUserId.trim() : "";
        const giftId = typeof body.giftId === "string" ? body.giftId.trim() : "";
        const quantity = Number(body.quantity ?? 1);
        const idempotencyKey = typeof body.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
        if (!/^[0-9a-f-]{36}$/i.test(recipientUserId) || !/^[a-z0-9-]{1,80}$/i.test(giftId) ||
            !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 100 ||
            !/^[A-Za-z0-9._:-]{16,128}$/.test(idempotencyKey)) {
          return json({ error: "invalid_gift_request" }, 400, origin, env);
        }
        if (recipientUserId === user.id) return json({ error: "cannot_gift_self" }, 400, origin, env);
        const [giftPolicy, roomPolicy] = await Promise.all([
          env.DB!.prepare("SELECT category FROM gift_catalog WHERE id = ? AND is_active = 1 LIMIT 1").bind(giftId).first<{ category: string }>(),
          env.DB!.prepare("SELECT r.owner_user_id, rs.settings_json FROM rooms r LEFT JOIN room_settings rs ON rs.room_id = r.id WHERE r.id = ? AND r.status = 'active' LIMIT 1").bind(roomId).first<{ owner_user_id: string; settings_json: string | null }>()
        ]);
        if (!giftPolicy || !roomPolicy) return json({ error: "gift_or_room_not_found" }, 404, origin, env);
        let roomGiftSettings: Record<string, unknown> = {};
        try { roomGiftSettings = roomPolicy.settings_json ? JSON.parse(roomPolicy.settings_json) as Record<string, unknown> : {}; } catch { roomGiftSettings = {}; }
        if (giftPolicy.category === "lucky" && String(roomGiftSettings.whoLuck ?? "everyone") === "ownerAndAdmins") {
          const roomModerator = await env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1")
            .bind(roomId, user.id).first();
          if (roomPolicy.owner_user_id !== user.id && !roomModerator) {
            return json({ error: "room_lucky_gift_restricted", message: "إرسال حقيبة الحظ متاح للمالك والمشرفين فقط" }, 403, origin, env);
          }
        }
        const now = new Date().toISOString();
        const dayKey = saudiDayKey(now);
        let pkRecipientSeat: number | null = null;
        let pkRecipientTeam: "blue" | "red" | null = null;
        if (env.ROOM_SEATS) {
          try {
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            const seatResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot", {
              headers: { "x-room-id": roomId }
            }));
            const seatPayload = await seatResponse.json().catch(() => null) as { seats?: Array<{ userId?: string; seatNumber?: number }> } | null;
            const recipientSeat = (seatPayload?.seats ?? []).find((seat) => seat.userId === recipientUserId);
            const seatNumber = Number(recipientSeat?.seatNumber);
            if (Number.isInteger(seatNumber) && seatNumber >= 1 && seatNumber <= 12) {
              pkRecipientSeat = seatNumber;
              pkRecipientTeam = [3, 4, 7, 8, 11, 12].includes(seatNumber) ? "blue" : "red";
            }
          } catch (seatError) {
            console.warn("[gifts.pk-seat] lookup skipped", seatError instanceof Error ? seatError.message : "UnknownError");
          }
        }
        const existing = await env.DB!.prepare(
          "SELECT id, status, coin_cost AS coinCost, experience_awarded AS experienceAwarded, recipient_coins AS recipientCoins, battle_id AS battleId " +
          "FROM gift_transactions WHERE sender_user_id = ? AND idempotency_key = ? LIMIT 1"
        ).bind(user.id, idempotencyKey).first<Record<string, unknown>>();
        if (existing) {
          if (existing.status === "succeeded") {
            try { await addCannonEnergy(env.DB!, String(existing.id), roomId, user.id, Number(existing.coinCost ?? 0)); }
            catch (cannonError) { console.warn("[cannon.gift-energy] skipped", cannonError instanceof Error ? cannonError.message : "UnknownError"); }
            if (existing.battleId && env.ROOM_SEATS) {
              try {
                const hub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
                await hub.fetch(new Request("https://room-seats.internal/battle-score/broadcast", {
                  method: "POST", headers: { "x-room-id": roomId }
                }));
              } catch (scoreError) {
                console.warn("[gifts.pk-score] duplicate sync skipped", scoreError instanceof Error ? scoreError.message : "UnknownError");
              }
            }
            return json({ ok: true, duplicate: true, transaction: existing }, 200, origin, env);
          }
          return json({ error: "gift_request_in_progress" }, 409, origin, env);
        }
        await env.DB!.prepare(
          "INSERT OR IGNORE INTO room_exp_daily (user_id, day_key, points) VALUES (?, ?, 0)"
        ).bind(user.id, dayKey).run();
        const transactionId = crypto.randomUUID();
        const statements = [
          env.DB!.prepare(
            "INSERT OR IGNORE INTO gift_transactions " +
            "(id, sender_user_id, recipient_user_id, context_type, room_id, gift_id, quantity, coin_cost, " +
            "app_percent_snapshot, recipient_percent_snapshot, app_coins, recipient_coins, experience_awarded, " +
            "experience_multiplier, battle_id, idempotency_key, sender_balance_before, status, created_at) " +
            "SELECT ?, ?, ?, 'room', r.id, g.id, ?, g.coin_price * ?, s.app_percent, s.recipient_percent, " +
            "CAST((g.coin_price * ? * s.app_percent) / 100 AS INTEGER), " +
            "(g.coin_price * ?) - CAST((g.coin_price * ? * s.app_percent) / 100 AS INTEGER), " +
            "MIN(g.coin_price * ? * CASE WHEN b.id IS NULL THEN 1 ELSE 2 END, MAX(0, 3000000 - COALESCE(d.points, 0)), " +
            "MAX(0, 13000000 - COALESCE((SELECT SUM(points) FROM room_exp_gift_awards WHERE room_id = r.id AND day_key = ?), 0)), " +
            "MAX(0, 14000000 - COALESCE((SELECT SUM(points) FROM room_exp_awards WHERE room_id = r.id AND day_key = ?), 0) - COALESCE((SELECT SUM(points) FROM room_exp_gift_awards WHERE room_id = r.id AND day_key = ?), 0))), " +
            "CASE WHEN b.id IS NULL THEN 1 ELSE 2 END, b.id, ?, sender_wallet.balance, 'processing', ? " +
            "FROM rooms r JOIN gift_catalog g ON g.id = ? AND g.is_active = 1 " +
            "AND (g.starts_at IS NULL OR g.starts_at <= ?) AND (g.ends_at IS NULL OR g.ends_at >= ?) " +
            "LEFT JOIN profiles sender_profile ON sender_profile.user_id = ? " +
            "JOIN gift_revenue_settings s ON s.id = 'current' " +
            "JOIN users recipient ON recipient.id = ? AND recipient.status = 'active' " +
            "JOIN user_wallets sender_wallet ON sender_wallet.user_id = ? AND sender_wallet.balance >= g.coin_price * ? " +
            "LEFT JOIN room_exp_daily d ON d.user_id = ? AND d.day_key = ? " +
            "LEFT JOIN room_battles b ON b.room_id = r.id AND b.status = 'active' AND (b.expires_at IS NULL OR b.expires_at > ?) " +
            "WHERE r.id = ? AND r.status = 'active' AND r.owner_user_id IS NOT NULL AND ? <> recipient.id " +
            "AND EXISTS (SELECT 1 FROM room_chat_visits v WHERE v.room_id = r.id AND v.user_id = recipient.id) " +
            "AND (g.category <> 'country' OR g.country_code = CASE WHEN UPPER(TRIM(COALESCE(sender_profile.country_name, ''))) IN ('SOUTH_ARABIA', 'SOUTH ARABIA', 'الجنوب العربي') THEN 'SOUTH_ARABIA' ELSE UPPER(TRIM(COALESCE(sender_profile.country_code, ''))) END)"
          ).bind(transactionId, user.id, recipientUserId, quantity, quantity, quantity, quantity, quantity, quantity,
            dayKey, dayKey, dayKey, idempotencyKey, now, giftId, now, now, user.id, recipientUserId, user.id, quantity, user.id, dayKey, now, roomId, user.id),
          env.DB!.prepare(
            "UPDATE user_wallets SET balance = balance - (SELECT coin_cost FROM gift_transactions WHERE id = ? AND status = 'processing'), " +
            "updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM gift_transactions WHERE id = ? AND status = 'processing') " +
            "AND balance >= (SELECT coin_cost FROM gift_transactions WHERE id = ? AND status = 'processing')"
          ).bind(transactionId, now, user.id, transactionId, transactionId),
          // Gift-derived coins are ordinary spendable balance, but spending them
          // consumes their future withdrawal eligibility in FIFO order.
          env.DB!.prepare(
            "WITH ordered AS (SELECT l.id, l.remaining_tagged_coins, COALESCE(SUM(l.remaining_tagged_coins) OVER (ORDER BY l.created_at, l.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prior " +
            "FROM gift_earning_lots l WHERE l.user_id = ? AND l.remaining_tagged_coins > 0), " +
            "consumption AS (SELECT id, MIN(remaining_tagged_coins, MAX(0, (SELECT coin_cost FROM gift_transactions WHERE id = ?) - prior)) AS used FROM ordered) " +
            "UPDATE gift_earning_lots SET remaining_tagged_coins = MAX(0, remaining_tagged_coins - (SELECT used FROM consumption WHERE consumption.id = gift_earning_lots.id)), " +
            "remaining_withdrawable_coins = MAX(0, remaining_withdrawable_coins - (SELECT used FROM consumption WHERE consumption.id = gift_earning_lots.id)) " +
            "WHERE id IN (SELECT id FROM consumption WHERE used > 0) AND EXISTS (SELECT 1 FROM gift_wallet_ledger WHERE gift_transaction_id = ? AND entry_type = 'sender_debit')"
          ).bind(user.id, transactionId, transactionId),
          env.DB!.prepare(
            "INSERT INTO gift_wallet_ledger (id, gift_transaction_id, user_id, entry_type, amount, balance_after, created_at) " +
            "SELECT ?, t.id, t.sender_user_id, 'sender_debit', -t.coin_cost, w.balance, ? FROM gift_transactions t " +
            "JOIN user_wallets w ON w.user_id = t.sender_user_id WHERE t.id = ? AND t.status = 'processing' " +
            "AND w.balance = t.sender_balance_before - t.coin_cost " +
            "AND NOT EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit')"
          ).bind(crypto.randomUUID(), now, transactionId),
          env.DB!.prepare(
            "INSERT INTO user_wallets (user_id, balance, updated_at) " +
            "SELECT recipient_user_id, recipient_coins, ? FROM gift_transactions t WHERE t.id = ? AND t.status = 'processing' " +
            "AND EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit') " +
            "ON CONFLICT(user_id) DO UPDATE SET balance = user_wallets.balance + excluded.balance, updated_at = excluded.updated_at"
          ).bind(now, transactionId),
          env.DB!.prepare(
            "INSERT INTO gift_earning_lots (id, gift_transaction_id, user_id, credited_coins, remaining_tagged_coins, remaining_withdrawable_coins, created_at) " +
            "SELECT ?, t.id, t.recipient_user_id, t.recipient_coins, t.recipient_coins, t.recipient_coins, ? FROM gift_transactions t " +
            "WHERE t.id = ? AND t.status = 'processing' AND EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit')"
          ).bind(crypto.randomUUID(), now, transactionId),
          env.DB!.prepare(
            "INSERT INTO gift_wallet_ledger (id, gift_transaction_id, user_id, entry_type, amount, balance_after, created_at) " +
            "SELECT ?, t.id, t.recipient_user_id, 'recipient_credit', t.recipient_coins, w.balance, ? FROM gift_transactions t " +
            "JOIN user_wallets w ON w.user_id = t.recipient_user_id WHERE t.id = ? AND t.status = 'processing' " +
            "AND EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit')"
          ).bind(crypto.randomUUID(), now, transactionId),
          env.DB!.prepare(
            "INSERT INTO room_exp_gift_awards (id, gift_transaction_id, room_id, user_id, day_key, points, created_at) " +
            "SELECT ?, t.id, t.room_id, t.sender_user_id, ?, t.experience_awarded, ? FROM gift_transactions t " +
            "WHERE t.id = ? AND t.status = 'processing' AND t.experience_awarded > 0 " +
            "AND EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit')"
          ).bind(crypto.randomUUID(), dayKey, now, transactionId),
          ...(pkRecipientTeam && pkRecipientSeat !== null ? [
            env.DB!.prepare(
              "INSERT OR IGNORE INTO room_battle_gift_scores (id, gift_transaction_id, battle_id, room_id, user_id, team, seat_number, points, created_at) " +
              "SELECT ?, t.id, t.battle_id, t.room_id, t.recipient_user_id, ?, ?, t.coin_cost, ? FROM gift_transactions t " +
              "JOIN room_battles b ON b.id = t.battle_id AND b.status = 'active' AND (b.expires_at IS NULL OR b.expires_at > ?) " +
              "WHERE t.id = ? AND t.status = 'processing' AND t.battle_id IS NOT NULL " +
              "AND EXISTS (SELECT 1 FROM gift_wallet_ledger l WHERE l.gift_transaction_id = t.id AND l.entry_type = 'sender_debit')"
            ).bind(crypto.randomUUID(), pkRecipientTeam, pkRecipientSeat, now, now, transactionId)
          ] : []),
          env.DB!.prepare(
            "UPDATE room_exp_daily SET points = points + COALESCE((SELECT points FROM room_exp_gift_awards WHERE gift_transaction_id = ?), 0) " +
            "WHERE user_id = ? AND day_key = ? AND EXISTS (SELECT 1 FROM room_exp_gift_awards WHERE gift_transaction_id = ?)"
          ).bind(transactionId, user.id, dayKey, transactionId),
          env.DB!.prepare(
            "INSERT INTO room_experience (room_id, total_exp, updated_at) " +
            "SELECT room_id, points, ? FROM room_exp_gift_awards WHERE gift_transaction_id = ? " +
            "ON CONFLICT(room_id) DO UPDATE SET total_exp = room_experience.total_exp + excluded.total_exp, updated_at = excluded.updated_at"
          ).bind(now, transactionId),
          env.DB!.prepare(
            "UPDATE gift_transactions SET status = 'succeeded' WHERE id = ? AND status = 'processing' " +
            "AND EXISTS (SELECT 1 FROM gift_wallet_ledger WHERE gift_transaction_id = ? AND entry_type = 'sender_debit')"
          ).bind(transactionId, transactionId),
          ...addRoomContribution(env.DB!, transactionId),
          env.DB!.prepare("DELETE FROM gift_transactions WHERE id = ? AND status = 'processing'").bind(transactionId)
        ];
        await env.DB!.batch(statements);
        const transaction = await env.DB!.prepare(
          "SELECT id, sender_user_id AS senderUserId, recipient_user_id AS recipientUserId, room_id AS roomId, gift_id AS giftId, quantity, coin_cost AS coinCost, app_coins AS appCoins, recipient_coins AS recipientCoins, experience_awarded AS experienceAwarded, experience_multiplier AS experienceMultiplier, battle_id AS battleId, status, created_at AS createdAt " +
          "FROM gift_transactions WHERE sender_user_id = ? AND idempotency_key = ? LIMIT 1"
        ).bind(user.id, idempotencyKey).first<Record<string, unknown>>();
        if (!transaction) {
          const wallet = await env.DB!.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(user.id).first<{ balance: number }>();
          const gift = await env.DB!.prepare(
            "SELECT g.coin_price FROM gift_catalog g LEFT JOIN profiles p ON p.user_id = ? " +
            "WHERE g.id = ? AND g.is_active = 1 AND (g.starts_at IS NULL OR g.starts_at <= ?) AND (g.ends_at IS NULL OR g.ends_at >= ?) " +
            "AND (g.category <> 'country' OR g.country_code = CASE WHEN UPPER(TRIM(COALESCE(p.country_name, ''))) IN ('SOUTH_ARABIA', 'SOUTH ARABIA', 'الجنوب العربي') THEN 'SOUTH_ARABIA' ELSE UPPER(TRIM(COALESCE(p.country_code, ''))) END)"
          ).bind(user.id, giftId, now, now).first<{ coin_price: number }>();
          if (!gift) return json({ error: "gift_not_available" }, 404, origin, env);
          const room = await env.DB!.prepare("SELECT id FROM rooms WHERE id = ? AND status = 'active'").bind(roomId).first<{ id: string }>();
          if (!room) return json({ error: "room_not_found" }, 404, origin, env);
          const wasRoomParticipant = await env.DB!.prepare("SELECT id FROM room_chat_visits WHERE room_id = ? AND user_id = ? LIMIT 1")
            .bind(roomId, recipientUserId).first<{ id: string }>();
          if (!wasRoomParticipant) return json({ error: "recipient_not_room_member" }, 409, origin, env);
          const needed = gift.coin_price * quantity;
          if ((wallet?.balance ?? 0) < needed) return json({ error: "insufficient_balance", balance: wallet?.balance ?? 0, required: needed }, 409, origin, env);
          return json({ error: "gift_not_processed" }, 409, origin, env);
        }
        if (transaction.status !== "succeeded") return json({ error: "gift_not_processed" }, 409, origin, env);
        // Cannon energy is derived only from the committed, server-priced gift transaction.
        // The transaction id is unique in cannon_energy_transactions, so retries cannot double-credit.
        try { await addCannonEnergy(env.DB!, String(transaction.id), roomId, user.id, Number(transaction.coinCost ?? 0)); }
        catch (cannonError) { console.warn("[cannon.gift-energy] skipped", cannonError instanceof Error ? cannonError.message : "UnknownError"); }
        // Notify every connected room member after the wallet transaction is committed.
        // Animation delivery is best-effort and must never undo a successful gift.
        let gift: Record<string, unknown> | null = null;
        try {
          gift = await env.DB!.prepare(
            "SELECT g.name, g.icon_emoji AS iconEmoji, g.media_url AS mediaUrl, g.media_type AS mediaType, g.sound_url AS soundUrl, g.duration_seconds AS durationSeconds, " +
            "COALESCE(sp.display_name, 'مستخدم') AS senderName, COALESCE(rp.display_name, 'مستخدم') AS recipientName, " +
            "COALESCE(sp.avatar_key, '') AS senderAvatar, COALESCE(rp.avatar_key, '') AS recipientAvatar " +
            "FROM gift_catalog g LEFT JOIN profiles sp ON sp.user_id = ? " +
            "LEFT JOIN profiles rp ON rp.user_id = ? WHERE g.id = ? LIMIT 1"
          ).bind(user.id, recipientUserId, giftId).first<Record<string, unknown>>();
          if (env.ROOM_SEATS && gift) {
            const hub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            const broadcastResponse = await hub.fetch(new Request("https://room-seats.internal/gift", {
              method: "POST",
              headers: { "Content-Type": "application/json", "x-room-id": roomId },
              body: JSON.stringify({
                transactionId: transaction.id,
                senderUserId: user.id,
                recipientUserId,
                senderName: gift.senderName,
                recipientName: gift.recipientName,
                name: gift.name,
                iconEmoji: gift.iconEmoji,
                mediaUrl: gift.mediaUrl,
                mediaType: gift.mediaType,
                soundUrl: gift.soundUrl,
                durationSeconds: Number(gift.durationSeconds ?? 5),
                mediaDurationMs: Number(gift.durationSeconds ?? 5) * 1000,
                quantity,
                coinCost: Number(transaction.coinCost ?? 0)
              })
            }));
            const broadcastResult = await broadcastResponse.json().catch(() => null) as Record<string, unknown> | null;
            const delivered = Number(broadcastResult?.delivered ?? 0);
            if (!broadcastResponse.ok || delivered === 0) {
              console.warn("[gifts.room.broadcast] no_live_recipients", {
                status: broadcastResponse.status,
                delivered,
                roomId
              });
            }
          }
        } catch (broadcastError) {
          console.warn("[gifts.room.broadcast] skipped", broadcastError instanceof Error ? broadcastError.message : "UnknownError");
        }
        if (transaction.battleId && env.ROOM_SEATS) {
          try {
            const hub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            await hub.fetch(new Request("https://room-seats.internal/battle-score/broadcast", {
              method: "POST", headers: { "x-room-id": roomId }
            }));
          } catch (scoreError) {
            console.warn("[gifts.pk-score] realtime sync skipped", scoreError instanceof Error ? scoreError.message : "UnknownError");
          }
        }
        // A qualifying gift also produces one application-wide banner, including for users outside rooms.
        try {
          const bannerSettings = await env.DB!.prepare(
            "SELECT enabled, minimum_coins AS minimumCoins FROM gift_banner_settings WHERE id = 'current'"
          ).first<{ enabled: number; minimumCoins: number }>();
          const giftCoins = Number(transaction.coinCost ?? 0);
          if (env.GLOBAL_GIFTS && bannerSettings?.enabled === 1 &&
              Number.isSafeInteger(giftCoins) && giftCoins >= Number(bannerSettings.minimumCoins) &&
              Number(bannerSettings.minimumCoins) > 0 && gift) {
            const bannerPayload = {
              type: "global_gift_banner",
              transactionId: transaction.id,
              senderName: gift.senderName,
              receiverName: gift.recipientName,
              giftImage: gift.mediaUrl || gift.iconEmoji,
              senderAvatar: gift.senderAvatar,
              receiverAvatar: gift.recipientAvatar,
              message: `${gift.senderName} أرسل هدية إلى ${gift.recipientName}`,
              level: 0,
              style: giftCoins >= Number(bannerSettings.minimumCoins) * 10 ? "blue" : "green",
              coinCost: giftCoins,
              quantity: Number(transaction.quantity ?? quantity),
              createdAt: new Date().toISOString()
            };
            // Fan out across independent shards instead of concentrating every
            // connected app user on one globally serialized Durable Object.
            await Promise.all(Array.from({ length: GLOBAL_GIFT_SHARD_COUNT }, (_, shard) => {
              const hub = env.GLOBAL_GIFTS!.get(
                env.GLOBAL_GIFTS!.idFromName(`application-global-${shard}`)
              );
              return hub.broadcast(bannerPayload);
            }));
          }
        } catch (globalBroadcastError) {
          console.warn("[gifts.global.broadcast] skipped", globalBroadcastError instanceof Error ? globalBroadcastError.message : "UnknownError");
        }
        return json({ ok: true, duplicate: false, transaction }, 201, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[gifts.room.send] failed", diagnostic);
        return json({ error: "gift_send_failed" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/wallet" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        await env.DB!.prepare("INSERT OR IGNORE INTO user_wallets (user_id, balance, updated_at) VALUES (?, 0, ?)").bind(user.id, new Date().toISOString()).run();
        const [wallet, transactions, giftEarnings] = await Promise.all([
          env.DB!.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(user.id).first<{ balance: number }>(),
          env.DB!.prepare(
            "SELECT id, amount, balance_after AS balanceAfter, transaction_type AS type, reference_id AS referenceId, description, created_at AS createdAt FROM wallet_transactions WHERE user_id = ? ORDER BY createdAt DESC LIMIT 30"
          ).bind(user.id).all(),
          env.DB!.prepare("SELECT COALESCE(SUM(credited_coins), 0) AS totalGiftCoins, COALESCE(SUM(remaining_tagged_coins), 0) AS remainingTaggedCoins, COALESCE(SUM(remaining_withdrawable_coins), 0) AS futureWithdrawableCoins FROM gift_earning_lots WHERE user_id = ?").bind(user.id).first<Record<string, number>>()
        ]);
        return json({
          ok: true,
          userCode: user.happy_id ?? "",
          balance: wallet?.balance ?? 0,
          transactions: transactions.results ?? [],
          giftEarnings: giftEarnings ?? { totalGiftCoins: 0, remainingTaggedCoins: 0, futureWithdrawableCoins: 0 },
          withdrawals: { enabled: false, ready: false }
        }, 200, origin, env);
      } catch (error) {
        console.error("[wallet.get] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "wallet_unavailable" }, 500, origin, env);
      }
    }

    // Server-authoritative room upgrade; the authenticated purchaser pays, even for another user's room.
    const roomUpgradeRoute = url.pathname.match(new RegExp("^/api/v1/rooms/([0-9a-f-]{36})/upgrade$", "i"));
    if (roomUpgradeRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const targetLevel = Number(body.level);
        if (!Number.isInteger(targetLevel) || targetLevel < 2 || targetLevel > 5) return json({ error: "invalid_room_level", message: "المستوى المطلوب غير صالح" }, 400, origin, env);
        const prices: Record<number, number> = { 2: 30000, 3: 60000, 4: 300000 };
        const price = prices[targetLevel];
        if (!price) return json({ error: "level_price_unavailable", message: "سعر مستوى القصر لم يُحدد بعد" }, 409, origin, env);
        const roomId = roomUpgradeRoute[1];
        const room = await env.DB!.prepare("SELECT r.id, r.name, COALESCE(rl.level, 1) AS level FROM rooms r LEFT JOIN room_levels rl ON rl.room_id = r.id WHERE r.id = ? AND r.status <> 'deleted' LIMIT 1").bind(roomId).first<{ id: string; name: string; level: number }>();
        if (!room) return json({ error: "room_not_found", message: "الغرفة غير موجودة" }, 404, origin, env);
        if (targetLevel <= room.level) return json({ error: "room_level_not_higher", message: "الغرفة وصلت إلى هذا المستوى أو أعلى" }, 409, origin, env);
        const now = new Date().toISOString();
        const transactionId = crypto.randomUUID();
        await env.DB!.prepare("INSERT OR IGNORE INTO user_wallets (user_id, balance, updated_at) VALUES (?, 0, ?)").bind(user.id, now).run();
        const results = await env.DB!.batch([
          env.DB!.prepare("INSERT INTO wallet_transactions (id, user_id, amount, balance_after, transaction_type, reference_id, description, created_at) SELECT ?, w.user_id, ?, w.balance - ?, 'room_upgrade', ?, ?, ? FROM user_wallets w INNER JOIN rooms r ON r.id = ? LEFT JOIN room_levels rl ON rl.room_id = r.id WHERE w.user_id = ? AND w.balance >= ? AND COALESCE(rl.level, 1) < ? AND r.status <> 'deleted'").bind(transactionId, -price, price, roomId, "ترقية غرفة " + room.name, now, roomId, user.id, price, targetLevel),
          env.DB!.prepare("UPDATE user_wallets SET balance = balance - ?, updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ? AND transaction_type = 'room_upgrade')").bind(price, now, user.id, transactionId),
          env.DB!.prepare(
            "WITH ordered AS (SELECT id, remaining_tagged_coins, COALESCE(SUM(remaining_tagged_coins) OVER (ORDER BY created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prior FROM gift_earning_lots WHERE user_id = ? AND remaining_tagged_coins > 0), " +
            "consumption AS (SELECT id, MIN(remaining_tagged_coins, MAX(0, ? - prior)) AS used FROM ordered) " +
            "UPDATE gift_earning_lots SET remaining_tagged_coins = MAX(0, remaining_tagged_coins - (SELECT used FROM consumption WHERE consumption.id = gift_earning_lots.id)), " +
            "remaining_withdrawable_coins = MAX(0, remaining_withdrawable_coins - (SELECT used FROM consumption WHERE consumption.id = gift_earning_lots.id)) " +
            "WHERE id IN (SELECT id FROM consumption WHERE used > 0) AND EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ? AND transaction_type = 'room_upgrade')"
          ).bind(user.id, price, transactionId),
          env.DB!.prepare("INSERT INTO room_levels (room_id, level, updated_at) SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ? AND transaction_type = 'room_upgrade') ON CONFLICT(room_id) DO UPDATE SET level = excluded.level, updated_at = excluded.updated_at WHERE room_levels.level < excluded.level").bind(roomId, targetLevel, now, transactionId)
        ]);
        // A wallet may contain no gift-derived lots at all. FIFO consumption is
        // intentionally allowed to update zero rows; only the purchase debit and
        // wallet balance mutation determine whether the upgrade succeeded.
        if ((results[0]?.meta?.changes ?? 0) !== 1 || (results[1]?.meta?.changes ?? 0) !== 1) {
          const [latestRoom, wallet] = await Promise.all([
            env.DB!.prepare("SELECT COALESCE(rl.level, 1) AS level FROM rooms r LEFT JOIN room_levels rl ON rl.room_id = r.id WHERE r.id = ? AND r.status <> 'deleted' LIMIT 1").bind(roomId).first<{ level: number }>(),
            env.DB!.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(user.id).first<{ balance: number }>()
          ]);
          if (!latestRoom) return json({ error: "room_not_found", message: "الغرفة غير موجودة" }, 404, origin, env);
          if (latestRoom.level >= targetLevel) return json({ error: "room_level_not_higher", message: "الغرفة وصلت إلى هذا المستوى أو أعلى", level: latestRoom.level }, 409, origin, env);
          return json({ error: "insufficient_funds", message: "رصيد العملات غير كافٍ", balance: wallet?.balance ?? 0, required: price }, 402, origin, env);
        }
        const wallet = await env.DB!.prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1").bind(user.id).first<{ balance: number }>();
        return json({ ok: true, roomId, level: targetLevel, price, balance: wallet?.balance ?? 0 }, 200, origin, env);
      } catch (error) {
        console.error("[rooms.upgrade] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_upgrade_failed", message: "تعذر تنفيذ ترقية الغرفة" }, 500, origin, env);
      }
    }

    // Owner-only room settings API. Settings and moderator permission rules are stored per room.
    const roomSettingsRoute = url.pathname.match(/^\/api\/v1\/rooms\/([0-9a-f-]{36})\/settings$/i);
    if (roomSettingsRoute && (request.method === "GET" || request.method === "PATCH")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedUser(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = roomSettingsRoute[1];
        const room = await env.DB.prepare(
          "SELECT id, owner_user_id, name, image_url, status FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string; name: string; image_url: string | null; status: string }>();
        if (!room) return json({ error: "room_not_found", message: "الغرفة غير موجودة" }, 404, origin, env);
        if (room.owner_user_id !== actor.id) return json({ error: "room_owner_required", message: "إعدادات الغرفة متاحة للمالك فقط" }, 403, origin, env);

        const saved = await env.DB.prepare(
          "SELECT settings_json, permissions_json FROM room_settings WHERE room_id = ? LIMIT 1"
        ).bind(roomId).first<{ settings_json: string; permissions_json: string }>();
        let settings: Record<string, unknown> = {};
        let permissions: Record<string, unknown> = {};
        try { settings = saved?.settings_json ? JSON.parse(saved.settings_json) as Record<string, unknown> : {}; } catch { settings = {}; }
        try { permissions = saved?.permissions_json ? JSON.parse(saved.permissions_json) as Record<string, unknown> : {}; } catch { permissions = {}; }

        if (request.method === "GET") {
          const [announcement, moderators] = await Promise.all([
            env.DB.prepare("SELECT announcement FROM room_announcements WHERE room_id = ? LIMIT 1").bind(roomId).first<{ announcement: string }>(),
            env.DB.prepare(
              "SELECT m.user_id, COALESCE(p.display_name, '') AS display_name, COALESCE(p.happy_id, '') AS public_id FROM room_moderators m LEFT JOIN profiles p ON p.user_id = m.user_id WHERE m.room_id = ? ORDER BY m.created_at ASC"
            ).bind(roomId).all<{ user_id: string; display_name: string; public_id: string }>()
          ]);
          return json({
            ok: true,
            settings: {
              ...settings,
              name: room.name,
              coverUrl: room.image_url ?? "",
              announcement: announcement?.announcement ?? "",
              seats: Number(settings.seats ?? 8),
              micLayoutId: String(settings.micLayoutId ?? ("m" + Number(settings.seats ?? 8))),
              micRequestMode: String(settings.micRequestMode ?? "إغلاق"),
              autoGames: settings.autoGames !== false,
              whoEnter: String(settings.whoEnter ?? "everyone"),
              whoMic: String(settings.whoMic ?? "membersOnly"),
              whoChat: String(settings.whoChat ?? "everyone"),
              whoLuck: String(settings.whoLuck ?? "everyone")
            },
            permissions,
            admins: moderators.results ?? []
          }, 200, origin, env);
        }

        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }

        if (typeof body.key === "string") {
          const key = body.key;
          const value = body.value;
          if (key === "name") {
            const name = String(value ?? "").trim();
            if (!name || name.length > 30) return json({ error: "invalid_room_name", message: "اسم الغرفة يجب أن يكون من 1 إلى 30 حرفًا" }, 400, origin, env);
            await env.DB.prepare("UPDATE rooms SET name = ?, updated_at = ? WHERE id = ? AND owner_user_id = ?")
              .bind(name, new Date().toISOString(), roomId, actor.id).run();
          } else if (key === "announcement") {
            const announcement = String(value ?? "").trim();
            if (announcement.length > 200) return json({ error: "invalid_announcement", message: "الإعلان لا يتجاوز 200 حرف" }, 400, origin, env);
            const now = new Date().toISOString();
            await env.DB.prepare(
              "INSERT INTO room_announcements (room_id, announcement, updated_at) VALUES (?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET announcement = excluded.announcement, updated_at = excluded.updated_at"
            ).bind(roomId, announcement, now).run();
          } else if (key === "micLayoutId") {
            const layoutCounts: Record<string, number> = { m2: 2, m8: 8, m10: 10, m12: 12, m14: 14, m15: 15, m16: 16, m20: 20, m24: 24, m10b: 10, m10c: 10 };
            const layoutId = String(value ?? "");
            if (!Object.prototype.hasOwnProperty.call(layoutCounts, layoutId)) return json({ error: "invalid_mic_layout" }, 400, origin, env);
            settings.micLayoutId = layoutId;
            settings.seats = layoutCounts[layoutId];
          } else {
            const allowedKeys = new Set(["seats", "micRequestMode", "autoGames", "whoEnter", "whoMic", "whoChat", "whoLuck", "coverUrl"]);
            if (!allowedKeys.has(key)) return json({ error: "unsupported_room_setting" }, 400, origin, env);
            if (key === "seats") {
              const count = Number(value);
              if (![2, 8, 10, 12, 14, 15, 16, 20, 24].includes(count)) return json({ error: "invalid_seat_count", message: "عدد المايكات غير مدعوم" }, 400, origin, env);
              settings.micLayoutId = "m" + count;
            }
            if (key === "micRequestMode" && !["إغلاق", "تفعيل"].includes(String(value))) return json({ error: "invalid_mic_request_mode" }, 400, origin, env);
            if (key === "autoGames" && typeof value !== "boolean") return json({ error: "invalid_boolean_setting" }, 400, origin, env);
            if (["whoEnter", "whoMic", "whoChat", "whoLuck"].includes(key) && !["everyone", "membersOnly", "ownerAndAdmins"].includes(String(value))) return json({ error: "invalid_audience" }, 400, origin, env);
            if (key === "coverUrl") {
              const coverUrl = value == null ? "" : String(value).trim();
              if (coverUrl && !isSafeExternalHttpsUrl(coverUrl)) return json({ error: "invalid_cover_url" }, 400, origin, env);
              await env.DB.prepare("UPDATE rooms SET image_url = ?, updated_at = ? WHERE id = ? AND owner_user_id = ?")
                .bind(coverUrl || null, new Date().toISOString(), roomId, actor.id).run();
              settings.coverUrl = coverUrl;
            } else {
              settings[key] = value;
            }
          }
          const now = new Date().toISOString();
          await env.DB.prepare(
            "INSERT INTO room_settings (room_id, settings_json, permissions_json, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET settings_json = excluded.settings_json, updated_at = excluded.updated_at"
          ).bind(roomId, JSON.stringify(settings), JSON.stringify(permissions), now).run();
          if ((key === "micLayoutId" || key === "seats") && env.ROOM_SEATS) {
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            await seatHub.fetch(new Request("https://room-seats.internal/set-seat-count", {
              method: "POST",
              headers: { "x-seat-count": String(settings.seats ?? 8) }
            }));
          }
          if (key === "whoMic" && env.ROOM_SEATS) {
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            await seatHub.fetch(new Request("https://room-seats.internal/set-mic-policy", {
              method: "POST",
              headers: { "x-who-mic": String(value) }
            }));
          }
          await env.DB.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, action, details_json, created_at) VALUES (?, ?, ?, 'setting.update', ?, ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, JSON.stringify({ key, value }), now).run();
          return json({ ok: true, key, value }, 200, origin, env);
        }

        if (typeof body.permissionId === "string") {
          const permissionId = body.permissionId;
          const allowedPermissions = new Set(["bg", "chat_delete", "room_lock", "seat_count", "mic_lock", "others_mic", "invite_seat", "mic_requests", "features", "events", "fireworks", "mute", "kick", "blacklist", "members", "super"]);
          const level = String(body.level ?? "");
          const adminIds = Array.isArray(body.adminIds) ? body.adminIds.map((id) => String(id)) : [];
          if (!allowedPermissions.has(permissionId) || !["ownerOnly", "allAdmins", "selectedAdmins"].includes(level)) return json({ error: "invalid_permission" }, 400, origin, env);
          if (level === "selectedAdmins" && adminIds.length === 0) return json({ error: "selected_admins_required", message: "حدد مشرفًا واحدًا على الأقل" }, 400, origin, env);
          if (adminIds.length > 100 || new Set(adminIds).size !== adminIds.length) return json({ error: "invalid_admin_list" }, 400, origin, env);
          if (adminIds.length) {
            const currentAdmins = await env.DB.prepare("SELECT user_id FROM room_moderators WHERE room_id = ?").bind(roomId).all<{ user_id: string }>();
            const validIds = new Set((currentAdmins.results ?? []).map((row) => row.user_id));
            if (adminIds.some((id) => !validIds.has(id))) return json({ error: "invalid_room_moderator", message: "تحتوي القائمة على مشرف غير معيّن في هذه الغرفة" }, 400, origin, env);
          }
          permissions[permissionId] = { level, adminIds: level === "selectedAdmins" ? adminIds : [] };
          const now = new Date().toISOString();
          await env.DB.prepare(
            "INSERT INTO room_settings (room_id, settings_json, permissions_json, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET permissions_json = excluded.permissions_json, updated_at = excluded.updated_at"
          ).bind(roomId, JSON.stringify(settings), JSON.stringify(permissions), now).run();
          await env.DB.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, action, details_json, created_at) VALUES (?, ?, ?, 'permission.update', ?, ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, JSON.stringify({ permissionId, level, adminIds }), now).run();
          return json({ ok: true, permissionId, level, adminIds }, 200, origin, env);
        }
        return json({ error: "invalid_room_settings_payload" }, 400, origin, env);
      } catch (error) {
        console.error("[rooms.settings] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_settings_failed", message: "تعذر حفظ إعدادات الغرفة" }, 500, origin, env);
      }
    }

    // Room moderation: room owners and explicitly assigned room moderators only.
    const moderationRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/moderation$/);
    if (moderationRoute && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB || !env.ROOM_SEATS) return json({ error: "room_moderation_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedUser(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(moderationRoute[1]);
        const room = await env.DB!.prepare(
          "SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        if (request.method === "GET") {
          if (room.owner_user_id !== actor.id) return json({ error: "room_owner_required", message: "هذه البيانات متاحة لمالك الغرفة فقط" }, 403, origin, env);
          const now = new Date().toISOString();
          const [bans, kicks, muted, logs] = await Promise.all([
            env.DB!.prepare("SELECT b.user_id, COALESCE(p.display_name, 'مستخدم') AS display_name, COALESCE(p.happy_id, '') AS public_id, b.created_at FROM room_bans b LEFT JOIN profiles p ON p.user_id = b.user_id WHERE b.room_id = ? ORDER BY b.created_at DESC").bind(roomId).all(),
            env.DB!.prepare(
              "SELECT user_id, display_name, public_id, kicked_until, created_at FROM (" +
              "SELECT k.user_id, COALESCE(p.display_name, 'مستخدم') AS display_name, COALESCE(p.happy_id, '') AS public_id, k.kicked_until, k.created_at FROM room_kicks k LEFT JOIN profiles p ON p.user_id = k.user_id WHERE k.room_id = ? AND k.kicked_until > ? " +
              "UNION SELECT c.user_id, COALESCE(p.display_name, 'مستخدم'), COALESCE(p.happy_id, ''), c.kicked_until, c.updated_at FROM room_user_controls c LEFT JOIN profiles p ON p.user_id = c.user_id WHERE c.room_id = ? AND c.kicked_until > ?" +
              ") ORDER BY kicked_until DESC"
            ).bind(roomId, now, roomId, now).all(),
            env.DB!.prepare("SELECT c.user_id, COALESCE(p.display_name, 'مستخدم') AS display_name, COALESCE(p.happy_id, '') AS public_id, c.updated_at FROM room_user_controls c LEFT JOIN profiles p ON p.user_id = c.user_id WHERE c.room_id = ? AND c.is_muted = 1 ORDER BY c.updated_at DESC").bind(roomId).all(),
            env.DB!.prepare("SELECT l.id, l.action, l.details_json, l.created_at, COALESCE(a.display_name, 'مالك الغرفة') AS actor_name, COALESCE(t.display_name, 'مستخدم') AS target_name, COALESCE(t.happy_id, '') AS target_public_id FROM room_settings_logs l LEFT JOIN profiles a ON a.user_id = l.actor_user_id LEFT JOIN profiles t ON t.user_id = l.target_user_id WHERE l.room_id = ? ORDER BY l.created_at DESC LIMIT 200").bind(roomId).all()
          ]);
          return json({ ok: true, bans: bans.results ?? [], kicks: kicks.results ?? [], muted: muted.results ?? [], logs: logs.results ?? [] }, 200, origin, env);
        }
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const action = String(body.action ?? "");
        const targetUserId = String(body.targetUserId ?? actor.id);
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 240) : "";
        const isOwner = room.owner_user_id === actor.id;
        const moderator = await env.DB!.prepare(
          "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, actor.id).first<{ user_id: string }>();
        const canModerate = isOwner || !!moderator;
        if (action === "self_mic_toggle") {
          const current = await env.DB!.prepare(
            "SELECT is_muted, muted_by FROM room_user_controls WHERE room_id = ? AND user_id = ?"
          ).bind(roomId, actor.id).first<{ is_muted: number; muted_by: string | null }>();
          if (current?.is_muted === 1 && current.muted_by && current.muted_by !== actor.id) {
            return json({ error: "moderator_muted", message: "تم كتم مايكك بواسطة إدارة الغرفة" }, 403, origin, env);
          }
          if (current?.is_muted !== 1) {
            const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
            const seatSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
            const seatSnapshot = await seatSnapshotResponse.json() as {
              seats?: Array<{ userId: string; seatNumber: number }>;
              seatControls?: Record<string, { isMuted?: boolean }>;
            };
            const mySeat = (seatSnapshot.seats ?? []).find((seat) => seat.userId === actor.id);
            if (mySeat && seatSnapshot.seatControls?.[String(mySeat.seatNumber)]?.isMuted === true) {
              return json({ error: "moderator_muted", message: "هذا المايك مكتوم بواسطة إدارة الغرفة" }, 403, origin, env);
            }
          }
          const nextMuted = current?.is_muted === 1 ? 0 : 1;
          await env.DB!.prepare(
            "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, NULL, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = NULL, updated_at = excluded.updated_at"
          ).bind(roomId, actor.id, nextMuted, new Date().toISOString()).run();
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          await seatHub.fetch(new Request("https://room-seats.internal/set-muted", {
            method: "POST",
            headers: { "x-target-user-id": actor.id, "x-is-muted": nextMuted === 1 ? "true" : "false" }
          }));
          return json({ ok: true, isMuted: nextMuted === 1 }, 200, origin, env);
        }
        if (!canModerate) return json({ error: "room_moderator_required", message: "هذه الصلاحية لمالك الغرفة ومشرفيها فقط" }, 403, origin, env);
        if (!isOwner) {
          const permissionId = action === "toggle_mute" || action === "unmute" || action === "toggle_seat_mute" || action === "toggle_seat_lock" ? "mute"
            : action === "kick" || action === "unkick" ? "kick"
            : action === "ban" || action === "unban" ? "blacklist"
            : action === "lower" ? "super"
            : null;
          if (permissionId) {
            const savedPermissions = await env.DB!.prepare(
              "SELECT permissions_json FROM room_settings WHERE room_id = ? LIMIT 1"
            ).bind(roomId).first<{ permissions_json: string }>();
            let permissionRules: Record<string, { level?: string; adminIds?: string[] }> = {};
            try {
              permissionRules = savedPermissions?.permissions_json
                ? JSON.parse(savedPermissions.permissions_json) as Record<string, { level?: string; adminIds?: string[] }>
                : {};
            } catch { permissionRules = {}; }
            const rule = permissionRules[permissionId];
            const level = rule?.level ?? "allAdmins";
            const selected = Array.isArray(rule?.adminIds) ? rule.adminIds : [];
            const permitted = level === "allAdmins" ||
              (level === "selectedAdmins" && selected.includes(actor.id));
            if (!permitted) {
              return json({ error: "room_permission_denied", message: "لا تملك صلاحية تنفيذ هذا الإجراء في الغرفة" }, 403, origin, env);
            }
          }
        }
        if (action === "toggle_seat_mute" || action === "toggle_seat_lock") {
          const seatNumber = Number(body.seatNumber);
          const seatLimit = await env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1")
            .bind(roomId).first<{ settings_json: string }>();
          let seatSettings: Record<string, unknown> = {};
          try { seatSettings = seatLimit?.settings_json ? JSON.parse(seatLimit.settings_json) as Record<string, unknown> : {}; } catch { seatSettings = {}; }
          const configuredSeats = Number(seatSettings.seats ?? 8);
          if (!Number.isInteger(seatNumber) || seatNumber < 1 || seatNumber > configuredSeats || seatNumber > 24) {
            return json({ error: "invalid_seat_number", message: "رقم المايك غير صحيح" }, 400, origin, env);
          }
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          const snapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
          const snapshot = await snapshotResponse.json() as {
            seats?: Array<{ seatNumber: number; userId: string; isRoomOwner?: boolean; isRoomModerator?: boolean; isMuted?: boolean }>;
            seatControls?: Record<string, { isLocked?: boolean; isMuted?: boolean }>;
          };
          const member = (snapshot.seats ?? []).find((seat) => seat.seatNumber === seatNumber);
          if (member && (member.isRoomOwner || member.isRoomModerator)) {
            return json({ error: "cannot_moderate_room_staff", message: "لا يمكن التحكم بمايك المالك أو مشرف الغرفة" }, 403, origin, env);
          }
          const previous = snapshot.seatControls?.[String(seatNumber)] ?? { isLocked: false, isMuted: false };
          const effectiveMuted = previous.isMuted === true || member?.isMuted === true;
          const nextLocked = action === "toggle_seat_lock" ? previous.isLocked !== true : previous.isLocked === true;
          const nextMuted = action === "toggle_seat_mute" ? !effectiveMuted : previous.isMuted === true;
          const now = new Date().toISOString();
          if (member && action === "toggle_seat_mute") {
            await env.DB!.prepare(
              "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = CASE WHEN excluded.is_muted = 1 THEN excluded.muted_by ELSE NULL END, updated_at = excluded.updated_at"
            ).bind(roomId, member.userId, nextMuted ? 1 : 0, nextMuted ? actor.id : null, now).run();
            await seatHub.fetch(new Request("https://room-seats.internal/set-muted", {
              method: "POST",
              headers: { "x-target-user-id": member.userId, "x-is-muted": nextMuted ? "true" : "false" }
            }));
          }
          const controlResponse = await seatHub.fetch(new Request("https://room-seats.internal/set-seat-control", {
            method: "POST",
            headers: {
              "x-seat-number": String(seatNumber),
              "x-is-locked": nextLocked ? "true" : "false",
              "x-is-muted": nextMuted ? "true" : "false"
            }
          }));
          if (!controlResponse.ok) return json({ error: "seat_control_failed", message: "تعذر تحديث المايك" }, 503, origin, env);
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, member?.userId ?? actor.id, action, JSON.stringify({ seatNumber, isLocked: nextLocked, isMuted: nextMuted }), now).run();
          return json({ ok: true, seatNumber, isLocked: nextLocked, isMuted: nextMuted }, 200, origin, env);
        }
        if (action === "assign_moderator" || action === "remove_moderator") {
          if (!isOwner) return json({ error: "room_owner_required" }, 403, origin, env);
          if (!targetUserId || targetUserId === actor.id) return json({ error: "invalid_moderator" }, 400, origin, env);
          if (action === "assign_moderator") {
            await env.DB!.prepare("INSERT OR IGNORE INTO room_moderators (room_id, user_id, assigned_by, created_at) VALUES (?, ?, ?, ?)")
              .bind(roomId, targetUserId, actor.id, new Date().toISOString()).run();
          } else {
            await env.DB!.prepare("DELETE FROM room_moderators WHERE room_id = ? AND user_id = ?")
              .bind(roomId, targetUserId).run();
          }
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          await seatHub.fetch(new Request("https://room-seats.internal/set-moderator", {
            method: "POST",
            headers: {
              "x-target-user-id": targetUserId,
              "x-is-moderator": action === "assign_moderator" ? "true" : "false"
            }
          }));
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, ?, '{}', ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, targetUserId, action, new Date().toISOString()).run();
          return json({ ok: true }, 200, origin, env);
        }
        if (!["toggle_mute", "kick", "unkick", "ban", "lower", "unmute", "unban"].includes(action) || !targetUserId || targetUserId === room.owner_user_id) {
          return json({ error: "invalid_moderation_action" }, 400, origin, env);
        }
        const targetModerator = await env.DB!.prepare(
          "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, targetUserId).first<{ user_id: string }>();
        if (targetModerator) return json({ error: "cannot_moderate_room_moderator", message: "لا يمكن تنفيذ الإجراء على مشرف الغرفة" }, 403, origin, env);
        const now = new Date().toISOString();
        if (action === "toggle_mute" || action === "unmute") {
          const current = await env.DB!.prepare(
            "SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ?"
          ).bind(roomId, targetUserId).first<{ is_muted: number }>();
          const nextMuted = action === "unmute" ? 0 : (current?.is_muted === 1 ? 0 : 1);
          await env.DB!.prepare(
            "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = CASE WHEN excluded.is_muted = 1 THEN excluded.muted_by ELSE NULL END, updated_at = excluded.updated_at"
          ).bind(roomId, targetUserId, nextMuted, nextMuted === 1 ? actor.id : null, now).run();
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          await seatHub.fetch(new Request("https://room-seats.internal/set-muted", {
            method: "POST",
            headers: { "x-target-user-id": targetUserId, "x-is-muted": nextMuted === 1 ? "true" : "false" }
          }));
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, targetUserId, nextMuted === 1 ? "mute" : "unmute", "{}", now).run();
          return json({ ok: true, isMuted: nextMuted === 1 }, 200, origin, env);
        }
        if (action === "unkick") {
          await env.DB!.batch([
            env.DB!.prepare("DELETE FROM room_kicks WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId),
            env.DB!.prepare("UPDATE room_user_controls SET kicked_until = NULL, updated_at = ? WHERE room_id = ? AND user_id = ?").bind(now, roomId, targetUserId)
          ]);
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, 'unkick', '{}', ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, targetUserId, now).run();
          return json({ ok: true }, 200, origin, env);
        }
        if (action === "unban") {
          await env.DB!.prepare("DELETE FROM room_bans WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId).run();
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, 'unban', '{}', ?)")
            .bind(crypto.randomUUID(), roomId, actor.id, targetUserId, now).run();
          return json({ ok: true }, 200, origin, env);
        }
        if (action === "kick" || action === "ban" || action === "lower") {
          await env.DB!.prepare("DELETE FROM room_seats WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId).run();
          if (action === "kick") {
            const kickedUntil = new Date(Date.now() + 60000).toISOString();
            await env.DB!.prepare(
              "INSERT INTO room_kicks (room_id, user_id, kicked_by, kicked_until, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET kicked_by = excluded.kicked_by, kicked_until = excluded.kicked_until, created_at = excluded.created_at"
            ).bind(roomId, targetUserId, actor.id, kickedUntil, now).run();
          }
          if (action === "kick") {
            await env.DB!.prepare(
              "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
            ).bind(now, roomId, targetUserId).run();
          }
          if (action === "ban") {
            await env.DB!.prepare(
              "INSERT INTO room_bans (room_id, user_id, banned_by, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET banned_by = excluded.banned_by, created_at = excluded.created_at"
            ).bind(roomId, targetUserId, actor.id, now).run();
          }
          await env.DB!.prepare("INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
            .bind(
              crypto.randomUUID(),
              roomId,
              actor.id,
              targetUserId,
              action,
              action === "kick" ? JSON.stringify({ reason }) : "{}",
              now
            ).run();
          const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
          await seatHub.fetch(new Request("https://room-seats.internal/remove-user", {
            method: "POST",
            headers: { "x-target-user-id": targetUserId }
          }));
          return json({ ok: true }, 200, origin, env);
        }
        return json({ error: "invalid_moderation_action" }, 400, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.moderation] failed", diagnostic);
        return json({ error: "room_moderation_failed" }, 500, origin, env);
      }
    }

    // Agora RTC tokens are issued only to authenticated members of an active room.
    const agoraTokenRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/agora-token$/);
    if (agoraTokenRoute && request.method === "POST") {
      if (!env.DB || !env.ROOM_SEATS) return json({ error: "database_unavailable" }, 503, origin, env);
      if (!env.AGORA_APP_ID || !env.AGORA_APP_CERTIFICATE || !(await isAgoraVoiceEnabled(env.DB, env))) {
        return json({ error: "agora_voice_disabled", message: "خدمة الصوت متوقفة حاليًا من إدارة Happy Live" }, 503, origin, env);
      }
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(agoraTokenRoute[1]);
        const room = await env.DB!.prepare("SELECT id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const now = new Date().toISOString();
        const [ban, kick, controlKick, control] = await Promise.all([
          env.DB!.prepare("SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_kicks WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first<{ is_muted: number }>()
        ]);
        if (ban || kick || controlKick) return json({ error: ban ? "room_banned" : "room_kicked" }, 403, origin, env);
        let requestedPublish = false;
        try {
          const body = await request.json() as Record<string, unknown>;
          requestedPublish = body.publish === true;
        } catch {
          requestedPublish = false;
        }
        const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
        const seatSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
        const seatSnapshot = await seatSnapshotResponse.json() as {
          seats?: Array<{ userId: string; seatNumber: number; expiresAt: number; isMuted?: boolean }>;
          seatControls?: Record<string, { isMuted?: boolean }>;
        };
        const currentSeat = (seatSnapshot.seats ?? []).find((entry) => entry.userId === user.id && entry.expiresAt > Date.now());
        const hasSeat = !!currentSeat;
        const seatMuted = !!currentSeat && (
          currentSeat.isMuted === true ||
          seatSnapshot.seatControls?.[String(currentSeat.seatNumber)]?.isMuted === true
        );
        const canPublish = requestedPublish && hasSeat && control?.is_muted !== 1 && !seatMuted;
        const numericUid = Number(user.happy_id);
        if (!Number.isSafeInteger(numericUid) || numericUid < 1 || numericUid > 2147483647) {
          return json({ error: "invalid_user_id" }, 400, origin, env);
        }
        const channel = "hl" + (await sha256(roomId)).slice(0, 30);
        const ttl = 3600;
        // Publisher privilege is issued only while the authenticated user owns a live seat.
        // Clients stay in the broadcaster role; publication is toggled without rejoining.
        const rtcToken = RtcTokenBuilder.buildTokenWithUidAndPrivilege(
          env.AGORA_APP_ID, env.AGORA_APP_CERTIFICATE, channel, numericUid,
          ttl, ttl, canPublish ? ttl : 0, 0, 0
        );
        return json({ ok: true, appId: env.AGORA_APP_ID, channel, uid: numericUid, token: rtcToken, role: "broadcaster", canPublish, expiresIn: ttl }, 200, origin, env);
      } catch (error) {
        console.error("[agora.token] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "agora_token_failed", message: "تعذر تجهيز اتصال الصوت" }, 500, origin, env);
      }
    }

    // Eight shared microphone seats. A seat is leased for 45 seconds and renewed by
    // authenticated clients, so abandoned seats disappear after disconnects.
    const seatRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/seats$/);
    if (seatRoute && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB || !env.ROOM_SEATS) return json({ error: "room_seats_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(seatRoute[1]);
        const now = new Date().toISOString();
        const dayKey = saudiDayKey(now);
        const room = await env.DB!.prepare(
          "SELECT r.id, r.owner_user_id, r.name, r.description, COALESCE(ra.announcement, r.description, '') AS announcement, r.image_url, r.room_code, COALESCE(r.locked, 0) AS locked, COALESCE(rl.level, 1) AS level, COALESCE(rx.total_exp, 0) AS total_exp, p.display_name AS owner_name, p.avatar_key AS owner_avatar_url, p.country_name AS owner_country_name FROM rooms r LEFT JOIN room_announcements ra ON ra.room_id = r.id LEFT JOIN room_levels rl ON rl.room_id = r.id LEFT JOIN room_experience rx ON rx.room_id = r.id LEFT JOIN profiles p ON p.user_id = r.owner_user_id WHERE r.id = ? AND r.status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string; name: string; description: string; announcement: string; image_url: string | null; room_code: string; locked: number; level: number; total_exp: number; owner_name: string | null; owner_avatar_url: string | null; owner_country_name: string | null }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);

        const [voiceEnabled, activeBan, activeKick, controlKick, profile, myControl, roomModerator] = await Promise.all([
          isAgoraVoiceEnabled(env.DB, env),
          env.DB!.prepare("SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_kicks WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB!.prepare("SELECT avatar_key, country_name FROM profiles WHERE user_id = ? LIMIT 1").bind(user.id).first<{ avatar_key: string | null; country_name: string | null }>(),
          env.DB!.prepare("SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first<{ is_muted: number }>(),
          env.DB!.prepare("SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first()
        ]);
        if (activeKick || controlKick) return json({ error: "room_kicked", message: "تم طردك مؤقتاً من الغرفة" }, 403, origin, env);
        const savedRoomSettings = await env.DB!.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1")
          .bind(roomId).first<{ settings_json: string }>();
        let roomSettings: Record<string, unknown> = {};
        try { roomSettings = savedRoomSettings?.settings_json ? JSON.parse(savedRoomSettings.settings_json) as Record<string, unknown> : {}; } catch { roomSettings = {}; }
        const isRoomOwner = room.owner_user_id === user.id;
        const isRoomModerator = !!roomModerator;
        if (room.locked === 1 && !isRoomOwner && !isRoomModerator) {
          const activeVisit = await env.DB!.prepare(
            "SELECT 1 AS active FROM room_chat_visits WHERE room_id = ? AND user_id = ? AND exited_at IS NULL LIMIT 1"
          ).bind(roomId, user.id).first();
          if (!activeVisit) return json({ error: "room_locked", message: "الغرفة مقفلة حاليًا" }, 403, origin, env);
        }
        if (String(roomSettings.whoEnter ?? "everyone") === "ownerAndAdmins" && !isRoomOwner && !isRoomModerator) {
          return json({ error: "room_entry_restricted", message: "دخول هذه الغرفة متاح للمالك والمشرفين فقط" }, 403, origin, env);
        }

        const seatHub = env.ROOM_SEATS.get(env.ROOM_SEATS.idFromName(roomId));
        await seatHub.fetch(new Request("https://room-seats.internal/set-mic-policy", {
          method: "POST",
          headers: { "x-who-mic": String(roomSettings.whoMic ?? "membersOnly") }
        }));
        if (voiceEnabled) {
          await seatHub.fetch(new Request("https://room-seats.internal/enable", { method: "POST" }));
        }
        const identityHeaders = new Headers({
          "x-user-id": user.id,
          "x-user-name": user.display_name?.trim() || "مستخدم",
          "x-user-code": user.happy_id ?? "",
          "x-avatar-url": profile?.avatar_key ?? "",
          "x-country-name": profile?.country_name ?? "",
          "x-is-muted": myControl?.is_muted === 1 ? "true" : "false",
          "x-is-room-owner": room.owner_user_id === user.id ? "true" : "false",
          "x-is-room-moderator": roomModerator ? "true" : "false"
        });

        if (request.method === "POST") {
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }

          if (body.heartbeat === true) {
            const heartbeatHeaders = new Headers(identityHeaders);
            const heartbeat = await seatHub.fetch(new Request("https://room-seats.internal/heartbeat", {
              method: "POST", headers: heartbeatHeaders
            }));
            await env.DB!.prepare(
              "UPDATE room_chat_visits SET last_seen_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
            ).bind(now, roomId, user.id).run();
            if (!heartbeat.ok) return json({ error: "seat_heartbeat_failed" }, 503, origin, env);
            const heartbeatSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
            const heartbeatSnapshot = await heartbeatSnapshotResponse.json() as { seats?: Array<Record<string, unknown>> };
            const isOnMic = (heartbeatSnapshot.seats ?? []).some((seat) => String(seat.userId ?? "") === user.id);
            if (isOnMic) {
              await awardRoomSeatExperience(env.DB, roomId, user.id, now);
            } else {
              // Only continuous microphone time counts; audience time resets the 5-minute clock.
              await resetRoomSeatExperienceTimer(env.DB, roomId, user.id, now);
            }
          } else {
            if (!voiceEnabled) return json({ error: "agora_voice_disabled", message: "الميكروفونات متوقفة حاليًا من إدارة التطبيق" }, 503, origin, env);
            if (activeBan) return json({ error: "room_banned", message: "أنت محظور من استخدام المايك في هذه الغرفة" }, 403, origin, env);
            const to = body.seatNumber === null ? null : Number(body.seatNumber);
            if (to !== null && String(roomSettings.whoMic ?? "membersOnly") === "ownerAndAdmins" && !isRoomOwner && !isRoomModerator) {
              return json({ error: "room_mic_restricted", message: "استخدام المايك متاح للمالك والمشرفين فقط" }, 403, origin, env);
            }
            if (to !== null && (!Number.isInteger(to) || to < 1 || to > Number(roomSettings.seats ?? 8))) {
              return json({ error: "invalid_seat_number" }, 400, origin, env);
            }
            const moveHeaders = new Headers(identityHeaders);
            moveHeaders.set("content-type", "application/json");
            const moveResponse = await seatHub.fetch(new Request("https://room-seats.internal/move", {
              method: "POST",
              headers: moveHeaders,
              body: JSON.stringify({ to, version: Number.isSafeInteger(Number(body.version)) && Number(body.version) > 0 ? Number(body.version) : null })
            }));
            const moveData = await moveResponse.json() as Record<string, unknown>;
            if (!moveResponse.ok || moveData.ok !== true) {
              const failedSnapshotResponse = await seatHub.fetch(new Request("https://room-seats.internal/snapshot"));
              const failedSnapshot = await failedSnapshotResponse.json() as {
                seats?: Array<Record<string, unknown>>;
                seatControls?: Record<string, { isLocked?: boolean; isMuted?: boolean }>;
              };
              const failedSeatByNumber = new Map((failedSnapshot.seats ?? []).map((seat) => [Number(seat.seatNumber), seat] as const));
              const failedSeatControls = failedSnapshot.seatControls ?? {};
              const failedSeatCount = Math.min(24, Math.max(1, Number(roomSettings.seats ?? 8)));
              const failedSeats = Array.from({ length: failedSeatCount }, (_, index) => {
                const seatNumber = index + 1;
                const seat = failedSeatByNumber.get(seatNumber);
                const control = failedSeatControls[String(seatNumber)] ?? {};
                return {
                  seatNumber,
                  userId: seat?.userId ?? "",
                  userCode: seat?.userCode ?? "",
                  uid: seat?.uid ?? null,
                  isMuted: seat?.isMuted === true || control.isMuted === true,
                  isLocked: control.isLocked === true,
                  isRoomOwner: seat?.isRoomOwner === true,
                  isRoomModerator: seat?.isRoomModerator === true,
                  name: seat?.name || "",
                  avatarUrl: seat?.avatarUrl ?? "",
                  countryName: seat?.countryName ?? "",
                  isMe: seat?.userId === user.id
                };
              });
              return json({
                ok: false,
                error: moveData.code === "seat_occupied" ? "seat_occupied" : moveData.code === "mic_restricted" ? "mic_restricted" : moveData.code === "seat_locked" ? "seat_locked" : "seat_move_failed",
                message: moveData.code === "seat_occupied" ? "هذا المايك مشغول" : moveData.code === "mic_restricted" ? "استخدام المايك متاح للمالك والمشرفين فقط" : moveData.code === "seat_locked" ? "هذا المايك مقفل" : "تعذر تغيير المايك",
                mySeat: failedSeats.find((seat) => seat.userId === user.id)?.seatNumber ?? null,
                seats: failedSeats
              }, moveResponse.status, origin, env);
            }
            // Reset only when the server confirms an actual seat change.
            // Re-selecting the same seat must not erase accumulated mic time.
            if (moveData.from !== moveData.mySeat) {
              await resetRoomSeatExperienceTimer(env.DB, roomId, user.id, now);
            }
          }
        }

        if (!voiceEnabled) {
          await seatHub.fetch(new Request("https://room-seats.internal/clear", { method: "POST" }));
        }
        const [snapshotResponse, audience] = await Promise.all([
          seatHub.fetch(new Request("https://room-seats.internal/snapshot")),
          env.DB!.prepare(
            "SELECT COUNT(DISTINCT v.user_id) AS count FROM room_chat_visits v WHERE v.room_id = ? AND v.exited_at IS NULL AND v.last_seen_at >= ?"
          ).bind(roomId, new Date(Date.now() - 45000).toISOString()).first<{ count: number }>()
        ]);
        const snapshot = await snapshotResponse.json() as {
          seats?: Array<Record<string, unknown>>;
          seatControls?: Record<string, { isLocked?: boolean; isMuted?: boolean }>;
          revision?: number;
        };
        const activeSeats = snapshot.seats ?? [];
        const seatControls = snapshot.seatControls ?? {};
        const activeSeatIds = activeSeats
          .map((seat) => String(seat.userId ?? ""))
          .filter((id) => id.length > 0);
        const profileByUserId = new Map<string, { display_name: string | null; avatar_key: string | null; country_name: string | null }>();
        if (activeSeatIds.length > 0) {
          const placeholders = activeSeatIds.map(() => "?").join(",");
          const profileRows = await env.DB!.prepare(
            "SELECT user_id, display_name, avatar_key, country_name FROM profiles WHERE user_id IN (" + placeholders + ")"
          ).bind(...activeSeatIds).all<{ user_id: string; display_name: string | null; avatar_key: string | null; country_name: string | null }>();
          for (const row of profileRows.results ?? []) {
            profileByUserId.set(row.user_id, row);
          }
        }
        const activeSeatByNumber = new Map(activeSeats.map((seat) => [Number(seat.seatNumber), seat] as const));
        const configuredSeatCount = Math.min(24, Math.max(1, Number(roomSettings.seats ?? 8)));
        const seats = Array.from({ length: configuredSeatCount }, (_, index) => {
          const seatNumber = index + 1;
          const seat = activeSeatByNumber.get(seatNumber);
          const control = seatControls[String(seatNumber)] ?? {};
          if (!seat) {
            return {
              seatNumber,
              userId: "",
              userCode: "",
              uid: null,
              isMuted: control.isMuted === true,
              isLocked: control.isLocked === true,
              isRoomOwner: false,
              isRoomModerator: false,
              name: "",
              avatarUrl: "",
              countryName: "",
              joinedAt: null,
              isMe: false
            };
          }
          const profile = profileByUserId.get(String(seat.userId ?? ""));
          return {
            seatNumber: seat.seatNumber,
            userId: seat.userId,
            userCode: seat.userCode ?? "",
            uid: seat.uid ?? null,
            isMuted: seat.isMuted === true || control.isMuted === true,
            isLocked: control.isLocked === true,
            isRoomOwner: seat.isRoomOwner === true,
            isRoomModerator: seat.isRoomModerator === true,
            name: profile?.display_name?.trim() || seat.name || "مستخدم",
            avatarUrl: profile?.avatar_key ?? seat.avatarUrl ?? "",
            countryName: profile?.country_name ?? "",
            joinedAt: null,
            isMe: seat.userId === user.id
          };
        });
        const mySeat = seats.find((seat) => seat.userId === user.id)?.seatNumber ?? null;

        const audienceCutoff = new Date(Date.now() - 45000).toISOString();
        await env.DB!.prepare(
          "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND exited_at IS NULL AND last_seen_at < ?"
        ).bind(now, roomId, audienceCutoff).run();
        const audienceUsersResult = await env.DB!.prepare(
          "SELECT v.user_id, p.display_name, p.happy_id, p.avatar_key, p.country_code, p.country_name, MAX(v.last_seen_at) AS last_seen_at, MAX(CASE WHEN v.user_id = ? THEN 1 ELSE 0 END) AS is_room_owner, EXISTS(SELECT 1 FROM room_moderators rm WHERE rm.room_id = v.room_id AND rm.user_id = v.user_id) AS is_room_moderator FROM room_chat_visits v LEFT JOIN profiles p ON p.user_id = v.user_id WHERE v.room_id = ? AND v.exited_at IS NULL AND v.last_seen_at >= ? GROUP BY v.user_id, p.display_name, p.happy_id, p.avatar_key, p.country_code, p.country_name ORDER BY last_seen_at DESC LIMIT 100"
        ).bind(room.owner_user_id, roomId, audienceCutoff).all<{ user_id: string; display_name: string | null; happy_id: string | null; avatar_key: string | null; country_code: string | null; country_name: string | null; last_seen_at: string; is_room_owner: number; is_room_moderator: number }>();
        const seatedIds = new Set(seats.map((seat) => String(seat.userId)));
        const audienceRows = audienceUsersResult.results ?? [];
        const seatedVisitorCount = audienceRows.filter((visitor) => seatedIds.has(visitor.user_id)).length;
        const audienceUsers = audienceRows
          .filter((visitor) => !seatedIds.has(visitor.user_id))
          .map((visitor) => ({
            userId: visitor.user_id,
            name: visitor.display_name?.trim() || "مستخدم",
            userCode: visitor.happy_id ?? "",
            avatarUrl: visitor.avatar_key ?? "",
            countryName: visitor.country_name ?? "",
            countryCode: visitor.country_code ?? "",
            isRoomOwner: visitor.is_room_owner === 1,
            isRoomModerator: visitor.is_room_moderator === 1
          }));
        const experience = roomExperienceProgress(Number(room.total_exp ?? 0));
        const [dailyExperience, dailyMicExperience, dailyGiftExperience] = await Promise.all([
          env.DB!.prepare(
            "SELECT COALESCE((SELECT SUM(points) FROM room_exp_awards WHERE room_id = ? AND day_key = ?), 0) + COALESCE((SELECT SUM(points) FROM room_exp_gift_awards WHERE room_id = ? AND day_key = ?), 0) AS points"
          ).bind(room.id, dayKey, room.id, dayKey).first<{ points: number }>(),
          env.DB!.prepare(
            "SELECT COALESCE(SUM(points), 0) AS points FROM room_exp_awards WHERE room_id = ? AND day_key = ?"
          ).bind(room.id, dayKey).first<{ points: number }>(),
          env.DB!.prepare(
            "SELECT COALESCE(SUM(points), 0) AS points FROM room_exp_gift_awards WHERE room_id = ? AND day_key = ?"
          ).bind(room.id, dayKey).first<{ points: number }>()
        ]);
        return json({
          ok: true,
          audienceCount: Math.max(0, (audience?.count ?? 0) - seatedVisitorCount),
          audienceUsers,
          voiceEnabled,
          seatRevision: snapshot.revision ?? 0,
          room: { id: room.id, name: room.name, description: room.description, announcement: room.announcement, imageUrl: room.image_url, roomCode: room.room_code, locked: room.locked === 1, level: room.level, palaceStatus: room.level >= 5 ? 'مفعّل' : 'غير مفعّل', experienceLevel: experience.level, experienceExp: experience.exp, experienceNextLevelExp: experience.nextLevelExp, experienceTotalExp: Number(room.total_exp ?? 0), micCount: Number(roomSettings.seats ?? 8), micLayoutId: String(roomSettings.micLayoutId ?? ("m" + Number(roomSettings.seats ?? 8))), dailyExperienceExp: Number(dailyExperience?.points ?? 0), dailyMicExperienceExp: Number(dailyMicExperience?.points ?? 0), dailyGiftExperienceExp: Number(dailyGiftExperience?.points ?? 0), dailyExperienceMax: ROOM_EXP_DAILY_ROOM_CAP, dailyResetInSeconds: secondsUntilSaudiMidnight(now), dailyExperienceUpdatedAt: now, dailyExperienceBreakdown: { total: Number(dailyExperience?.points ?? 0), microphone: Number(dailyMicExperience?.points ?? 0), gifts: Number(dailyGiftExperience?.points ?? 0) } },
          owner: { id: room.owner_user_id, name: room.owner_name?.trim() || "صاحب الغرفة", avatarUrl: room.owner_avatar_url ?? "", countryName: room.owner_country_name ?? "" },
          me: { id: user.id, name: user.display_name?.trim() || "مستخدم", userCode: user.happy_id ?? "", avatarUrl: profile?.avatar_key ?? "", countryName: profile?.country_name ?? "", isMuted: myControl?.is_muted === 1, isBanned: !!activeBan },
          isOwner: room.owner_user_id === user.id,
          isModerator: !!roomModerator,
          mySeat,
          seats
        }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.seats] failed", diagnostic);
        return json({ error: "room_seats_failed" }, 500, origin, env);
      }
    }


    // Social posts: authenticated feed, likes, comments, and follows.
    if (url.pathname === "/api/v1/posts" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const rows = await env.DB!.prepare(
          "SELECT p.id, p.user_id, p.content, p.image_url, p.visibility, p.created_at, pr.display_name, pr.happy_id, pr.avatar_key, " +
          "EXISTS(SELECT 1 FROM post_likes l WHERE l.post_id = p.id AND l.user_id = ?) AS liked, " +
          "(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = p.id) AS likes_count, " +
          "(SELECT COUNT(*) FROM post_comments c WHERE c.post_id = p.id) AS comments_count, " +
          "EXISTS(SELECT 1 FROM user_follows f WHERE f.following_id = p.user_id AND f.follower_id = ?) AS followed " +
          "FROM posts p LEFT JOIN profiles pr ON pr.user_id = p.user_id " +
          "WHERE p.status = 'published' " +
          "AND (p.user_id = ? OR p.visibility = 'public' OR (p.visibility = 'followers' AND EXISTS (SELECT 1 FROM user_follows vf WHERE vf.follower_id = ? AND vf.following_id = p.user_id))) " +
          "AND NOT EXISTS (SELECT 1 FROM user_hidden_users hu WHERE hu.user_id = ? AND hu.hidden_user_id = p.user_id) " +
          "ORDER BY p.created_at DESC LIMIT 50"
        ).bind(user.id, user.id, user.id, user.id, user.id).all<{
          id: string; user_id: string; content: string; image_url: string | null; visibility: string; created_at: string;
          display_name: string | null; happy_id: string | null; avatar_key: string | null;
          liked: number; likes_count: number; comments_count: number; followed: number;
        }>();
        return json({ ok: true, posts: (rows.results ?? []).map(p => ({
          id: p.id, userId: p.user_id, name: p.display_name?.trim() || "مستخدم",
          userCode: p.happy_id, avatarUrl: p.avatar_key, content: p.content, imageUrl: p.image_url, createdAt: p.created_at,
          liked: Boolean(p.liked), likesCount: p.likes_count,
          commentsCount: p.comments_count, followed: Boolean(p.followed), visibility: p.visibility,
          isMine: p.user_id === user.id
        })) }, 200, origin, env);
      } catch (error) {
        console.error("[posts.list] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "posts_unavailable" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/posts" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const content = typeof body.content === "string" ? body.content.trim() : "";
        const imageUrl = typeof body.imageUrl === "string" ? body.imageUrl.trim() : "";
        if (!content && !imageUrl) return json({ error: "post_content_required", message: "أضف نصاً أو صورة للمنشور" }, 400, origin, env);
        if (content.length > 2000) return json({ error: "post_too_long", message: "المنشور طويل جداً" }, 400, origin, env);
        if (imageUrl) {
          try {
            const parsed = new URL(imageUrl);
            if (parsed.protocol !== "https:" || !parsed.hostname.endsWith("imagekit.io")) throw new Error("invalid");
          } catch {
            return json({ error: "invalid_post_image", message: "رابط الصورة غير صالح" }, 400, origin, env);
          }
        }
        const id = crypto.randomUUID();
        const createdAt = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO posts (id, user_id, content, image_url, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)")
          .bind(id, user.id, content, imageUrl || null, createdAt, createdAt).run();
        return json({ ok: true, post: { id, userId: user.id, name: user.display_name?.trim() || "مستخدم", userCode: user.happy_id, content, imageUrl: imageUrl || null, createdAt, liked: false, likesCount: 0, commentsCount: 0, followed: false, isMine: true } }, 201, origin, env);
      } catch (error) {
        console.error("[posts.create] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "post_creation_failed" }, 500, origin, env);
      }
    }


    const postActionRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})$/i);
    const postVisibilityRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/visibility$/i);
    if ((postActionRoute && request.method === "DELETE") || (postVisibilityRoute && request.method === "PATCH")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const postId = postActionRoute?.[1] ?? postVisibilityRoute?.[1];
        const post = await env.DB!.prepare("SELECT id, user_id FROM posts WHERE id = ? AND status = 'published'").bind(postId).first<{ id: string; user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id !== user.id) return json({ error: "not_post_owner" }, 403, origin, env);
        if (request.method === "DELETE") {
          await env.DB!.prepare("UPDATE posts SET status = 'deleted', updated_at = ? WHERE id = ? AND user_id = ?").bind(new Date().toISOString(), postId, user.id).run();
          return json({ ok: true }, 200, origin, env);
        }
        const body = await request.json() as Record<string, unknown>;
        const visibility = typeof body.visibility === "string" ? body.visibility : "";
        if (!["public", "followers", "private"].includes(visibility)) return json({ error: "invalid_visibility" }, 400, origin, env);
        await env.DB!.prepare("UPDATE posts SET visibility = ?, updated_at = ? WHERE id = ? AND user_id = ?").bind(visibility, new Date().toISOString(), postId, user.id).run();
        return json({ ok: true, visibility }, 200, origin, env);
      } catch (error) {
        console.error("[posts.manage] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "post_update_failed" }, 500, origin, env);
      }
    }

    const hideUserRoute = url.pathname.match(/^\/api\/v1\/users\/([0-9a-f-]{36})\/hide$/i);
    if (hideUserRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const targetId = hideUserRoute[1];
        if (targetId === user.id) return json({ error: "cannot_hide_self" }, 400, origin, env);
        const target = await env.DB!.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetId).first();
        if (!target) return json({ error: "user_not_found" }, 404, origin, env);
        await env.DB!.prepare("INSERT INTO user_hidden_users (user_id, hidden_user_id, created_at) VALUES (?, ?, ?) ON CONFLICT(user_id, hidden_user_id) DO NOTHING").bind(user.id, targetId, new Date().toISOString()).run();
        return json({ ok: true }, 200, origin, env);
      } catch (error) {
        console.error("[users.hide] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "hide_user_failed" }, 500, origin, env);
      }
    }

    const postReportRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/report$/i);
    if (postReportRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 300) : "general";
        const post = await env.DB!.prepare("SELECT id, user_id FROM posts WHERE id = ? AND status = 'published'").bind(postReportRoute[1]).first<{ id: string; user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id === user.id) return json({ error: "cannot_report_own_post" }, 400, origin, env);
        await env.DB!.prepare("INSERT INTO post_reports (id, post_id, reporter_id, reported_user_id, reason, created_at) VALUES (?, ?, ?, ?, ?, ?)").bind(crypto.randomUUID(), post.id, user.id, post.user_id, reason || "general", new Date().toISOString()).run();
        return json({ ok: true }, 201, origin, env);
      } catch (error) {
        console.error("[posts.report] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "report_failed" }, 500, origin, env);
      }
    }

    const postLikeRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/like$/i);
    if (postLikeRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const post = await env.DB!.prepare("SELECT id FROM posts WHERE id = ? AND status = 'published'").bind(postLikeRoute[1]).first();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        const existing = await env.DB!.prepare("SELECT 1 AS found FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postLikeRoute[1], user.id).first();
        if (existing) await env.DB!.prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postLikeRoute[1], user.id).run();
        else await env.DB!.prepare("INSERT INTO post_likes (post_id, user_id, created_at) VALUES (?, ?, ?)").bind(postLikeRoute[1], user.id, new Date().toISOString()).run();
        const count = await env.DB!.prepare("SELECT COUNT(*) AS total FROM post_likes WHERE post_id = ?").bind(postLikeRoute[1]).first<{ total: number }>();
        return json({ ok: true, liked: !existing, likesCount: count?.total ?? 0 }, 200, origin, env);
      } catch (error) {
        console.error("[posts.like] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "like_failed" }, 500, origin, env);
      }
    }

    const commentRepliesRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/comments\/([0-9a-f-]{36})\/replies$/i);
    if (commentRepliesRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const content = typeof body.content === "string" ? body.content.trim() : "";
        const parentReplyId = typeof body.parentReplyId === "string" && body.parentReplyId.trim() ? body.parentReplyId.trim() : null;
        if (!content || content.length > 500) return json({ error: "invalid_reply", message: "اكتب رداً لا يتجاوز 500 حرف" }, 400, origin, env);
        const parent = await env.DB!.prepare(
          "SELECT c.id FROM post_comments c INNER JOIN posts p ON p.id = c.post_id WHERE c.id = ? AND c.post_id = ? AND p.status = 'published'"
        ).bind(commentRepliesRoute[2], commentRepliesRoute[1]).first();
        if (!parent) return json({ error: "comment_not_found" }, 404, origin, env);
        if (parentReplyId) {
          const parentReply = await env.DB!.prepare("SELECT id FROM post_comment_replies WHERE id = ? AND comment_id = ?")
            .bind(parentReplyId, commentRepliesRoute[2]).first();
          if (!parentReply) return json({ error: "parent_reply_not_found" }, 404, origin, env);
        }
        const id = crypto.randomUUID();
        const createdAt = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO post_comment_replies (id, comment_id, user_id, content, created_at, parent_reply_id) VALUES (?, ?, ?, ?, ?, ?)")
          .bind(id, commentRepliesRoute[2], user.id, content, createdAt, parentReplyId).run();
        const profile = await env.DB!.prepare("SELECT avatar_key FROM profiles WHERE user_id = ?")
          .bind(user.id).first<{ avatar_key: string | null }>();
        return json({ ok: true, reply: { id, commentId: commentRepliesRoute[2], userId: user.id, content, createdAt, name: user.display_name?.trim() || "مستخدم", userCode: user.happy_id, avatarUrl: profile?.avatar_key ?? null } }, 201, origin, env);
      } catch (error) {
        console.error("[posts.comments.reply] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "reply_creation_failed" }, 500, origin, env);
      }
    }


    if (url.pathname === "/api/v1/admin/reports/post-comments" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const admin = await authenticatedAdmin(request, env.DB);
        if (!admin) return json({ error: "authentication_required" }, 401, origin, env);
        
        const status = url.searchParams.get("status") || "pending";
        if (!["pending", "reviewed", "dismissed", "actioned", "all"].includes(status)) {
          return json({ error: "invalid_report_status" }, 400, origin, env);
        }
        const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 50), 1), 100);
        const rows = await env.DB!.prepare(
          "SELECT r.id, r.post_id, r.comment_id, r.reason, r.status, r.created_at, " +
          "reporter.id AS reporter_id, reporter_profile.display_name AS reporter_name, reporter_profile.happy_id AS reporter_code, " +
          "reported.id AS reported_user_id, reported_profile.display_name AS reported_name, reported_profile.happy_id AS reported_code, " +
          "c.content AS comment_content, p.content AS post_content, p.image_url AS post_image_url, " +
          "reviewer_profile.display_name AS reviewer_name " +
          "FROM post_comment_reports r " +
          "LEFT JOIN users reporter ON reporter.id = r.reporter_id " +
          "LEFT JOIN profiles reporter_profile ON reporter_profile.user_id = reporter.id " +
          "LEFT JOIN users reported ON reported.id = r.reported_user_id " +
          "LEFT JOIN profiles reported_profile ON reported_profile.user_id = reported.id " +
          "LEFT JOIN post_comments c ON c.id = r.comment_id AND c.post_id = r.post_id " +
          "LEFT JOIN posts p ON p.id = r.post_id " +
          "LEFT JOIN profiles reviewer_profile ON reviewer_profile.user_id = r.reviewed_by " +
          (status === "all" ? "" : "WHERE r.status = ? ") +
          "ORDER BY r.created_at DESC LIMIT ?"
        ).bind(...(status === "all" ? [limit] : [status, limit])).all<{
          id: string; post_id: string; comment_id: string; reason: string; status: string; created_at: string;
          reporter_id: string | null; reporter_name: string | null; reporter_code: string | null;
          reported_user_id: string | null; reported_name: string | null; reported_code: string | null;
          comment_content: string | null; post_content: string | null; post_image_url: string | null; reviewer_name: string | null;
        }>();
        return json({ ok: true, reports: rows.results ?? [] }, 200, origin, env);
      } catch (error) {
        console.error("[admin.post-comment-reports.list] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_reports_unavailable" }, 500, origin, env);
      }
    }

    const commentActionRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/comments\/([0-9a-f-]{36})(?:\/(report))?$/i);
    if (commentActionRoute && request.method === "DELETE" && !commentActionRoute[3]) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const post = await env.DB!.prepare("SELECT user_id FROM posts WHERE id = ? AND status = 'published'")
          .bind(commentActionRoute[1]).first<{ user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id !== user.id) return json({ error: "forbidden" }, 403, origin, env);
        const comment = await env.DB!.prepare("SELECT id FROM post_comments WHERE id = ? AND post_id = ?")
          .bind(commentActionRoute[2], commentActionRoute[1]).first<{ id: string }>();
        if (!comment) return json({ error: "comment_not_found" }, 404, origin, env);
        await env.DB!.prepare("DELETE FROM post_comment_replies WHERE comment_id = ?").bind(comment.id).run();
        await env.DB!.prepare("DELETE FROM post_comments WHERE id = ? AND post_id = ?")
          .bind(comment.id, commentActionRoute[1]).run();
        return json({ ok: true }, 200, origin, env);
      } catch (error) {
        console.error("[posts.comments.delete] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "comment_delete_failed" }, 500, origin, env);
      }
    }
    if (commentActionRoute && request.method === "POST" && commentActionRoute[3] === "report") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const comment = await env.DB!.prepare(
          "SELECT c.id, c.user_id FROM post_comments c INNER JOIN posts p ON p.id = c.post_id WHERE c.id = ? AND c.post_id = ? AND p.status = 'published'"
        ).bind(commentActionRoute[2], commentActionRoute[1]).first<{ id: string; user_id: string }>();
        if (!comment) return json({ error: "comment_not_found" }, 404, origin, env);
        if (comment.user_id === user.id) return json({ error: "cannot_report_own_comment" }, 400, origin, env);
        const existing = await env.DB!.prepare("SELECT id FROM post_comment_reports WHERE comment_id = ? AND reporter_id = ?")
          .bind(comment.id, user.id).first();
        if (existing) return json({ error: "already_reported" }, 409, origin, env);
        const reportId = crypto.randomUUID();
        const reportedAt = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO post_comment_reports (id, post_id, comment_id, reporter_id, reported_user_id, reason, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)")
          .bind(reportId, commentActionRoute[1], comment.id, user.id, comment.user_id, "general", reportedAt).run();
        await env.DB!.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
          .bind(crypto.randomUUID(), user.id, "post_comment_report.created", "post_comment_report", reportId, JSON.stringify({ postId: commentActionRoute[1], commentId: comment.id, reportedUserId: comment.user_id }), reportedAt).run();
        return json({ ok: true, reportId }, 201, origin, env);
      } catch (error) {
        console.error("[posts.comments.report] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "comment_report_failed" }, 500, origin, env);
      }
    }

    const postCommentsRoute = url.pathname.match(/^\/api\/v1\/posts\/([0-9a-f-]{36})\/comments$/i);
    if (postCommentsRoute && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const rows = await env.DB!.prepare(
          "SELECT c.id, c.user_id, c.content, c.created_at, p.display_name, p.happy_id, p.avatar_key FROM post_comments c LEFT JOIN profiles p ON p.user_id = c.user_id WHERE c.post_id = ? ORDER BY c.created_at ASC LIMIT 100"
        ).bind(postCommentsRoute[1]).all<{ id: string; user_id: string; content: string; created_at: string; display_name: string | null; happy_id: string | null; avatar_key: string | null }>();
        const comments = (rows.results ?? []).map(c => ({ id: c.id, userId: c.user_id, content: c.content, createdAt: c.created_at, name: c.display_name?.trim() || "مستخدم", userCode: c.happy_id, avatarUrl: c.avatar_key, replies: [] as Array<Record<string, unknown>> }));
        const replies = await env.DB!.prepare(
          "SELECT r.id, r.comment_id, r.parent_reply_id, r.user_id, r.content, r.created_at, p.display_name, p.happy_id, p.avatar_key FROM post_comment_replies r LEFT JOIN profiles p ON p.user_id = r.user_id INNER JOIN post_comments c ON c.id = r.comment_id WHERE c.post_id = ? ORDER BY r.created_at ASC"
        ).bind(postCommentsRoute[1]).all<{ id: string; comment_id: string; parent_reply_id: string | null; user_id: string; content: string; created_at: string; display_name: string | null; happy_id: string | null; avatar_key: string | null }>();
        const commentsById = new Map(comments.map(c => [c.id, c]));
        const repliesById = new Map<string, Record<string, unknown>>();
        for (const row of replies.results ?? []) {
          repliesById.set(row.id, {
            id: row.id, commentId: row.comment_id, parentReplyId: row.parent_reply_id,
            userId: row.user_id, content: row.content, createdAt: row.created_at,
            name: row.display_name?.trim() || "مستخدم", userCode: row.happy_id,
            avatarUrl: row.avatar_key, replies: [] as Array<Record<string, unknown>>
          });
        }
        for (const row of replies.results ?? []) {
          const node = repliesById.get(row.id)!;
          if (row.parent_reply_id) {
            const parentNode = repliesById.get(row.parent_reply_id);
            if (parentNode) (parentNode.replies as Array<Record<string, unknown>>).push(node);
            else commentsById.get(row.comment_id)?.replies.push(node);
          } else {
            commentsById.get(row.comment_id)?.replies.push(node);
          }
        }
        return json({ ok: true, comments }, 200, origin, env);
      } catch (error) {
        console.error("[posts.comments.list] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "comments_unavailable" }, 500, origin, env);
      }
    }

    if (postCommentsRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const content = typeof body.content === "string" ? body.content.trim() : "";
        if (!content || content.length > 500) return json({ error: "invalid_comment", message: "اكتب تعليقاً لا يتجاوز 500 حرف" }, 400, origin, env);
        const post = await env.DB!.prepare("SELECT id FROM posts WHERE id = ? AND status = 'published'").bind(postCommentsRoute[1]).first();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        const createdAt = new Date().toISOString();
        const allowed = await env.DB!.prepare(
          "INSERT INTO post_comment_rate_limits (user_id, last_comment_at) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET last_comment_at = excluded.last_comment_at WHERE CAST(strftime('%s', excluded.last_comment_at) AS INTEGER) - CAST(strftime('%s', post_comment_rate_limits.last_comment_at) AS INTEGER) >= 30 RETURNING user_id"
        ).bind(user.id, createdAt).first<{ user_id: string }>();
        if (!allowed) {
          const last = await env.DB!.prepare("SELECT last_comment_at FROM post_comment_rate_limits WHERE user_id = ?")
            .bind(user.id).first<{ last_comment_at: string }>();
          const elapsed = last ? Math.max(0, Math.floor((Date.now() - Date.parse(last.last_comment_at)) / 1000)) : 0;
          const retryAfter = Math.max(1, 30 - elapsed);
          return json({ error: "comment_cooldown", message: `انتظر ${retryAfter} ثانية قبل كتابة تعليق جديد`, retryAfterSeconds: retryAfter }, 429, origin, env);
        }
        const id = crypto.randomUUID();
        await env.DB!.prepare("INSERT INTO post_comments (id, post_id, user_id, content, created_at) VALUES (?, ?, ?, ?, ?)")
          .bind(id, postCommentsRoute[1], user.id, content, createdAt).run();
        const commenterProfile = await env.DB!.prepare("SELECT avatar_key FROM profiles WHERE user_id = ?")
          .bind(user.id).first<{ avatar_key: string | null }>();
        return json({ ok: true, comment: { id, userId: user.id, content, createdAt, name: user.display_name?.trim() || "مستخدم", userCode: user.happy_id, avatarUrl: commenterProfile?.avatar_key ?? null } }, 201, origin, env);
      } catch (error) {
        console.error("[posts.comments.create] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "comment_creation_failed" }, 500, origin, env);
      }
    }

    const userByCodeRoute = url.pathname.match(/^\/api\/v1\/users\/by-code\/(\d{8})$/);
    if (userByCodeRoute && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const viewer = await authenticatedUser(request, env.DB);
        if (!viewer) return json({ error: "authentication_required" }, 401, origin, env);
        const target = await env.DB!.prepare(
          "SELECT u.id, p.display_name, p.happy_id, p.avatar_key FROM users u " +
          "INNER JOIN profiles p ON p.user_id = u.id " +
          "WHERE p.happy_id = ? AND u.status = 'active' LIMIT 1"
        ).bind(userByCodeRoute[1]).first<{
          id: string; display_name: string | null; happy_id: string;
          avatar_key: string | null;
        }>();
        if (!target) return json({ error: "user_not_found", message: "لم يتم العثور على مستخدم بهذا ID" }, 404, origin, env);
        return json({ ok: true, user: {
          id: target.id, name: target.display_name?.trim() || "مستخدم",
          userCode: target.happy_id, avatarUrl: target.avatar_key
        } }, 200, origin, env);
      } catch (error) {
        console.error("[users.by-code] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "user_lookup_failed" }, 500, origin, env);
      }
    }

    const publicProfileRoute = url.pathname.match(/^\/api\/v1\/users\/([0-9a-f-]{36})\/profile$/i);
    if (publicProfileRoute && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const viewer = await authenticatedUser(request, env.DB);
        if (!viewer) return json({ error: "authentication_required" }, 401, origin, env);
        const targetId = publicProfileRoute[1];
        const profile = await env.DB!.prepare(
          "SELECT u.id, p.display_name, p.happy_id, p.avatar_key, p.cover_key, p.bio, p.country_name, p.gender, p.birthday, p.is_private, p.created_at " +
          "FROM users u INNER JOIN profiles p ON p.user_id = u.id WHERE u.id = ? AND u.status = 'active' LIMIT 1"
        ).bind(targetId).first<{
          id: string; display_name: string; happy_id: string | null; avatar_key: string | null;
          cover_key: string | null; bio: string; country_name: string | null; gender: string | null;
          birthday: string | null; is_private: number; created_at: string;
        }>();
        if (!profile) return json({ error: "user_not_found" }, 404, origin, env);
        const isMine = viewer.id === targetId;
        const follow = isMine ? null : await env.DB!.prepare(
          "SELECT 1 AS found FROM user_follows WHERE follower_id = ? AND following_id = ? LIMIT 1"
        ).bind(viewer.id, targetId).first<{ found: number }>();
        const isFollowing = Boolean(follow);
        const canViewPosts = !profile.is_private || isMine || isFollowing;
        const stats = await env.DB!.prepare(
          "SELECT " +
          "(SELECT COUNT(*) FROM user_follows WHERE following_id = ?) AS followers, " +
          "(SELECT COUNT(*) FROM user_follows WHERE follower_id = ?) AS following, " +
          "(SELECT COUNT(*) FROM posts WHERE user_id = ? AND status = 'published') AS posts, " +
          "(SELECT COUNT(*) FROM post_likes l INNER JOIN posts p ON p.id = l.post_id WHERE p.user_id = ? AND p.status = 'published') AS likes_received, " +
          "(SELECT COUNT(*) FROM rooms WHERE owner_user_id = ? AND status = 'active') AS active_rooms"
        ).bind(targetId, targetId, targetId, targetId, targetId).first<{
          followers: number; following: number; posts: number; likes_received: number; active_rooms: number;
        }>();
        const posts = canViewPosts ? await env.DB!.prepare(
          "SELECT id, content, image_url, created_at, " +
          "(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = posts.id) AS likes_count, " +
          "(SELECT COUNT(*) FROM post_comments c WHERE c.post_id = posts.id) AS comments_count, " +
          "EXISTS(SELECT 1 FROM post_likes l WHERE l.post_id = posts.id AND l.user_id = ?) AS liked " +
          "FROM posts WHERE user_id = ? AND status = 'published' " +
          "AND (visibility = 'public' OR (visibility = 'followers' AND ? = 1) OR (visibility = 'private' AND ? = 1)) " +
          "ORDER BY created_at DESC LIMIT 50"
        ).bind(viewer.id, targetId, isFollowing ? 1 : 0, isMine ? 1 : 0).all<{
          id: string; content: string; image_url: string | null; created_at: string;
          likes_count: number; comments_count: number; liked: number;
        }>() : { results: [] as Array<{id:string;content:string;image_url:string|null;created_at:string;likes_count:number;comments_count:number;liked:number}> };
        const age = profile.birthday ? calculateAge(profile.birthday) : null;
        return json({ ok: true, profile: {
          userId: profile.id, name: profile.display_name, userCode: profile.happy_id ?? "",
          avatarUrl: profile.avatar_key, coverUrl: profile.cover_key, bio: profile.bio ?? "",
          country: profile.country_name ?? "", gender: profile.gender ?? "",
          age, joinedAt: profile.created_at, isPrivate: Boolean(profile.is_private),
          isFollowing, isMine, canViewPosts,
          stats: {
            followers: stats?.followers ?? 0, following: stats?.following ?? 0,
            posts: stats?.posts ?? 0, likesReceived: stats?.likes_received ?? 0,
            activeRooms: stats?.active_rooms ?? 0
          },
          posts: (posts.results ?? []).map(p => ({
            id: p.id, userId: profile.id, content: p.content, imageUrl: p.image_url,
            createdAt: p.created_at, likesCount: p.likes_count, commentsCount: p.comments_count,
            liked: Boolean(p.liked)
          }))
        } }, 200, origin, env);
      } catch (error) {
        console.error("[users.public-profile] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "public_profile_unavailable" }, 500, origin, env);
      }
    }

    const followRoute = url.pathname.match(/^\/api\/v1\/users\/([0-9a-f-]{36})\/follow$/i);
    if (followRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        if (followRoute[1] === user.id) return json({ error: "cannot_follow_self" }, 400, origin, env);
        const target = await env.DB!.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(followRoute[1]).first();
        if (!target) return json({ error: "user_not_found" }, 404, origin, env);
        const existing = await env.DB!.prepare("SELECT 1 AS found FROM user_follows WHERE follower_id = ? AND following_id = ?").bind(user.id, followRoute[1]).first();
        if (existing) await env.DB!.prepare("DELETE FROM user_follows WHERE follower_id = ? AND following_id = ?").bind(user.id, followRoute[1]).run();
        else await env.DB!.prepare("INSERT INTO user_follows (follower_id, following_id, created_at) VALUES (?, ?, ?)").bind(user.id, followRoute[1], new Date().toISOString()).run();
        return json({ ok: true, following: !existing }, 200, origin, env);
      } catch (error) {
        console.error("[users.follow] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "follow_failed" }, 500, origin, env);
      }
    }


    if (url.pathname === "/api/v1/reports/rooms" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const body = await request.json() as Record<string, unknown>;
        const roomCode = typeof body.roomCode === "string" ? body.roomCode.trim().slice(0, 64) : "";
        const roomName = typeof body.roomName === "string" ? body.roomName.trim().slice(0, 120) : "";
        const targets = Array.isArray(body.targets) ? body.targets.filter((value): value is string => typeof value === "string").slice(0, 3) : [];
        const violation = typeof body.violation === "string" ? body.violation.trim().slice(0, 120) : "";
        const allowedTargets = new Set(["اسم الغرفة", "غلاف الغرفة", "إعلان الغرفة"]);
        const allowedViolations = new Set(["اهانة", "مضايقة", "إباحية", "إعلانات / توجيه", "احتيال", "هكر", "الخصوصية والأمان", "عنف / مشاهد دموية / إرهاب", "انتهاكات سياسية / دينية", "انتحال الهوية", "اخرى"]);
        if (!roomCode || !roomName || targets.length === 0 || targets.some((value) => !allowedTargets.has(value)) || !allowedViolations.has(violation)) {
          return json({ error: "invalid_room_report", message: "بيانات البلاغ غير مكتملة" }, 400, origin, env);
        }
        const room = await env.DB!.prepare("SELECT room_code, name FROM rooms WHERE room_code = ? OR id = ? LIMIT 1")
          .bind(roomCode, roomCode).first<{ room_code: string; name: string }>();
        if (!room) return json({ error: "room_not_found", message: "الغرفة غير موجودة" }, 404, origin, env);
        const id = crypto.randomUUID();
        const createdAt = new Date().toISOString();
        await env.DB!.prepare("INSERT INTO room_profile_reports (id, room_code, room_name, reporter_id, targets_json, violation, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)")
          .bind(id, room.room_code, room.name, user.id, JSON.stringify([...new Set(targets)]), violation, createdAt).run();
        return json({ ok: true, reportId: id, message: "تم إرسال البلاغ إلى إدارة Happy Live للمراجعة" }, 201, origin, env);
      } catch (error) {
        console.error("[room-reports.create] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "room_report_creation_failed", message: "تعذر إرسال البلاغ الآن" }, 500, origin, env);
      }
    }

    // Return the signed-in user's permanent room, if one has already been created.
    if (url.pathname === "/api/v1/rooms/mine" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const room = await env.DB!.prepare(
          "SELECT id, room_code, owner_user_id, name, description, image_url, visibility, status, created_at FROM rooms WHERE owner_user_id = ? ORDER BY created_at ASC LIMIT 1"
        ).bind(user.id).first<{
          id: string; room_code: string; owner_user_id: string; name: string;
          description: string; image_url: string | null; visibility: string;
          status: string; created_at: string;
        }>();
        if (!room) return json({ ok: true, room: null }, 200, origin, env);
        return json({ ok: true, room: {
          id: room.id, roomCode: room.room_code, ownerId: room.owner_user_id,
          name: room.name, description: room.description, imageUrl: room.image_url,
          isPrivate: room.visibility === "private", status: room.status, createdAt: room.created_at
        } }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.mine] failed", diagnostic);
        return json({ error: "my_room_lookup_failed" }, 500, origin, env);
      }
    }

    // New rooms use a seven-digit public room code; accept eight-digit legacy codes too.
    const roomCodeRoute = url.pathname.match(/^\/api\/v1\/rooms\/by-code\/(\d{7,8})$/);
    if (roomCodeRoute && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const room = await env.DB!.prepare(
          "SELECT r.id, r.room_code, r.owner_user_id, r.name, r.description, r.image_url, r.visibility, r.status, r.created_at, p.display_name AS owner_name FROM rooms r LEFT JOIN profiles p ON p.user_id = r.owner_user_id WHERE r.room_code = ? AND r.status = 'active' LIMIT 1"
        ).bind(roomCodeRoute[1]).first<{
          id: string; room_code: string; owner_user_id: string; name: string;
          description: string; image_url: string | null; visibility: string;
          status: string; created_at: string; owner_name: string | null;
        }>();
        if (!room) return json({ error: "room_not_found", message: "لم يتم العثور على غرفة نشطة بهذا ID" }, 404, origin, env);
        return json({ ok: true, room: {
          id: room.id, roomCode: room.room_code, ownerId: room.owner_user_id,
          ownerName: room.owner_name?.trim() || "صاحب الغرفة",
          name: room.name, description: room.description, imageUrl: room.image_url,
          isPrivate: room.visibility === "private", status: room.status,
          createdAt: room.created_at
        } }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error ? { name: error.name, message: error.message } : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.by-code] failed", diagnostic);
        return json({ error: "room_lookup_failed" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/rooms" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const result = await env.DB!.prepare(
          "SELECT id, room_code, owner_user_id, name, description, image_url, visibility, created_at FROM rooms WHERE status = 'active' AND visibility = 'public' ORDER BY created_at DESC LIMIT 100"
        ).all<{
          id: string;
          room_code: string;
          owner_user_id: string;
          name: string;
          description: string;
          image_url: string | null;
          visibility: string;
          created_at: string;
        }>();
        const rooms = (result.results ?? []).map((room) => ({
          id: room.id,
          roomCode: room.room_code,
          ownerId: room.owner_user_id,
          name: room.name,
          description: room.description,
          imageUrl: room.image_url,
          isPrivate: room.visibility === "private",
          createdAt: room.created_at
        }));
        return json({ ok: true, rooms }, 200, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error
          ? { name: error.name, message: error.message }
          : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.list] failed", diagnostic);
        return json({ error: "room_list_failed" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/rooms" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);

        // A user owns one permanent room. Leaving it never deletes it, and
        // pressing create again returns the original room instead of duplicating it.
        const existingRoom = await env.DB!.prepare(
          "SELECT id, room_code, owner_user_id, name, description, image_url, visibility, status, created_at FROM rooms WHERE owner_user_id = ? ORDER BY created_at ASC LIMIT 1"
        ).bind(user.id).first<{
          id: string; room_code: string; owner_user_id: string; name: string;
          description: string; image_url: string | null; visibility: string;
          status: string; created_at: string;
        }>();
        if (existingRoom) {
          return json({ ok: true, existing: true, room: {
            id: existingRoom.id, roomCode: existingRoom.room_code,
            ownerId: existingRoom.owner_user_id, name: existingRoom.name,
            description: existingRoom.description, imageUrl: existingRoom.image_url,
            isPrivate: existingRoom.visibility === "private", status: existingRoom.status,
            createdAt: existingRoom.created_at
          } }, 200, origin, env);
        }

        let body: Record<string, unknown>;
        try {
          body = await request.json() as Record<string, unknown>;
        } catch {
          return json({ error: "invalid_json" }, 400, origin, env);
        }

        const name = typeof body.name === "string" ? body.name.trim() : "";
        const description = typeof body.description === "string" ? body.description.trim() : "";
        const isPrivate = body.isPrivate === true;
        const requestedImageUrl = typeof body.imageUrl === "string" ? body.imageUrl.trim() : "";
        // If the creator skips choosing a room image, copy the current profile
        // avatar once as the initial room cover. The stored room image remains
        // independent and can later be replaced from Room Settings > Cover.
        const ownerProfile = await env.DB!.prepare(
          "SELECT avatar_key FROM profiles WHERE user_id = ? LIMIT 1"
        ).bind(user.id).first<{ avatar_key: string | null }>();
        const imageUrl = requestedImageUrl || (ownerProfile?.avatar_key ?? "").trim();
        if (imageUrl) {
          try {
            const parsedImageUrl = new URL(imageUrl);
            if (parsedImageUrl.protocol !== "https:" || !parsedImageUrl.hostname.endsWith("imagekit.io")) {
              return json({ error: "invalid_room_image" }, 400, origin, env);
            }
          } catch {
            return json({ error: "invalid_room_image" }, 400, origin, env);
          }
        }

        if (!name) return json({ error: "room_name_required", message: "اكتب اسم الغرفة" }, 400, origin, env);
        if (name.length > 20) return json({ error: "invalid_room_name", message: "اسم الغرفة يجب ألا يتجاوز 20 حرفًا" }, 400, origin, env);
        if (description.length > 120) return json({ error: "invalid_description", message: "الوصف يجب ألا يتجاوز 120 حرفًا" }, 400, origin, env);

        const roomId = crypto.randomUUID();
        const createdAt = new Date().toISOString();
        let roomCode = "";
        let roomCreated = false;
        for (let attempt = 0; attempt < 12; attempt++) {
          const random = new Uint32Array(1);
          crypto.getRandomValues(random);
          roomCode = String(1000000 + (random[0] % 9000000));
          const inserted = await env.DB!.prepare(
            "INSERT INTO rooms (id, room_code, owner_user_id, name, description, image_url, visibility, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?) ON CONFLICT DO NOTHING"
          ).bind(roomId, roomCode, user.id, name, description, imageUrl || null, isPrivate ? "private" : "public", createdAt, createdAt).run();
          if ((inserted.meta?.changes ?? 0) === 1) {
            roomCreated = true;
            break;
          }

          // A concurrent request may have created this user's room after the
          // initial lookup. The unique owner index rejects the second insert;
          // return the winner's room instead of reporting a room-code failure.
          const concurrentRoom = await env.DB!.prepare(
            "SELECT id, room_code, owner_user_id, name, description, image_url, visibility, status, created_at FROM rooms WHERE owner_user_id = ? ORDER BY created_at ASC, id ASC LIMIT 1"
          ).bind(user.id).first<{
            id: string; room_code: string; owner_user_id: string; name: string;
            description: string; image_url: string | null; visibility: string;
            status: string; created_at: string;
          }>();
          if (concurrentRoom) {
            return json({ ok: true, existing: true, room: {
              id: concurrentRoom.id, roomCode: concurrentRoom.room_code,
              ownerId: concurrentRoom.owner_user_id, name: concurrentRoom.name,
              description: concurrentRoom.description, imageUrl: concurrentRoom.image_url,
              isPrivate: concurrentRoom.visibility === "private", status: concurrentRoom.status,
              createdAt: concurrentRoom.created_at
            } }, 200, origin, env);
          }
        }
        if (!roomCreated) {
          return json({ error: "room_code_generation_failed", message: "تعذر توليد رقم الغرفة، حاول مرة أخرى" }, 503, origin, env);
        }

        return json({
          ok: true,
          room: {
            id: roomId,
            roomCode,
            ownerId: user.id,
            name,
            description,
            imageUrl: imageUrl || null,
            isPrivate,
            status: "active",
            createdAt
          }
        }, 201, origin, env);
      } catch (error) {
        const diagnostic = error instanceof Error
          ? { name: error.name, message: error.message }
          : { name: "UnknownError", message: "Non-Error exception" };
        console.error("[rooms.create] failed", diagnostic);
        return json({ error: "room_creation_failed", message: "تعذر إنشاء الغرفة حاليًا" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/auth/logout" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const authorization = request.headers.get("Authorization") ?? "";
      const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
      if (match) {
        await env.DB!.prepare("UPDATE user_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
          .bind(new Date().toISOString(), await sha256(match[1])).run();
      }
      return json({ ok: true }, 200, origin, env);
    }

    if (url.pathname === "/api/v1/health" && request.method === "GET") {
      let database = "not_configured";

      if (env.DB) {
        try {
          await env.DB!.prepare("SELECT 1 AS ok").first();
          database = "connected";
        } catch {
          database = "unavailable";
        }
      }

      const healthy = database === "connected";
      return json({
        ok: healthy,
        service: "happy-live-api",
        environment: env.APP_ENV ?? "unknown",
        database
      }, healthy ? 200 : 503, origin, env);
    }

    if (url.pathname === "/api/v1/imagekit/auth" && request.method === "GET") {
      if (!env.DB || !env.IMAGEKIT_PUBLIC_KEY?.trim() || !env.IMAGEKIT_PRIVATE_KEY?.trim()) {
        return json({ error: "imagekit_not_configured" }, 503, origin, env);
      }

      // Permit the application owner and signed-in users to upload their own media.
      // Admin sessions are separately scoped; only the owner may use this upload path.
      const adminActor = await authenticatedAdmin(request, env.DB);
      const isOwnerAdmin = adminActor?.role === "owner";
      const authorization = request.headers.get("Authorization") ?? "";
      const bearerMatch = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
      if (!isOwnerAdmin) {
        if (!bearerMatch) return json({ error: "authentication_required" }, 401, origin, env);
        try {
          const tokenHashBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(bearerMatch[1]));
          const tokenHash = Array.from(new Uint8Array(tokenHashBytes)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
          const session = await env.DB!.prepare(
            "SELECT s.user_id FROM user_sessions s INNER JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active' LIMIT 1"
          ).bind(tokenHash, new Date().toISOString()).first<{ user_id: string }>();
          if (!session) return json({ error: "invalid_or_expired_session" }, 401, origin, env);
        } catch {
          return json({ error: "authentication_required" }, 401, origin, env);
        }
      }

      try {
        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const now = Math.floor(Date.now() / 1000);
        const windowStart = now - 60;
        const rate = await env.DB!.prepare(
          "INSERT INTO imagekit_auth_rate_limits (ip, window_start, request_count) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET window_start = CASE WHEN imagekit_auth_rate_limits.window_start <= ? THEN excluded.window_start ELSE imagekit_auth_rate_limits.window_start END, request_count = CASE WHEN imagekit_auth_rate_limits.window_start <= ? THEN 1 ELSE imagekit_auth_rate_limits.request_count + 1 END RETURNING request_count"
        ).bind(ip, now, windowStart, windowStart).first<{ request_count: number }>();

        if (!rate || rate.request_count > 8) {
          return json({ error: "rate_limit_exceeded", retry_after_seconds: 60 }, 429, origin, env);
        }

        const token = crypto.randomUUID();
        const expire = now + 300;
        const key = await crypto.subtle.importKey(
          "raw",
          new TextEncoder().encode(env.IMAGEKIT_PRIVATE_KEY),
          { name: "HMAC", hash: "SHA-1" },
          false,
          ["sign"]
        );
        const signatureBytes = await crypto.subtle.sign(
          "HMAC",
          key,
          new TextEncoder().encode(token + expire)
        );
        const signature = Array.from(new Uint8Array(signatureBytes))
          .map((byte) => byte.toString(16).padStart(2, "0"))
          .join("");

        return json({
          token,
          expire,
          signature,
          publicKey: env.IMAGEKIT_PUBLIC_KEY
        }, 200, origin, env);
      } catch {
        return json({ error: "imagekit_auth_unavailable" }, 503, origin, env);
      }
    }

    if (url.pathname === "/api/v1/imagekit/health" && request.method === "GET") {
      const publicKeyConfigured = Boolean(env.IMAGEKIT_PUBLIC_KEY?.trim());
      const privateKey = env.IMAGEKIT_PRIVATE_KEY?.trim() ?? "";
      let signing = "not_configured";

      if (privateKey) {
        try {
          const key = await crypto.subtle.importKey(
            "raw",
            new TextEncoder().encode(privateKey),
            { name: "HMAC", hash: "SHA-1" },
            false,
            ["sign"]
          );
          await crypto.subtle.sign(
            "HMAC",
            key,
            new TextEncoder().encode("happy-live-imagekit-configuration-check")
          );
          signing = "ready";
        } catch {
          signing = "error";
        }
      }

      const ok = publicKeyConfigured && signing === "ready";
      return json({
        ok,
        service: "imagekit",
        public_key: publicKeyConfigured ? "configured" : "missing",
        private_key: privateKey ? "configured" : "missing",
        signing
      }, ok ? 200 : 503, origin, env);
    }

    // Private messaging: authenticated direct conversations and member-only group chats.
    if (url.pathname === "/api/v1/messages/search" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const viewer = await authenticatedUser(request, env.DB);
        if (!viewer) return json({ error: "authentication_required" }, 401, origin, env);
        const q = (url.searchParams.get("q") ?? "").trim().slice(0, 80);
        if (q.length < 2) return json({ ok: true, users: [], groups: [] }, 200, origin, env);
        const pattern = "%" + q + "%";
        const [users, groups] = await Promise.all([
          env.DB!.prepare(
            "SELECT u.id AS userId, p.display_name AS name, p.happy_id AS userCode, p.avatar_key AS avatarUrl " +
            "FROM users u INNER JOIN profiles p ON p.user_id = u.id " +
            "WHERE u.status = 'active' AND u.id <> ? AND (p.display_name LIKE ? OR p.happy_id LIKE ?) " +
            "AND NOT EXISTS (SELECT 1 FROM user_hidden_users h WHERE (h.user_id = ? AND h.hidden_user_id = u.id) OR (h.user_id = u.id AND h.hidden_user_id = ?)) " +
            "ORDER BY CASE WHEN p.happy_id = ? THEN 0 ELSE 1 END, p.display_name LIMIT 30"
          ).bind(viewer.id, pattern, pattern, viewer.id, viewer.id, q).all(),
          env.DB!.prepare(
            "SELECT c.id AS conversationId, c.title, c.updated_at AS updatedAt, " +
            "(SELECT COUNT(*) FROM conversation_members m WHERE m.conversation_id = c.id) AS memberCount " +
            "FROM conversations c INNER JOIN conversation_members mine ON mine.conversation_id = c.id AND mine.user_id = ? " +
            "WHERE c.kind = 'group' AND c.title LIKE ? ORDER BY c.updated_at DESC LIMIT 20"
          ).bind(viewer.id, pattern).all()
        ]);
        return json({ ok: true, users: users.results ?? [], groups: groups.results ?? [] }, 200, origin, env);
      } catch (error) {
        console.error("[messages.search] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "message_search_failed" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/messages/conversations" && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const viewer = await authenticatedUser(request, env.DB);
        if (!viewer) return json({ error: "authentication_required" }, 401, origin, env);
        if (request.method === "GET") {
          const rows = await env.DB!.prepare(
            "SELECT c.id, c.kind, c.title, c.updated_at AS updatedAt, " +
            "last_message.content AS lastMessage, last_message.created_at AS lastMessageAt, " +
            "CASE WHEN c.kind = 'direct' THEN other.id ELSE NULL END AS otherUserId, " +
            "CASE WHEN c.kind = 'direct' THEN other_profile.display_name ELSE c.title END AS displayName, " +
            "CASE WHEN c.kind = 'direct' THEN other_profile.happy_id ELSE NULL END AS userCode, " +
            "CASE WHEN c.kind = 'direct' THEN other_profile.avatar_key ELSE NULL END AS avatarUrl, " +
            "(SELECT COUNT(*) FROM private_messages unread WHERE unread.conversation_id = c.id AND unread.sender_id <> ? AND unread.deleted_at IS NULL AND (mine.last_read_at IS NULL OR unread.created_at > mine.last_read_at)) AS unreadCount " +
            "FROM conversation_members mine INNER JOIN conversations c ON c.id = mine.conversation_id " +
            "LEFT JOIN conversation_members other_member ON other_member.conversation_id = c.id AND c.kind = 'direct' AND other_member.user_id <> ? " +
            "LEFT JOIN users other ON other.id = other_member.user_id AND c.kind = 'direct' " +
            "LEFT JOIN profiles other_profile ON other_profile.user_id = other.id " +
            "LEFT JOIN private_messages last_message ON last_message.id = (SELECT pm.id FROM private_messages pm WHERE pm.conversation_id = c.id AND pm.deleted_at IS NULL ORDER BY pm.created_at DESC LIMIT 1) " +
            "ORDER BY COALESCE(last_message.created_at, c.updated_at) DESC LIMIT 100"
          ).bind(viewer.id, viewer.id).all();
          return json({ ok: true, conversations: rows.results ?? [] }, 200, origin, env);
        }
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const now = new Date().toISOString();
        if (body.kind === "group") {
          const title = typeof body.title === "string" ? body.title.trim().slice(0, 80) : "";
          const ids = Array.isArray(body.memberIds) ? Array.from(new Set(body.memberIds.filter((x): x is string => typeof x === "string" && /^[0-9a-f-]{36}$/i.test(x) && x !== viewer.id))).slice(0, 99) : [];
          if (title.length < 2 || ids.length < 1) return json({ error: "invalid_group", message: "أدخل اسم المجموعة واختر عضواً واحداً على الأقل" }, 400, origin, env);
          const placeholders = ids.map(() => "?").join(",");
          const valid = await env.DB!.prepare("SELECT id FROM users WHERE status = 'active' AND id IN (" + placeholders + ")").bind(...ids).all<{id:string}>();
          if ((valid.results ?? []).length !== ids.length) return json({ error: "invalid_group_members" }, 400, origin, env);
          const conversationId = crypto.randomUUID();
          const statements: D1PreparedStatement[] = [
            env.DB!.prepare("INSERT INTO conversations (id, kind, title, created_by, direct_key, created_at, updated_at) VALUES (?, 'group', ?, ?, NULL, ?, ?)").bind(conversationId, title, viewer.id, now, now),
            env.DB!.prepare("INSERT INTO conversation_members (conversation_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)").bind(conversationId, viewer.id, now),
            ...ids.map(id => env.DB!.prepare("INSERT INTO conversation_members (conversation_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)").bind(conversationId, id, now))
          ];
          await env.DB!.batch(statements);
          return json({ ok: true, conversationId, kind: "group" }, 201, origin, env);
        }
        const recipientId = typeof body.recipientId === "string" ? body.recipientId : "";
        if (!/^[0-9a-f-]{36}$/i.test(recipientId) || recipientId === viewer.id) return json({ error: "invalid_recipient" }, 400, origin, env);
        const recipient = await env.DB!.prepare("SELECT id FROM users WHERE id = ? AND status = 'active' LIMIT 1").bind(recipientId).first();
        if (!recipient) return json({ error: "user_not_found" }, 404, origin, env);
        const hidden = await env.DB!.prepare("SELECT 1 AS blocked FROM user_hidden_users WHERE (user_id = ? AND hidden_user_id = ?) OR (user_id = ? AND hidden_user_id = ?) LIMIT 1").bind(viewer.id, recipientId, recipientId, viewer.id).first();
        if (hidden) return json({ error: "conversation_unavailable", message: "لا يمكن بدء محادثة مع هذا المستخدم" }, 403, origin, env);
        const directKey = [viewer.id, recipientId].sort().join(":");
        const existing = await env.DB!.prepare("SELECT id FROM conversations WHERE direct_key = ? LIMIT 1").bind(directKey).first<{id:string}>();
        const conversationId = existing?.id ?? crypto.randomUUID();
        if (!existing) {
          await env.DB!.batch([
            env.DB!.prepare("INSERT OR IGNORE INTO conversations (id, kind, title, created_by, direct_key, created_at, updated_at) VALUES (?, 'direct', NULL, ?, ?, ?, ?)").bind(conversationId, viewer.id, directKey, now, now),
            env.DB!.prepare("INSERT OR IGNORE INTO conversation_members (conversation_id, user_id, role, joined_at) SELECT id, ?, 'member', ? FROM conversations WHERE direct_key = ?").bind(viewer.id, now, directKey),
            env.DB!.prepare("INSERT OR IGNORE INTO conversation_members (conversation_id, user_id, role, joined_at) SELECT id, ?, 'member', ? FROM conversations WHERE direct_key = ?").bind(recipientId, now, directKey)
          ]);
        }
        const actual = await env.DB!.prepare("SELECT id FROM conversations WHERE direct_key = ? LIMIT 1").bind(directKey).first<{id:string}>();
        return json({ ok: true, conversationId: actual?.id ?? conversationId, kind: "direct" }, 200, origin, env);
      } catch (error) {
        console.error("[messages.conversations] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "conversations_unavailable" }, 500, origin, env);
      }
    }

    const privateConversationRoute = url.pathname.match(/^\/api\/v1\/messages\/conversations\/([0-9a-f-]{36})(?:\/(messages|read))?$/i);
    if (privateConversationRoute && (request.method === "GET" || request.method === "POST" || request.method === "PATCH")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const viewer = await authenticatedUser(request, env.DB);
        if (!viewer) return json({ error: "authentication_required" }, 401, origin, env);
        const conversationId = privateConversationRoute[1];
        const action = privateConversationRoute[2] ?? "";
        const member = await env.DB!.prepare("SELECT role, last_read_at FROM conversation_members WHERE conversation_id = ? AND user_id = ? LIMIT 1").bind(conversationId, viewer.id).first<{role:string;last_read_at:string|null}>();
        if (!member) return json({ error: "conversation_not_found" }, 404, origin, env);
        if (action === "read" && request.method === "PATCH") {
          const now = new Date().toISOString();
          await env.DB!.prepare("UPDATE conversation_members SET last_read_at = ? WHERE conversation_id = ? AND user_id = ?").bind(now, conversationId, viewer.id).run();
          return json({ ok: true, lastReadAt: now }, 200, origin, env);
        }
        if (action === "messages" && request.method === "GET") {
          const before = url.searchParams.get("before");
          const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 50), 1), 100);
          const rows = await env.DB!.prepare(
            "SELECT m.id, m.sender_id AS senderId, p.display_name AS senderName, p.avatar_key AS senderAvatar, m.content AS text, m.created_at AS createdAt " +
            "FROM private_messages m LEFT JOIN profiles p ON p.user_id = m.sender_id " +
            "WHERE m.conversation_id = ? AND m.deleted_at IS NULL AND (? IS NULL OR m.created_at < ?) " +
            "ORDER BY m.created_at DESC LIMIT ?"
          ).bind(conversationId, before, before, limit).all();
          const participants = await env.DB!.prepare(
            "SELECT u.id AS userId, p.display_name AS name, p.happy_id AS userCode, p.avatar_key AS avatarUrl, cm.role " +
            "FROM conversation_members cm INNER JOIN users u ON u.id = cm.user_id LEFT JOIN profiles p ON p.user_id = u.id " +
            "WHERE cm.conversation_id = ? ORDER BY cm.joined_at ASC"
          ).bind(conversationId).all();
          return json({ ok: true, currentUserId: viewer.id, messages: (rows.results ?? []).reverse(), participants: participants.results ?? [] }, 200, origin, env);
        }
        if (action === "messages" && request.method === "POST") {
          const body = await request.json() as Record<string, unknown>;
          const messageText = typeof body.text === "string" ? body.text.trim() : "";
          if (!messageText || messageText.length > 2000) return json({ error: "invalid_message", message: "الرسالة يجب أن تكون بين حرف واحد و2000 حرف" }, 400, origin, env);
          const recent = await env.DB!.prepare("SELECT COUNT(*) AS total FROM private_messages WHERE sender_id = ? AND created_at >= ? AND deleted_at IS NULL").bind(viewer.id, new Date(Date.now() - 60000).toISOString()).first<{total:number}>();
          if ((recent?.total ?? 0) >= 30) return json({ error: "message_rate_limited", message: "أرسلت رسائل كثيرة، انتظر قليلاً" }, 429, origin, env);
          const id = crypto.randomUUID();
          const now = new Date().toISOString();
          await env.DB!.batch([
            env.DB!.prepare("INSERT INTO private_messages (id, conversation_id, sender_id, content, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, conversationId, viewer.id, messageText, now),
            env.DB!.prepare("UPDATE conversations SET updated_at = ? WHERE id = ?").bind(now, conversationId),
            env.DB!.prepare("UPDATE conversation_members SET last_read_at = ? WHERE conversation_id = ? AND user_id = ?").bind(now, conversationId, viewer.id)
          ]);
          return json({ ok: true, message: { id, senderId: viewer.id, senderName: viewer.display_name?.trim() || "مستخدم", senderAvatar: null, text: messageText, createdAt: now } }, 201, origin, env);
        }
        return json({ error: "method_not_allowed" }, 405, origin, env);
      } catch (error) {
        console.error("[messages.conversation] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "conversation_unavailable" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1" && request.method === "GET") {
      return json({
        name: "Happy Live API",
        version: "v1",
        status: "scaffold",
        endpoints: ["/api/v1/health", "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/google", "/api/v1/auth/me", "/api/v1/auth/logout", "/api/v1/rooms", "/api/v1/messages/search", "/api/v1/messages/conversations", "/api/v1/messages/conversations/{id}/messages", "/api/v1/imagekit/health", "/api/v1/imagekit/auth"]
      }, 200, origin, env);
    }

    return json({ error: "not_found" }, 404, origin, env);
  }
};
export class RoomChatHub {
  private readonly sockets = new Set<WebSocket>();

  constructor(private readonly state: DurableObjectState, private readonly env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/broadcast" && request.method === "POST") {
      const payload = await request.text();
      for (const socket of this.sockets) {
        try { socket.send(payload); } catch { this.sockets.delete(socket); }
      }
      return new Response(null, { status: 204 });
    }

    if (url.pathname !== "/connect" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Not found", { status: 404 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();
    this.sockets.add(server);
    server.addEventListener("close", () => this.sockets.delete(server));
    server.addEventListener("error", () => this.sockets.delete(server));
    return new Response(null, {
      status: 101,
      headers: { "Sec-WebSocket-Protocol": "happy-live-chat" },
      webSocket: client
    });
  }
}
