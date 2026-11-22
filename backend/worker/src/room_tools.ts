export interface RoomToolsEnv {
  DB?: D1Database;
}

export interface RoomToolsUser {
  id: string;
  display_name?: string | null;
  username?: string | null;
}

type AuthResolver = () => Promise<RoomToolsUser | null>;
type JsonResponder = (data: unknown, status?: number) => Response;

async function canManageRoom(db: D1Database, roomId: string, userId: string): Promise<boolean> {
  const room = await db.prepare(
    "SELECT owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
  ).bind(roomId).first<{ owner_user_id: string }>();
  if (!room) return false;
  if (room.owner_user_id === userId) return true;
  const moderator = await db.prepare(
    "SELECT 1 AS allowed FROM room_moderators WHERE room_id = ? AND user_id = ? LIMIT 1"
  ).bind(roomId, userId).first();
  return Boolean(moderator);
}

export async function isRoomLocked(db: D1Database, roomId: string): Promise<boolean> {
  const row = await db.prepare(
    "SELECT locked FROM rooms WHERE id = ? LIMIT 1"
  ).bind(roomId).first<{ locked: number | null }>();
  return row?.locked === 1;
}

/**
 * The existing room_kicks table is a live 60-second kick restriction, not a
 * historical log. Historical kick entries are already stored in
 * admin_audit_logs, so this feature reads that source instead of creating a
 * conflicting second room_kicks schema.
 */
export async function recordRoomKick(
  db: D1Database,
  roomId: string,
  targetId: string,
  adminId: string,
  reason = ""
): Promise<void> {
  const actor = await db.prepare(
    "SELECT display_name FROM profiles WHERE user_id = ? LIMIT 1"
  ).bind(adminId).first<{ display_name: string | null }>();
  await db.prepare(
    "INSERT INTO room_settings_logs (id, room_id, actor_user_id, target_user_id, action, details_json, created_at) VALUES (?, ?, ?, ?, 'kick', ?, ?)"
  ).bind(
    crypto.randomUUID(),
    roomId,
    adminId,
    targetId,
    JSON.stringify({
      adminUsername: actor?.display_name ?? "مشرف",
      reason: reason.slice(0, 240),
      durationSeconds: 60
    }),
    new Date().toISOString()
  ).run();
}

export async function handleRoomTools(
  request: Request,
  env: RoomToolsEnv,
  authenticate: AuthResolver,
  respond: JsonResponder
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!["/api/room/tools-state", "/api/room/lock", "/api/room/kicks"].includes(url.pathname)) {
    return null;
  }
  if (!env.DB) return respond({ ok: false, error: "database_unavailable" }, 503);

  const user = await authenticate();
  if (!user) return respond({ ok: false, error: "authentication_required" }, 401);

  if (url.pathname === "/api/room/tools-state" && request.method === "GET") {
    const roomId = (url.searchParams.get("room_id") ?? "").trim();
    if (!roomId) return respond({ ok: false, error: "room_id_required" }, 400);
    const room = await env.DB.prepare(
      "SELECT id, locked FROM rooms WHERE id = ? AND status = 'active' LIMIT 1"
    ).bind(roomId).first<{ id: string; locked: number | null }>();
    if (!room) return respond({ ok: false, error: "room_not_found" }, 404);
    return respond({ ok: true, locked: room.locked === 1 });
  }

  if (url.pathname === "/api/room/lock" && request.method === "POST") {
    let body: Record<string, unknown>;
    try { body = await request.json() as Record<string, unknown>; }
    catch { return respond({ ok: false, error: "invalid_json" }, 400); }
    const roomId = typeof body.room_id === "string" ? body.room_id.trim() : "";
    if (!roomId || typeof body.locked !== "boolean") {
      return respond({ ok: false, error: "invalid_lock_request" }, 400);
    }
    const room = await env.DB.prepare("SELECT owner_user_id FROM rooms WHERE id = ? AND status = 'active' LIMIT 1").bind(roomId).first<{ owner_user_id: string }>();
    if (!room) return respond({ ok: false, error: "room_not_found" }, 404);
    if (room.owner_user_id !== user.id) return respond({ ok: false, error: "room_owner_required", message: "قفل الغرفة متاح للمالك فقط" }, 403);
    let lockStage = "read_settings";
    try {
      const settingsRow = await env.DB.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1").bind(roomId).first<{ settings_json: string }>();
      let settings: Record<string, unknown> = {};
      try { settings = settingsRow?.settings_json ? JSON.parse(settingsRow.settings_json) as Record<string, unknown> : {}; } catch { settings = {}; }
      if (body.locked) {
        const password = typeof body.password === "string" ? body.password : "";
        if (!/^\d{6}$/.test(password)) return respond({ ok: false, error: "invalid_room_password", message: "كلمة المرور يجب أن تتكون من 6 أرقام" }, 400);
        lockStage = "derive_password_hash";
        const salt = crypto.getRandomValues(new Uint8Array(16));
        const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
        const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 120000, hash: "SHA-256" }, key, 256);
        settings.roomPasswordSalt = Array.from(salt).map(x => x.toString(16).padStart(2, "0")).join("");
        settings.roomPasswordHash = Array.from(new Uint8Array(bits)).map(x => x.toString(16).padStart(2, "0")).join("");
      } else {
        delete settings.roomPasswordSalt;
        delete settings.roomPasswordHash;
      }
      lockStage = "write_database";
      const now = new Date().toISOString();
      await env.DB.batch([
        env.DB.prepare("UPDATE rooms SET locked = ? WHERE id = ?").bind(body.locked ? 1 : 0, roomId),
        env.DB.prepare("INSERT INTO room_settings (room_id, settings_json, updated_at) VALUES (?, ?, ?) ON CONFLICT(room_id) DO UPDATE SET settings_json = excluded.settings_json, updated_at = excluded.updated_at")
          .bind(roomId, JSON.stringify(settings), now)
      ]);
      return respond({ ok: true, roomId, locked: body.locked });
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      console.error("room_lock_failed", { roomId, userId: user.id, stage: lockStage, error: detail });
      return respond({ ok: false, error: "room_lock_failed", stage: lockStage, message: "فشل القفل في مرحلة " + lockStage + ": " + detail }, 500);
    }
  }

  if (url.pathname === "/api/room/kicks" && request.method === "GET") {
    const roomId = (url.searchParams.get("room_id") ?? "").trim();
    if (!roomId) return respond({ ok: false, error: "room_id_required" }, 400);
    if (!await canManageRoom(env.DB, roomId, user.id)) {
      return respond({ ok: false, error: "room_moderator_permission_required" }, 403);
    }
    const rows = await env.DB.prepare(
      "SELECT l.target_user_id AS userId, COALESCE(t.display_name, 'مستخدم') AS name, " +
      "COALESCE(t.avatar_key, '') AS avatar, COALESCE(a.display_name, 'مشرف') AS by, " +
      "COALESCE(json_extract(l.details_json, '$.reason'), '') AS reason, l.created_at AS time " +
      "FROM room_settings_logs l " +
      "LEFT JOIN profiles t ON t.user_id = l.target_user_id " +
      "LEFT JOIN profiles a ON a.user_id = l.actor_user_id " +
      "WHERE l.room_id = ? AND l.action = 'kick' " +
      "ORDER BY l.created_at DESC LIMIT 100"
    ).bind(roomId).all();
    return respond({ ok: true, kicks: rows.results ?? [] });
  }

  return respond({ ok: false, error: "method_not_allowed" }, 405);
}
