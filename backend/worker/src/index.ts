import { RtcTokenBuilder } from "agora-token";
export interface Env {
  DB?: D1Database;
  ROOM_CHAT?: DurableObjectNamespace;
  APP_ENV?: string;
  ALLOWED_ORIGINS?: string;
  IMAGEKIT_PUBLIC_KEY?: string;
  IMAGEKIT_PRIVATE_KEY?: string;
  ADMIN_SETUP_TOKEN?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_ENABLED?: string;
}


const SESSION_TTL_DAYS = 30;
const PASSWORD_ITERATIONS = 100000;
const AUTH_RATE_WINDOW_SECONDS = 900;
const AUTH_RATE_MAX_ATTEMPTS = 8;

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
        "UPDATE profiles SET gabo_id = ? WHERE user_id = ? AND (gabo_id IS NULL OR gabo_id = '')"
      ).bind(candidate, userId).run();
      if ((result.meta?.changes ?? 0) > 0) return candidate;
      const existing = await db.prepare("SELECT gabo_id FROM profiles WHERE user_id = ? LIMIT 1")
        .bind(userId).first<{ gabo_id: string | null }>();
      if (existing?.gabo_id) return existing.gabo_id;
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
    "SELECT u.id, u.email, p.display_name, p.gabo_id FROM user_sessions s INNER JOIN users u ON u.id = s.user_id LEFT JOIN profiles p ON p.user_id = u.id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active' LIMIT 1"
  ).bind(await sha256(match[1]), new Date().toISOString()).first<{ id: string; email: string; display_name: string | null; gabo_id: string | null }>();
  if (!row) return null;
  row.gabo_id = await ensurePublicUserId(db, row.id, row.gabo_id);
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

async function checkAuthRateLimit(db: D1Database, ip: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const cutoff = now - AUTH_RATE_WINDOW_SECONDS;
  const row = await db.prepare(
    "INSERT INTO auth_rate_limits (ip, window_start, request_count) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET window_start = CASE WHEN auth_rate_limits.window_start <= ? THEN excluded.window_start ELSE auth_rate_limits.window_start END, request_count = CASE WHEN auth_rate_limits.window_start <= ? THEN 1 ELSE auth_rate_limits.request_count + 1 END RETURNING request_count"
  ).bind(ip, now, cutoff, cutoff).first<{ request_count: number }>();
  return Boolean(row && row.request_count <= AUTH_RATE_MAX_ATTEMPTS);
}


async function authenticatedAdmin(request: Request, db: D1Database) {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
  if (!match) return null;
  const row = await db.prepare(
    "SELECT a.id, a.username, a.display_name FROM admin_sessions s INNER JOIN admin_accounts a ON a.id = s.admin_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND a.status = 'active' LIMIT 1"
  ).bind(await sha256(match[1]), new Date().toISOString()).first<{ id: string; username: string; display_name: string }>();
  return row ? { id: row.id, username: row.username, display_name: row.display_name, role: "owner" as const } : null;
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

    if (origin && !isAllowedOrigin(origin, env)) {
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


    if (url.pathname === "/api/v1/admin/auth/setup-status" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      const state = await env.DB.prepare("SELECT id FROM admin_setup_state WHERE id = 'primary-owner' LIMIT 1").first();
      return json({ setupRequired: !state }, 200, origin, env);
    }

    if (url.pathname === "/api/v1/admin/auth/setup" && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      if (!env.ADMIN_SETUP_TOKEN) return json({ error: "admin_setup_not_configured" }, 503, origin, env);
      try {
        const state = await env.DB.prepare("SELECT id FROM admin_setup_state WHERE id = 'primary-owner' LIMIT 1").first();
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
        const owner = await env.DB.prepare("SELECT id FROM admin_accounts WHERE username = 'owner' COLLATE NOCASE AND status = 'active' LIMIT 1")
          .first<{ id: string }>();
        if (!owner) return json({ error: "primary_admin_not_found" }, 404, origin, env);
        const nonce = crypto.randomUUID();
        const now = new Date().toISOString();
        const passwordHash = await hashPassword(password);
        const results = await env.DB.batch([
          env.DB.prepare("INSERT OR IGNORE INTO admin_setup_state (id, setup_nonce, completed_at) VALUES ('primary-owner', ?, ?)")
            .bind(nonce, now),
          env.DB.prepare("UPDATE admin_accounts SET password_hash = ?, updated_at = ? WHERE id = ? AND EXISTS (SELECT 1 FROM admin_setup_state WHERE id = 'primary-owner' AND setup_nonce = ?)")
            .bind(passwordHash, now, owner.id, nonce),
          env.DB.prepare("UPDATE admin_sessions SET revoked_at = ? WHERE admin_id = ? AND revoked_at IS NULL")
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
        const account = await env.DB.prepare("SELECT id, password_hash FROM admin_accounts WHERE username = ? COLLATE NOCASE AND status = 'active' LIMIT 1")
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
      if (match) await env.DB.prepare("UPDATE admin_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
        .bind(new Date().toISOString(), await sha256(match[1])).run();
      return json({ ok: true }, 200, origin, env);
    }

    // Admin API: authentication uses a separate admin-only session table.
    if (
      url.pathname === "/api/v1/admin/me" ||
      url.pathname === "/api/v1/admin/overview" ||
      url.pathname === "/api/v1/admin/users" ||
      url.pathname === "/api/v1/admin/rooms" ||
      url.pathname === "/api/v1/admin/audit" ||
      url.pathname === "/api/v1/admin/agora/status" ||
      url.pathname === "/api/v1/admin/agora/voice" ||
      /^\/api\/v1\/admin\/users\/[0-9a-f-]{36}\/status$/i.test(url.pathname) ||
      /^\/api\/v1\/admin\/rooms\/[0-9a-f-]{36}\/status$/i.test(url.pathname)
    ) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedAdmin(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        const role = "owner" as const;
        const canManageUsers = role === "owner" || role === "admin";
        const canManageRooms = role === "owner" || role === "admin";

        if (url.pathname === "/api/v1/admin/agora/status" && request.method === "GET") {
          const voiceEnabled = await isAgoraVoiceEnabled(env.DB, env);
          return json({ ok: true, agora: {
            enabled: env.AGORA_ENABLED !== "false",
            voiceEnabled,
            appId: env.AGORA_APP_ID ?? "",
            certificateConfigured: Boolean(env.AGORA_APP_CERTIFICATE)
          } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/agora/voice" && request.method === "PATCH") {
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
            env.DB.prepare(
              "INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('agora_voice_enabled', ?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at"
            ).bind(body.enabled ? "true" : "false", now)
          ];
          if (!body.enabled) {
            statements.push(env.DB.prepare("DELETE FROM room_seats"));
          }
          statements.push(env.DB.prepare(
            "INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, ?, 'platform', 'agora_voice', ?, ?)"
          ).bind(
            crypto.randomUUID(),
            body.enabled ? "agora.voice.enable" : "agora.voice.disable",
            JSON.stringify({ enabled: body.enabled, adminUsername: actor.username, effect: body.enabled ? "voice_service_resumed" : "all_microphone_seats_released" }),
            now
          ));
          await env.DB.batch(statements);
          return json({ ok: true, voiceEnabled: body.enabled }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/me" && request.method === "GET") {
          return json({ ok: true, admin: { id: actor.id, name: actor.display_name, username: actor.username, role } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/overview" && request.method === "GET") {
          const [users, rooms, posts] = await Promise.all([
            env.DB.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active FROM users").first<{total:number;active:number}>(),
            env.DB.prepare("SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active FROM rooms").first<{total:number;active:number}>(),
            env.DB.prepare("SELECT COUNT(*) AS total FROM posts WHERE status = 'published'").first<{total:number}>()
          ]);
          return json({ ok: true, overview: {
            users: { total: users?.total ?? 0, active: users?.active ?? 0 },
            rooms: { total: rooms?.total ?? 0, active: rooms?.active ?? 0 },
            publishedPosts: posts?.total ?? 0
          } }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/users" && request.method === "GET") {
          const q = (url.searchParams.get("q") ?? "").trim().slice(0, 80);
          const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit") ?? 50) || 50));
          const result = await env.DB.prepare(
            "SELECT u.id, u.email, u.status, u.auth_provider, u.created_at, p.display_name, p.gabo_id, ar.role AS admin_role " +
            "FROM users u LEFT JOIN profiles p ON p.user_id = u.id LEFT JOIN admin_roles ar ON ar.user_id = u.id " +
            "WHERE (? = '' OR u.email LIKE '%' || ? || '%' OR p.display_name LIKE '%' || ? || '%' OR p.gabo_id LIKE '%' || ? || '%') " +
            "ORDER BY u.created_at DESC LIMIT ?"
          ).bind(q, q, q, q, limit).all();
          return json({ ok: true, users: result.results ?? [] }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/rooms" && request.method === "GET") {
          const result = await env.DB.prepare(
            "SELECT r.id, r.room_code, r.name, r.status, r.visibility, r.created_at, u.id AS owner_id, p.display_name AS owner_name " +
            "FROM rooms r INNER JOIN users u ON u.id = r.owner_user_id LEFT JOIN profiles p ON p.user_id = u.id " +
            "ORDER BY r.created_at DESC LIMIT 100"
          ).all();
          return json({ ok: true, rooms: result.results ?? [] }, 200, origin, env);
        }
        if (url.pathname === "/api/v1/admin/audit" && request.method === "GET") {
          
          const result = await env.DB.prepare(
            "SELECT l.id, l.action, l.target_type, l.target_id, l.details_json, l.created_at, p.display_name AS actor_name, u.email AS actor_email " +
            "FROM admin_audit_logs l LEFT JOIN users u ON u.id = l.actor_user_id LEFT JOIN profiles p ON p.user_id = l.actor_user_id " +
            "ORDER BY l.created_at DESC LIMIT 100"
          ).all();
          return json({ ok: true, entries: result.results ?? [] }, 200, origin, env);
        }
        const userStatusRoute = url.pathname.match(/^\/api\/v1\/admin\/users\/([0-9a-f-]{36})\/status$/i);
        if (userStatusRoute && request.method === "PATCH") {
          if (!canManageUsers) return json({ error: "permission_denied" }, 403, origin, env);
          const targetId = userStatusRoute[1];
          
          const body = await request.json() as Record<string, unknown>;
          const status = body.status === "active" || body.status === "suspended" ? body.status : null;
          if (!status) return json({ error: "invalid_status" }, 400, origin, env);
          const target = await env.DB.prepare("SELECT u.id, u.status, ar.role FROM users u LEFT JOIN admin_roles ar ON ar.user_id = u.id WHERE u.id = ? LIMIT 1")
            .bind(targetId).first<{id:string;status:string;role:string|null}>();
          if (!target) return json({ error: "user_not_found" }, 404, origin, env);
          if (target.status === "deleted") return json({ error: "deleted_user_cannot_be_reactivated" }, 409, origin, env);
          if (target.role && role !== "owner") return json({ error: "owner_permission_required" }, 403, origin, env);
          const now = new Date().toISOString();
          await env.DB.batch([
            env.DB.prepare("UPDATE users SET status = ?, updated_at = ? WHERE id = ?").bind(status, now, targetId),
            env.DB.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, 'user', ?, ?, ?)")
              .bind(crypto.randomUUID(), null, status === "suspended" ? "user.suspend" : "user.activate", targetId, JSON.stringify({ status, adminUsername: actor.username }), now)
          ]);
          return json({ ok: true, userId: targetId, status }, 200, origin, env);
        }
        const roomStatusRoute = url.pathname.match(/^\/api\/v1\/admin\/rooms\/([0-9a-f-]{36})\/status$/i);
        if (roomStatusRoute && request.method === "PATCH") {
          if (!canManageRooms) return json({ error: "permission_denied" }, 403, origin, env);
          const targetId = roomStatusRoute[1];
          const body = await request.json() as Record<string, unknown>;
          const status = body.status === "active" || body.status === "closed" ? body.status : null;
          if (!status) return json({ error: "invalid_status" }, 400, origin, env);
          const exists = await env.DB.prepare("SELECT id FROM rooms WHERE id = ? LIMIT 1").bind(targetId).first();
          if (!exists) return json({ error: "room_not_found" }, 404, origin, env);
          const now = new Date().toISOString();
          await env.DB.batch([
            env.DB.prepare("UPDATE rooms SET status = ?, updated_at = ? WHERE id = ?").bind(status, now, targetId),
            env.DB.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, 'room', ?, ?, ?)")
              .bind(crypto.randomUUID(), null, status === "closed" ? "room.close" : "room.reopen", targetId, JSON.stringify({ status, adminUsername: actor.username }), now)
          ]);
          return json({ ok: true, roomId: targetId, status }, 200, origin, env);
        }
        return json({ error: "admin_route_not_found" }, 404, origin, env);
      } catch (error) {
        console.error("[admin.api] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "admin_operation_failed" }, 500, origin, env);
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
          const existingId = await env.DB.prepare("SELECT 1 FROM profiles WHERE gabo_id = ? LIMIT 1").bind(candidate).first();
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
          await env.DB.batch([
            env.DB.prepare("INSERT INTO users (id, email, password_hash, auth_provider, status, terms_accepted_at) VALUES (?, ?, ?, 'email', 'active', ?)").bind(userId, email, passwordHash, now),
            env.DB.prepare("INSERT INTO profiles (user_id, display_name, birthday, gabo_id) VALUES (?, ?, ?, ?)").bind(userId, name, birthday, publicId),
            env.DB.prepare("INSERT INTO user_sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)").bind(crypto.randomUUID(), userId, tokenHash, expiresAt)
          ]);
        } catch (error) {
          const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ? LIMIT 1").bind(email).first();
          if (existing) return json({ error: "email_already_registered", message: "هذا البريد مسجل بالفعل، سجّل الدخول بدلًا من ذلك" }, 409, origin, env);
          throw error;
        }
        return json({ ok: true, accessToken: sessionToken, expiresAt, user: { id: userId, gabo_id: publicId, email, name } }, 201, origin, env);
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
        const user = await env.DB.prepare(
          "SELECT u.id, u.email, u.password_hash, u.status, p.display_name, p.gabo_id FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.email = ? AND u.auth_provider = 'email' LIMIT 1"
        ).bind(email).first<{ id: string; email: string; password_hash: string | null; status: string; display_name: string | null; gabo_id: string | null }>();
        if (!user || user.status !== "active" || !user.password_hash || !await verifyPassword(password, user.password_hash)) {
          return json({ error: "invalid_credentials", message: "البريد أو كلمة المرور غير صحيحة" }, 401, origin, env);
        }
        user.gabo_id = await ensurePublicUserId(env.DB, user.id, user.gabo_id);
        const session = await createSession(env.DB, user.id);
        return json({ ok: true, ...session, user: { id: user.id, gabo_id: user.gabo_id ?? "", email: user.email, name: user.display_name ?? "" } }, 200, origin, env);
      } catch {
        return json({ error: "login_failed", message: "تعذر تسجيل الدخول حاليًا" }, 500, origin, env);
      }
    }

    if (url.pathname === "/api/v1/auth/me" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const profile = await env.DB.prepare("SELECT display_name, bio, avatar_key, birthday, gender, country_name FROM profiles WHERE user_id = ? LIMIT 1")
          .bind(user.id).first<{ display_name: string; bio: string; avatar_key: string | null; birthday: string | null; gender: string | null; country_name: string | null }>();
        return json({ ok: true, user: {
          id: user.id, gabo_id: user.gabo_id ?? "", email: user.email,
          name: profile?.display_name ?? user.display_name ?? "", bio: profile?.bio ?? "",
          avatar_url: profile?.avatar_key ?? null, birthday: profile?.birthday ?? "2000-01-01",
          gender: profile?.gender ?? "male", country_name: profile?.country_name ?? "Saudi Arabia"
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
        const countryName = typeof body.countryName === "string" ? body.countryName.trim() : "Saudi Arabia";
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
        await env.DB.prepare("UPDATE profiles SET display_name = ?, bio = ?, avatar_key = ?, birthday = ?, gender = ?, country_name = ?, updated_at = ? WHERE user_id = ?")
          .bind(name, bio, avatarUrl, birthday, gender, countryName, new Date().toISOString(), user.id).run();
        return json({ ok: true, user: { id: user.id, gabo_id: user.gabo_id ?? "", email: user.email, name, bio, avatar_url: avatarUrl, birthday, gender, country_name: countryName } }, 200, origin, env);
      } catch (error) {
        console.error("[profile.update] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "profile_update_failed", message: "تعذر حفظ الملف الشخصي حاليًا" }, 500, origin, env);
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
        const room = await env.DB.prepare("SELECT id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const visit = await env.DB.prepare(
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
        const room = await env.DB.prepare(
          "SELECT id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const activeBan = await env.DB.prepare(
          "SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, user.id).first<{ user_id: string }>();
        const activeKick = await env.DB.prepare(
          "SELECT kicked_until FROM room_kicks WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1"
        ).bind(roomId, user.id, new Date().toISOString()).first<{ kicked_until: string }>();
        if (activeKick) return json({ error: "room_kicked", message: "تم طردك مؤقتاً من الغرفة" }, 403, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const action = body.action === "leave" ? "leave" : body.action === "join" ? "join" : "";
        if (!action) return json({ error: "invalid_chat_session_action" }, 400, origin, env);
        const now = new Date().toISOString();
        if (action === "join") {
          // A new visit starts with a clean view of chat history. Any abandoned
          // visit (for example after a closed browser tab) is ended first.
          await env.DB.prepare(
            "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
          ).bind(now, roomId, user.id).run();
          const visitId = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO room_chat_visits (id, room_id, user_id, entered_at, last_seen_at) VALUES (?, ?, ?, ?, ?)"
          ).bind(visitId, roomId, user.id, now, now).run();
          await broadcastRoomChat(env, roomId, {
            type: "system",
            message: {
              id: crypto.randomUUID(), userId: user.id,
              name: user.display_name?.trim() || "مستخدم",
              message: "انضم للغرفة", imageUrl: null, createdAt: now, isMe: false
            }
          });
          return json({ ok: true, enteredAt: now }, 200, origin, env);
        }
        await env.DB.prepare(
          "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
        ).bind(now, roomId, user.id).run();
        await broadcastRoomChat(env, roomId, {
          type: "system",
          message: {
            id: crypto.randomUUID(), userId: user.id,
            name: user.display_name?.trim() || "مستخدم",
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
    if (chatRoute && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(chatRoute[1]);
        const room = await env.DB.prepare(
          "SELECT id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const visit = await env.DB.prepare(
          "SELECT entered_at FROM room_chat_visits WHERE room_id = ? AND user_id = ? AND exited_at IS NULL ORDER BY entered_at DESC LIMIT 1"
        ).bind(roomId, user.id).first<{ entered_at: string }>();
        if (!visit) return json({ error: "chat_session_not_active" }, 409, origin, env);

        if (request.method === "POST") {
          const activeBan = await env.DB.prepare(
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
          const rate = await env.DB.prepare(
            "INSERT INTO room_chat_rate_limits (room_id, user_id, last_sent_at) VALUES (?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET last_sent_at = excluded.last_sent_at WHERE room_chat_rate_limits.last_sent_at <= ? RETURNING last_sent_at"
          ).bind(roomId, user.id, now, cutoff).first<{ last_sent_at: string }>();
          if (!rate) return json({ error: "chat_rate_limited", message: "انتظر ثانية قبل إرسال رسالة أخرى" }, 429, origin, env);
          const id = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO room_messages (id, room_id, user_id, message, image_url, created_at) VALUES (?, ?, ?, ?, ?, ?)"
          ).bind(id, roomId, user.id, message, imageUrl || null, now).run();
          const createdMessage = {
            id, userId: user.id, name: user.display_name?.trim() || "مستخدم",
            message, imageUrl: imageUrl || null, createdAt: now, isMe: false
          };
          await broadcastRoomChat(env, roomId, { type: "message", message: createdMessage });
        }

        const result = await env.DB.prepare(
          "SELECT m.id, m.user_id, m.message, m.image_url, m.created_at, p.display_name FROM room_messages m LEFT JOIN profiles p ON p.user_id = m.user_id WHERE m.room_id = ? AND m.created_at >= ? ORDER BY m.created_at DESC LIMIT 60"
        ).bind(roomId, visit.entered_at).all<{
          id: string; user_id: string; message: string; image_url: string | null;
          created_at: string; display_name: string | null;
        }>();
        const messages = (result.results ?? []).reverse().map((item) => ({
          id: item.id,
          userId: item.user_id,
          name: item.display_name?.trim() || "مستخدم",
          senderId: item.user_id,
          senderName: item.display_name?.trim() || "مستخدم",
          senderAvatar: "",
          text: item.message,
          message: item.message,
          imageUrl: item.image_url,
          createdAt: item.created_at,
          isMe: item.user_id === user.id
        }));
        return json({ ok: true, messages, enteredAt: visit.entered_at }, 200, origin, env);
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
        const room = await env.DB.prepare(
          "SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        if (room.owner_user_id !== user.id) return json({ error: "room_owner_only", message: "تعديل الإعلان متاح لمالك الغرفة فقط" }, 403, origin, env);
        const updatedAt = new Date().toISOString();
        await env.DB.prepare(
          "INSERT INTO room_announcements (room_id, announcement, updated_at) VALUES (?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET announcement = excluded.announcement, updated_at = excluded.updated_at"
        ).bind(roomId, announcement, updatedAt).run();
        const now = new Date().toISOString();
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

    // Room moderation: room owners and explicitly assigned room moderators only.
    const moderationRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/moderation$/);
    if (moderationRoute && request.method === "POST") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const actor = await authenticatedUser(request, env.DB);
        if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(moderationRoute[1]);
        const room = await env.DB.prepare(
          "SELECT id, owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; }
        catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const action = String(body.action ?? "");
        const targetUserId = String(body.targetUserId ?? actor.id);
        const isOwner = room.owner_user_id === actor.id;
        const moderator = await env.DB.prepare(
          "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, actor.id).first<{ user_id: string }>();
        const canModerate = isOwner || !!moderator;
        if (action === "self_mic_toggle") {
          const current = await env.DB.prepare(
            "SELECT is_muted, muted_by FROM room_user_controls WHERE room_id = ? AND user_id = ?"
          ).bind(roomId, actor.id).first<{ is_muted: number; muted_by: string | null }>();
          if (current?.is_muted === 1 && current.muted_by && current.muted_by !== actor.id) {
            return json({ error: "moderator_muted", message: "تم كتم مايكك بواسطة إدارة الغرفة" }, 403, origin, env);
          }
          const nextMuted = current?.is_muted === 1 ? 0 : 1;
          await env.DB.prepare(
            "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, NULL, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = NULL, updated_at = excluded.updated_at"
          ).bind(roomId, actor.id, nextMuted, new Date().toISOString()).run();
          return json({ ok: true, isMuted: nextMuted === 1 }, 200, origin, env);
        }
        if (!canModerate) return json({ error: "room_moderator_required", message: "هذه الصلاحية لمالك الغرفة ومشرفيها فقط" }, 403, origin, env);
        if (action === "assign_moderator" || action === "remove_moderator") {
          if (!isOwner) return json({ error: "room_owner_required" }, 403, origin, env);
          if (!targetUserId || targetUserId === actor.id) return json({ error: "invalid_moderator" }, 400, origin, env);
          if (action === "assign_moderator") {
            await env.DB.prepare("INSERT OR IGNORE INTO room_moderators (room_id, user_id, assigned_by, created_at) VALUES (?, ?, ?, ?)")
              .bind(roomId, targetUserId, actor.id, new Date().toISOString()).run();
          } else {
            await env.DB.prepare("DELETE FROM room_moderators WHERE room_id = ? AND user_id = ?")
              .bind(roomId, targetUserId).run();
          }
          return json({ ok: true }, 200, origin, env);
        }
        if (!["toggle_mute", "kick", "ban", "lower"].includes(action) || !targetUserId || targetUserId === room.owner_user_id) {
          return json({ error: "invalid_moderation_action" }, 400, origin, env);
        }
        const targetModerator = await env.DB.prepare(
          "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, targetUserId).first<{ user_id: string }>();
        if (targetModerator) return json({ error: "cannot_moderate_room_moderator", message: "لا يمكن تنفيذ الإجراء على مشرف الغرفة" }, 403, origin, env);
        const now = new Date().toISOString();
        if (action === "toggle_mute") {
          const current = await env.DB.prepare(
            "SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ?"
          ).bind(roomId, targetUserId).first<{ is_muted: number }>();
          const nextMuted = current?.is_muted === 1 ? 0 : 1;
          await env.DB.prepare(
            "INSERT INTO room_user_controls (room_id, user_id, is_muted, muted_by, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET is_muted = excluded.is_muted, muted_by = CASE WHEN excluded.is_muted = 1 THEN excluded.muted_by ELSE NULL END, updated_at = excluded.updated_at"
          ).bind(roomId, targetUserId, nextMuted, nextMuted === 1 ? actor.id : null, now).run();
          return json({ ok: true, isMuted: nextMuted === 1 }, 200, origin, env);
        }
        if (action === "kick" || action === "ban" || action === "lower") {
          await env.DB.prepare("DELETE FROM room_seats WHERE room_id = ? AND user_id = ?").bind(roomId, targetUserId).run();
          if (action === "kick") {
            const kickedUntil = new Date(Date.now() + 60000).toISOString();
            await env.DB.prepare(
              "INSERT INTO room_kicks (room_id, user_id, kicked_by, kicked_until, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET kicked_by = excluded.kicked_by, kicked_until = excluded.kicked_until, created_at = excluded.created_at"
            ).bind(roomId, targetUserId, actor.id, kickedUntil, now).run();
          }
          if (action === "kick") {
            await env.DB.prepare(
              "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
            ).bind(now, roomId, targetUserId).run();
          }
          if (action === "ban") {
            await env.DB.prepare(
              "INSERT INTO room_bans (room_id, user_id, banned_by, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET banned_by = excluded.banned_by, created_at = excluded.created_at"
            ).bind(roomId, targetUserId, actor.id, now).run();
          }
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
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      if (!env.AGORA_APP_ID || !env.AGORA_APP_CERTIFICATE || !(await isAgoraVoiceEnabled(env.DB, env))) {
        return json({ error: "agora_voice_disabled", message: "خدمة الصوت متوقفة حاليًا من إدارة Happy Live" }, 503, origin, env);
      }
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(agoraTokenRoute[1]);
        const room = await env.DB.prepare("SELECT id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1")
          .bind(roomId).first<{ id: string }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const now = new Date().toISOString();
        const [ban, kick, control, seat] = await Promise.all([
          env.DB.prepare("SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first(),
          env.DB.prepare("SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1").bind(roomId, user.id, now).first(),
          env.DB.prepare("SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ? LIMIT 1").bind(roomId, user.id).first<{ is_muted: number }>(),
          env.DB.prepare("SELECT seat_number FROM room_seats WHERE room_id = ? AND user_id = ? AND expires_at > ? LIMIT 1").bind(roomId, user.id, now).first<{ seat_number: number }>()
        ]);
        if (ban || kick) return json({ error: ban ? "room_banned" : "room_kicked" }, 403, origin, env);
        let requestedPublish = false;
        try {
          const body = await request.json() as Record<string, unknown>;
          requestedPublish = body.publish === true;
        } catch {
          requestedPublish = false;
        }
        const canPublish = requestedPublish && Boolean(seat) && control?.is_muted !== 1;
        const numericUid = Number(user.gabo_id);
        if (!Number.isSafeInteger(numericUid) || numericUid < 1 || numericUid > 2147483647) {
          return json({ error: "invalid_user_id" }, 400, origin, env);
        }
        const channel = "hl" + (await sha256(roomId)).slice(0, 30);
        const ttl = 3600;
        // Explicitly omit publish privileges for listeners. Role.SUBSCRIBER alone is not
        // sufficient unless Agora Co-host authentication is enabled for the project.
        const rtcToken = RtcTokenBuilder.buildTokenWithUidAndPrivilege(
          env.AGORA_APP_ID, env.AGORA_APP_CERTIFICATE, channel, numericUid,
          ttl, ttl, canPublish ? ttl : 0, 0, 0
        );
        return json({ ok: true, appId: env.AGORA_APP_ID, channel, uid: numericUid, token: rtcToken, role: canPublish ? "publisher" : "audience", canPublish, expiresIn: ttl }, 200, origin, env);
      } catch (error) {
        console.error("[agora.token] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "agora_token_failed", message: "تعذر تجهيز اتصال الصوت" }, 500, origin, env);
      }
    }

    // Eight shared microphone seats. A seat is leased for 45 seconds and renewed by
    // authenticated clients, so abandoned seats disappear after disconnects.
    const seatRoute = url.pathname.match(/^\/api\/v1\/rooms\/([^/]+)\/seats$/);
    if (seatRoute && (request.method === "GET" || request.method === "POST")) {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const roomId = decodeURIComponent(seatRoute[1]);
        const now = new Date().toISOString();
        const room = await env.DB.prepare(
          "SELECT r.id, r.owner_user_id, r.name, r.description, COALESCE(ra.announcement, r.description, '') AS announcement, r.image_url, r.room_code, p.display_name AS owner_name FROM rooms r LEFT JOIN room_announcements ra ON ra.room_id = r.id LEFT JOIN profiles p ON p.user_id = r.owner_user_id WHERE r.id = ? AND r.status = 'active' LIMIT 1"
        ).bind(roomId).first<{ id: string; owner_user_id: string; name: string; description: string; announcement: string; image_url: string | null; room_code: string; owner_name: string | null }>();
        if (!room) return json({ error: "room_not_found" }, 404, origin, env);
        const voiceEnabled = await isAgoraVoiceEnabled(env.DB, env);
        if (!voiceEnabled) {
          await env.DB.prepare("DELETE FROM room_seats WHERE room_id = ?").bind(roomId).run();
        }

        const activeBan = await env.DB.prepare(
          "SELECT user_id FROM room_bans WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, user.id).first<{ user_id: string }>();
        const activeKick = await env.DB.prepare(
          "SELECT kicked_until FROM room_user_controls WHERE room_id = ? AND user_id = ? AND kicked_until > ? LIMIT 1"
        ).bind(roomId, user.id, now).first<{ kicked_until: string }>();
        if (activeKick) return json({ error: "room_kicked", message: "تم طردك مؤقتاً من الغرفة" }, 403, origin, env);

        // Expired leases are never shown as occupied.
        await env.DB.prepare("DELETE FROM room_seats WHERE room_id = ? AND expires_at <= ?").bind(roomId, now).run();

        if (request.method === "POST") {
          let body: Record<string, unknown>;
          try { body = await request.json() as Record<string, unknown>; }
          catch { return json({ error: "invalid_json" }, 400, origin, env); }

          if (body.heartbeat === true) {
            if (voiceEnabled) {
              const heartbeatExpiry = new Date(Date.now() + 45000).toISOString();
              await env.DB.prepare(
                "UPDATE room_seats SET updated_at = ?, expires_at = ? WHERE room_id = ? AND user_id = ?"
              ).bind(now, heartbeatExpiry, roomId, user.id).run();
            }
            await env.DB.prepare(
              "UPDATE room_chat_visits SET last_seen_at = ? WHERE room_id = ? AND user_id = ? AND exited_at IS NULL"
            ).bind(now, roomId, user.id).run();
          } else if (body.seatNumber === null) {
            await env.DB.prepare("DELETE FROM room_seats WHERE room_id = ? AND user_id = ?").bind(roomId, user.id).run();
          } else {
            if (!voiceEnabled) {
              return json({ error: "agora_voice_disabled", message: "الميكروفونات متوقفة حاليًا من إدارة التطبيق" }, 503, origin, env);
            }
            if (activeBan) return json({ error: "room_banned", message: "أنت محظور من استخدام المايك في هذه الغرفة" }, 403, origin, env);
            const seatNumber = Number(body.seatNumber);
            if (!Number.isInteger(seatNumber) || seatNumber < 1 || seatNumber > 8) {
              return json({ error: "invalid_seat_number" }, 400, origin, env);
            }
            const expiresAt = new Date(Date.now() + 45000).toISOString();
            try {
              const result = await env.DB.prepare(
                "INSERT INTO room_seats (room_id, seat_number, user_id, joined_at, updated_at, expires_at) SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM room_seats WHERE room_id = ? AND seat_number = ? AND user_id <> ?) AND COALESCE((SELECT setting_value FROM platform_settings WHERE setting_key = 'agora_voice_enabled'), 'true') <> 'false' ON CONFLICT(room_id, user_id) DO UPDATE SET seat_number = excluded.seat_number, updated_at = excluded.updated_at, expires_at = excluded.expires_at WHERE NOT EXISTS (SELECT 1 FROM room_seats WHERE room_id = excluded.room_id AND seat_number = excluded.seat_number AND user_id <> excluded.user_id) RETURNING seat_number"
              ).bind(roomId, seatNumber, user.id, now, now, expiresAt, roomId, seatNumber, user.id).first<{ seat_number: number }>();
              if (!result) {
                return json({ error: "seat_occupied", message: "هذا المايك مشغول" }, 409, origin, env);
              }
            } catch {
              // The unique seat constraint is the final guard against simultaneous claims.
              return json({ error: "seat_occupied", message: "هذا المايك مشغول" }, 409, origin, env);
            }
          }
        }

        const seatsResult = await env.DB.prepare(
          "SELECT s.seat_number, s.user_id, s.joined_at, p.display_name, p.gabo_id, p.avatar_key, COALESCE(c.is_muted, 0) AS is_muted, (s.user_id = (SELECT owner_user_id FROM rooms WHERE id = s.room_id)) AS is_room_owner, EXISTS(SELECT 1 FROM room_moderators rm WHERE rm.room_id = s.room_id AND rm.user_id = s.user_id) AS is_room_moderator FROM room_seats s LEFT JOIN profiles p ON p.user_id = s.user_id LEFT JOIN room_user_controls c ON c.room_id = s.room_id AND c.user_id = s.user_id WHERE s.room_id = ? AND s.expires_at > ? ORDER BY s.seat_number"
        ).bind(roomId, new Date().toISOString()).all<{ seat_number: number; user_id: string; joined_at: string; display_name: string | null; gabo_id: string | null; avatar_key: string | null; is_muted: number; is_room_owner: number; is_room_moderator: number }>();
        const seats = (seatsResult.results ?? []).map((seat) => ({
          seatNumber: seat.seat_number,
          userId: seat.user_id,
          userCode: seat.gabo_id ?? "",
          isMuted: seat.is_muted === 1,
          isRoomOwner: seat.is_room_owner === 1,
          isRoomModerator: seat.is_room_moderator === 1,
          name: seat.display_name?.trim() || "مستخدم",
          avatarUrl: seat.avatar_key,
          joinedAt: seat.joined_at,
          isMe: seat.user_id === user.id
        }));
        const mySeat = seats.find((seat) => seat.userId === user.id)?.seatNumber ?? null;
        const roomModerator = await env.DB.prepare(
          "SELECT user_id FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, user.id).first<{ user_id: string }>();
        const myControl = await env.DB.prepare(
          "SELECT is_muted FROM room_user_controls WHERE room_id = ? AND user_id = ? LIMIT 1"
        ).bind(roomId, user.id).first<{ is_muted: number }>();
        const audienceCutoff = new Date(Date.now() - 45000).toISOString();
        await env.DB.prepare(
          "UPDATE room_chat_visits SET exited_at = ? WHERE room_id = ? AND exited_at IS NULL AND last_seen_at < ?"
        ).bind(now, roomId, audienceCutoff).run();
        const audience = await env.DB.prepare(
          "SELECT COUNT(DISTINCT user_id) AS count FROM room_chat_visits WHERE room_id = ? AND exited_at IS NULL AND last_seen_at >= ?"
        ).bind(roomId, audienceCutoff).first<{ count: number }>();
        return json({
          ok: true,
          audienceCount: audience?.count ?? 0,
          voiceEnabled,
          room: { id: room.id, name: room.name, description: room.description, announcement: room.announcement, imageUrl: room.image_url, roomCode: room.room_code },
          owner: { id: room.owner_user_id, name: room.owner_name?.trim() || "صاحب الغرفة" },
          me: { id: user.id, name: user.display_name?.trim() || "مستخدم", isMuted: myControl?.is_muted === 1, isBanned: !!activeBan },
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
        const rows = await env.DB.prepare(
          "SELECT p.id, p.user_id, p.content, p.image_url, p.visibility, p.created_at, pr.display_name, pr.gabo_id, pr.avatar_key, " +
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
          display_name: string | null; gabo_id: string | null; avatar_key: string | null;
          liked: number; likes_count: number; comments_count: number; followed: number;
        }>();
        return json({ ok: true, posts: (rows.results ?? []).map(p => ({
          id: p.id, userId: p.user_id, name: p.display_name?.trim() || "مستخدم",
          userCode: p.gabo_id, avatarUrl: p.avatar_key, content: p.content, imageUrl: p.image_url, createdAt: p.created_at,
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
        await env.DB.prepare("INSERT INTO posts (id, user_id, content, image_url, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)")
          .bind(id, user.id, content, imageUrl || null, createdAt, createdAt).run();
        return json({ ok: true, post: { id, userId: user.id, name: user.display_name?.trim() || "مستخدم", userCode: user.gabo_id, content, imageUrl: imageUrl || null, createdAt, liked: false, likesCount: 0, commentsCount: 0, followed: false, isMine: true } }, 201, origin, env);
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
        const post = await env.DB.prepare("SELECT id, user_id FROM posts WHERE id = ? AND status = 'published'").bind(postId).first<{ id: string; user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id !== user.id) return json({ error: "not_post_owner" }, 403, origin, env);
        if (request.method === "DELETE") {
          await env.DB.prepare("UPDATE posts SET status = 'deleted', updated_at = ? WHERE id = ? AND user_id = ?").bind(new Date().toISOString(), postId, user.id).run();
          return json({ ok: true }, 200, origin, env);
        }
        const body = await request.json() as Record<string, unknown>;
        const visibility = typeof body.visibility === "string" ? body.visibility : "";
        if (!["public", "followers", "private"].includes(visibility)) return json({ error: "invalid_visibility" }, 400, origin, env);
        await env.DB.prepare("UPDATE posts SET visibility = ?, updated_at = ? WHERE id = ? AND user_id = ?").bind(visibility, new Date().toISOString(), postId, user.id).run();
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
        const target = await env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetId).first();
        if (!target) return json({ error: "user_not_found" }, 404, origin, env);
        await env.DB.prepare("INSERT INTO user_hidden_users (user_id, hidden_user_id, created_at) VALUES (?, ?, ?) ON CONFLICT(user_id, hidden_user_id) DO NOTHING").bind(user.id, targetId, new Date().toISOString()).run();
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
        const post = await env.DB.prepare("SELECT id, user_id FROM posts WHERE id = ? AND status = 'published'").bind(postReportRoute[1]).first<{ id: string; user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id === user.id) return json({ error: "cannot_report_own_post" }, 400, origin, env);
        await env.DB.prepare("INSERT INTO post_reports (id, post_id, reporter_id, reported_user_id, reason, created_at) VALUES (?, ?, ?, ?, ?, ?)").bind(crypto.randomUUID(), post.id, user.id, post.user_id, reason || "general", new Date().toISOString()).run();
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
        const post = await env.DB.prepare("SELECT id FROM posts WHERE id = ? AND status = 'published'").bind(postLikeRoute[1]).first();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        const existing = await env.DB.prepare("SELECT 1 AS found FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postLikeRoute[1], user.id).first();
        if (existing) await env.DB.prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postLikeRoute[1], user.id).run();
        else await env.DB.prepare("INSERT INTO post_likes (post_id, user_id, created_at) VALUES (?, ?, ?)").bind(postLikeRoute[1], user.id, new Date().toISOString()).run();
        const count = await env.DB.prepare("SELECT COUNT(*) AS total FROM post_likes WHERE post_id = ?").bind(postLikeRoute[1]).first<{ total: number }>();
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
        const parent = await env.DB.prepare(
          "SELECT c.id FROM post_comments c INNER JOIN posts p ON p.id = c.post_id WHERE c.id = ? AND c.post_id = ? AND p.status = 'published'"
        ).bind(commentRepliesRoute[2], commentRepliesRoute[1]).first();
        if (!parent) return json({ error: "comment_not_found" }, 404, origin, env);
        if (parentReplyId) {
          const parentReply = await env.DB.prepare("SELECT id FROM post_comment_replies WHERE id = ? AND comment_id = ?")
            .bind(parentReplyId, commentRepliesRoute[2]).first();
          if (!parentReply) return json({ error: "parent_reply_not_found" }, 404, origin, env);
        }
        const id = crypto.randomUUID();
        const createdAt = new Date().toISOString();
        await env.DB.prepare("INSERT INTO post_comment_replies (id, comment_id, user_id, content, created_at, parent_reply_id) VALUES (?, ?, ?, ?, ?, ?)")
          .bind(id, commentRepliesRoute[2], user.id, content, createdAt, parentReplyId).run();
        const profile = await env.DB.prepare("SELECT avatar_key FROM profiles WHERE user_id = ?")
          .bind(user.id).first<{ avatar_key: string | null }>();
        return json({ ok: true, reply: { id, commentId: commentRepliesRoute[2], userId: user.id, content, createdAt, name: user.display_name?.trim() || "مستخدم", userCode: user.gabo_id, avatarUrl: profile?.avatar_key ?? null } }, 201, origin, env);
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
        const rows = await env.DB.prepare(
          "SELECT r.id, r.post_id, r.comment_id, r.reason, r.status, r.created_at, " +
          "reporter.id AS reporter_id, reporter_profile.display_name AS reporter_name, reporter_profile.gabo_id AS reporter_code, " +
          "reported.id AS reported_user_id, reported_profile.display_name AS reported_name, reported_profile.gabo_id AS reported_code, " +
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
        const post = await env.DB.prepare("SELECT user_id FROM posts WHERE id = ? AND status = 'published'")
          .bind(commentActionRoute[1]).first<{ user_id: string }>();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        if (post.user_id !== user.id) return json({ error: "forbidden" }, 403, origin, env);
        const comment = await env.DB.prepare("SELECT id FROM post_comments WHERE id = ? AND post_id = ?")
          .bind(commentActionRoute[2], commentActionRoute[1]).first<{ id: string }>();
        if (!comment) return json({ error: "comment_not_found" }, 404, origin, env);
        await env.DB.prepare("DELETE FROM post_comment_replies WHERE comment_id = ?").bind(comment.id).run();
        await env.DB.prepare("DELETE FROM post_comments WHERE id = ? AND post_id = ?")
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
        const comment = await env.DB.prepare(
          "SELECT c.id, c.user_id FROM post_comments c INNER JOIN posts p ON p.id = c.post_id WHERE c.id = ? AND c.post_id = ? AND p.status = 'published'"
        ).bind(commentActionRoute[2], commentActionRoute[1]).first<{ id: string; user_id: string }>();
        if (!comment) return json({ error: "comment_not_found" }, 404, origin, env);
        if (comment.user_id === user.id) return json({ error: "cannot_report_own_comment" }, 400, origin, env);
        const existing = await env.DB.prepare("SELECT id FROM post_comment_reports WHERE comment_id = ? AND reporter_id = ?")
          .bind(comment.id, user.id).first();
        if (existing) return json({ error: "already_reported" }, 409, origin, env);
        const reportId = crypto.randomUUID();
        const reportedAt = new Date().toISOString();
        await env.DB.prepare("INSERT INTO post_comment_reports (id, post_id, comment_id, reporter_id, reported_user_id, reason, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)")
          .bind(reportId, commentActionRoute[1], comment.id, user.id, comment.user_id, "general", reportedAt).run();
        await env.DB.prepare("INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
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
        const rows = await env.DB.prepare(
          "SELECT c.id, c.user_id, c.content, c.created_at, p.display_name, p.gabo_id, p.avatar_key FROM post_comments c LEFT JOIN profiles p ON p.user_id = c.user_id WHERE c.post_id = ? ORDER BY c.created_at ASC LIMIT 100"
        ).bind(postCommentsRoute[1]).all<{ id: string; user_id: string; content: string; created_at: string; display_name: string | null; gabo_id: string | null; avatar_key: string | null }>();
        const comments = (rows.results ?? []).map(c => ({ id: c.id, userId: c.user_id, content: c.content, createdAt: c.created_at, name: c.display_name?.trim() || "مستخدم", userCode: c.gabo_id, avatarUrl: c.avatar_key, replies: [] as Array<Record<string, unknown>> }));
        const replies = await env.DB.prepare(
          "SELECT r.id, r.comment_id, r.parent_reply_id, r.user_id, r.content, r.created_at, p.display_name, p.gabo_id, p.avatar_key FROM post_comment_replies r LEFT JOIN profiles p ON p.user_id = r.user_id INNER JOIN post_comments c ON c.id = r.comment_id WHERE c.post_id = ? ORDER BY r.created_at ASC"
        ).bind(postCommentsRoute[1]).all<{ id: string; comment_id: string; parent_reply_id: string | null; user_id: string; content: string; created_at: string; display_name: string | null; gabo_id: string | null; avatar_key: string | null }>();
        const commentsById = new Map(comments.map(c => [c.id, c]));
        const repliesById = new Map<string, Record<string, unknown>>();
        for (const row of replies.results ?? []) {
          repliesById.set(row.id, {
            id: row.id, commentId: row.comment_id, parentReplyId: row.parent_reply_id,
            userId: row.user_id, content: row.content, createdAt: row.created_at,
            name: row.display_name?.trim() || "مستخدم", userCode: row.gabo_id,
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
        const post = await env.DB.prepare("SELECT id FROM posts WHERE id = ? AND status = 'published'").bind(postCommentsRoute[1]).first();
        if (!post) return json({ error: "post_not_found" }, 404, origin, env);
        const createdAt = new Date().toISOString();
        const allowed = await env.DB.prepare(
          "INSERT INTO post_comment_rate_limits (user_id, last_comment_at) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET last_comment_at = excluded.last_comment_at WHERE CAST(strftime('%s', excluded.last_comment_at) AS INTEGER) - CAST(strftime('%s', post_comment_rate_limits.last_comment_at) AS INTEGER) >= 30 RETURNING user_id"
        ).bind(user.id, createdAt).first<{ user_id: string }>();
        if (!allowed) {
          const last = await env.DB.prepare("SELECT last_comment_at FROM post_comment_rate_limits WHERE user_id = ?")
            .bind(user.id).first<{ last_comment_at: string }>();
          const elapsed = last ? Math.max(0, Math.floor((Date.now() - Date.parse(last.last_comment_at)) / 1000)) : 0;
          const retryAfter = Math.max(1, 30 - elapsed);
          return json({ error: "comment_cooldown", message: `انتظر ${retryAfter} ثانية قبل كتابة تعليق جديد`, retryAfterSeconds: retryAfter }, 429, origin, env);
        }
        const id = crypto.randomUUID();
        await env.DB.prepare("INSERT INTO post_comments (id, post_id, user_id, content, created_at) VALUES (?, ?, ?, ?, ?)")
          .bind(id, postCommentsRoute[1], user.id, content, createdAt).run();
        const commenterProfile = await env.DB.prepare("SELECT avatar_key FROM profiles WHERE user_id = ?")
          .bind(user.id).first<{ avatar_key: string | null }>();
        return json({ ok: true, comment: { id, userId: user.id, content, createdAt, name: user.display_name?.trim() || "مستخدم", userCode: user.gabo_id, avatarUrl: commenterProfile?.avatar_key ?? null } }, 201, origin, env);
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
        const target = await env.DB.prepare(
          "SELECT u.id, p.display_name, p.gabo_id, p.avatar_key FROM users u " +
          "INNER JOIN profiles p ON p.user_id = u.id " +
          "WHERE p.gabo_id = ? AND u.status = 'active' LIMIT 1"
        ).bind(userByCodeRoute[1]).first<{
          id: string; display_name: string | null; gabo_id: string;
          avatar_key: string | null;
        }>();
        if (!target) return json({ error: "user_not_found", message: "لم يتم العثور على مستخدم بهذا ID" }, 404, origin, env);
        return json({ ok: true, user: {
          id: target.id, name: target.display_name?.trim() || "مستخدم",
          userCode: target.gabo_id, avatarUrl: target.avatar_key
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
        const profile = await env.DB.prepare(
          "SELECT u.id, p.display_name, p.gabo_id, p.avatar_key, p.cover_key, p.bio, p.country_name, p.gender, p.birthday, p.is_private, p.created_at " +
          "FROM users u INNER JOIN profiles p ON p.user_id = u.id WHERE u.id = ? AND u.status = 'active' LIMIT 1"
        ).bind(targetId).first<{
          id: string; display_name: string; gabo_id: string | null; avatar_key: string | null;
          cover_key: string | null; bio: string; country_name: string | null; gender: string | null;
          birthday: string | null; is_private: number; created_at: string;
        }>();
        if (!profile) return json({ error: "user_not_found" }, 404, origin, env);
        const isMine = viewer.id === targetId;
        const follow = isMine ? null : await env.DB.prepare(
          "SELECT 1 AS found FROM user_follows WHERE follower_id = ? AND following_id = ? LIMIT 1"
        ).bind(viewer.id, targetId).first<{ found: number }>();
        const isFollowing = Boolean(follow);
        const canViewPosts = !profile.is_private || isMine || isFollowing;
        const stats = await env.DB.prepare(
          "SELECT " +
          "(SELECT COUNT(*) FROM user_follows WHERE following_id = ?) AS followers, " +
          "(SELECT COUNT(*) FROM user_follows WHERE follower_id = ?) AS following, " +
          "(SELECT COUNT(*) FROM posts WHERE user_id = ? AND status = 'published') AS posts, " +
          "(SELECT COUNT(*) FROM post_likes l INNER JOIN posts p ON p.id = l.post_id WHERE p.user_id = ? AND p.status = 'published') AS likes_received, " +
          "(SELECT COUNT(*) FROM rooms WHERE owner_user_id = ? AND status = 'active') AS active_rooms"
        ).bind(targetId, targetId, targetId, targetId, targetId).first<{
          followers: number; following: number; posts: number; likes_received: number; active_rooms: number;
        }>();
        const posts = canViewPosts ? await env.DB.prepare(
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
          userId: profile.id, name: profile.display_name, userCode: profile.gabo_id ?? "",
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
        const target = await env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(followRoute[1]).first();
        if (!target) return json({ error: "user_not_found" }, 404, origin, env);
        const existing = await env.DB.prepare("SELECT 1 AS found FROM user_follows WHERE follower_id = ? AND following_id = ?").bind(user.id, followRoute[1]).first();
        if (existing) await env.DB.prepare("DELETE FROM user_follows WHERE follower_id = ? AND following_id = ?").bind(user.id, followRoute[1]).run();
        else await env.DB.prepare("INSERT INTO user_follows (follower_id, following_id, created_at) VALUES (?, ?, ?)").bind(user.id, followRoute[1], new Date().toISOString()).run();
        return json({ ok: true, following: !existing }, 200, origin, env);
      } catch (error) {
        console.error("[users.follow] failed", error instanceof Error ? error.message : "UnknownError");
        return json({ error: "follow_failed" }, 500, origin, env);
      }
    }


    // Return the signed-in user's permanent room, if one has already been created.
    if (url.pathname === "/api/v1/rooms/mine" && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const room = await env.DB.prepare(
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

    // Find one active room by its public eight-digit room code.
    const roomCodeRoute = url.pathname.match(/^\/api\/v1\/rooms\/by-code\/(\d{8})$/);
    if (roomCodeRoute && request.method === "GET") {
      if (!env.DB) return json({ error: "database_unavailable" }, 503, origin, env);
      try {
        const user = await authenticatedUser(request, env.DB);
        if (!user) return json({ error: "authentication_required" }, 401, origin, env);
        const room = await env.DB.prepare(
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
        const result = await env.DB.prepare(
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
        const existingRoom = await env.DB.prepare(
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
        const imageUrl = typeof body.imageUrl === "string" ? body.imageUrl.trim() : "";
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
          roomCode = String(10000000 + (random[0] % 90000000));
          const inserted = await env.DB.prepare(
            "INSERT INTO rooms (id, room_code, owner_user_id, name, description, image_url, visibility, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?) ON CONFLICT(room_code) DO NOTHING"
          ).bind(roomId, roomCode, user.id, name, description, imageUrl || null, isPrivate ? "private" : "public", createdAt, createdAt).run();
          if ((inserted.meta?.changes ?? 0) === 1) {
            roomCreated = true;
            break;
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
        await env.DB.prepare("UPDATE user_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
          .bind(new Date().toISOString(), await sha256(match[1])).run();
      }
      return json({ ok: true }, 200, origin, env);
    }

    if (url.pathname === "/api/v1/health" && request.method === "GET") {
      let database = "not_configured";

      if (env.DB) {
        try {
          await env.DB.prepare("SELECT 1 AS ok").first();
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

      // Require a live application session before issuing upload credentials.
      // Session tokens are stored only as SHA-256 hashes in D1.
      const authorization = request.headers.get("Authorization") ?? "";
      const bearerMatch = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/i);
      if (!bearerMatch) {
        return json({ error: "authentication_required" }, 401, origin, env);
      }

      try {
        const tokenHashBytes = await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(bearerMatch[1])
        );
        const tokenHash = Array.from(new Uint8Array(tokenHashBytes))
          .map((byte) => byte.toString(16).padStart(2, "0"))
          .join("");
        const session = await env.DB.prepare(
          "SELECT s.user_id FROM user_sessions s INNER JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active' LIMIT 1"
        ).bind(tokenHash, new Date().toISOString()).first<{ user_id: string }>();

        if (!session) {
          return json({ error: "invalid_or_expired_session" }, 401, origin, env);
        }

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const now = Math.floor(Date.now() / 1000);
        const windowStart = now - 60;
        const rate = await env.DB.prepare(
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

    if (url.pathname === "/api/v1" && request.method === "GET") {
      return json({
        name: "Happy Live API",
        version: "v1",
        status: "scaffold",
        endpoints: ["/api/v1/health", "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/me", "/api/v1/auth/logout", "/api/v1/rooms", "/api/v1/imagekit/health", "/api/v1/imagekit/auth"]
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
