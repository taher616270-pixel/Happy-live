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
    "INSERT INTO admin_audit_logs (id, actor_user_id, action, target_type, target_id, details_json, created_at) VALUES (?, NULL, 'room.user.kick', 'room_user', ?, ?, ?)"
  ).bind(
    crypto.randomUUID(),
    targetId,
    JSON.stringify({
      roomId,
      targetUserId: targetId,
      adminId,
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
    const allowed = await canManageRoom(env.DB, roomId, user.id);
    if (!allowed) return respond({ ok: false, error: "room_moderator_permission_required" }, 403);
    await env.DB.prepare("UPDATE rooms SET locked = ? WHERE id = ?")
      .bind(body.locked ? 1 : 0, roomId).run();
    return respond({ ok: true, roomId, locked: body.locked });
  }

  if (url.pathname === "/api/room/kicks" && request.method === "GET") {
    const roomId = (url.searchParams.get("room_id") ?? "").trim();
    if (!roomId) return respond({ ok: false, error: "room_id_required" }, 400);
    if (!await canManageRoom(env.DB, roomId, user.id)) {
      return respond({ ok: false, error: "room_moderator_permission_required" }, 403);
    }
    const rows = await env.DB.prepare(
      "SELECT l.target_id AS userId, COALESCE(p.display_name, 'مستخدم') AS name, " +
      "COALESCE(p.avatar_key, '') AS avatar, " +
      "COALESCE(json_extract(l.details_json, '$.adminUsername'), 'مشرف') AS by, " +
      "COALESCE(json_extract(l.details_json, '$.reason'), '') AS reason, " +
      "l.created_at AS time " +
      "FROM admin_audit_logs l LEFT JOIN profiles p ON p.user_id = l.target_id " +
      "WHERE l.action = 'room.user.kick' AND l.target_type = 'room_user' " +
      "AND json_extract(l.details_json, '$.roomId') = ? " +
      "ORDER BY l.created_at DESC LIMIT 100"
    ).bind(roomId).all();
    return respond({ ok: true, kicks: rows.results ?? [] });
  }

  return respond({ ok: false, error: "method_not_allowed" }, 405);
}
