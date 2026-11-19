export interface RoomSeatMember {
  seatNumber: number;
  userId: string;
  name: string;
  userCode: string;
  avatarUrl: string;
  countryName: string;
  uid: number | null;
  isMuted: boolean;
  isRoomOwner: boolean;
  isRoomModerator: boolean;
  expiresAt: number;
}

interface RoomSeatSnapshot {
  seats: Record<string, RoomSeatMember>;
  versions: Record<string, number>;
  revision: number;
  voiceEnabled: boolean;
}

interface SocketIdentity {
  userId: string;
  name: string;
  userCode: string;
  avatarUrl: string;
  countryName: string;
  uid: number | null;
  isMuted: boolean;
  isRoomOwner: boolean;
  isRoomModerator: boolean;
  lastVersion: number;
}

const EMPTY_SNAPSHOT: RoomSeatSnapshot = { seats: {}, versions: {}, revision: 0, voiceEnabled: true };
const SEAT_LEASE_MS = 45_000;
const ROOM_EXP_DAILY_USER_CAP = 3_000_000;
const ROOM_EXP_DAILY_ROOM_CAP = 14_000_000;

interface RoomSeatsEnv {
  DB: D1Database;
}

async function resetRoomSeatExperienceTimer(
  db: D1Database, roomId: string, userId: string, now: string
): Promise<void> {
  await db.prepare(
    "INSERT INTO room_exp_activity (room_id, user_id, last_awarded_at) VALUES (?, ?, ?) ON CONFLICT(room_id, user_id) DO UPDATE SET last_awarded_at = excluded.last_awarded_at"
  ).bind(roomId, userId, now).run();
}

async function awardRoomSeatExperience(
  db: D1Database, roomId: string, userId: string, now: string
): Promise<void> {
  await db.prepare(
    "INSERT OR IGNORE INTO room_exp_activity (room_id, user_id, last_awarded_at) VALUES (?, ?, ?)"
  ).bind(roomId, userId, now).run();
  const previous = await db.prepare(
    "SELECT last_awarded_at FROM room_exp_activity WHERE room_id = ? AND user_id = ? LIMIT 1"
  ).bind(roomId, userId).first<{ last_awarded_at: string }>();
  if (!previous?.last_awarded_at || Date.parse(now) - Date.parse(previous.last_awarded_at) < 300_000) return;

  const dayKey = new Date(Date.parse(now) + 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const nowMs = Date.parse(now);
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
  ).bind(now, roomId, userId, previous.last_awarded_at).run();
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
      ).bind(previous.last_awarded_at, roomId, userId, now).run();
    } catch {
      // Keep the original D1 error; the next heartbeat can retry if rollback was unavailable.
    }
    throw error;
  }
}

export class RoomSeatsHub {
  private snapshot: RoomSeatSnapshot = structuredClone(EMPTY_SNAPSHOT);
  private roomId = '';
  private readonly sockets = new Map<WebSocket, SocketIdentity>();
  private mutationQueue: Promise<void> = Promise.resolve();
  private whoMicMode = "membersOnly";
  private async configuredSeatLimit(): Promise<number> {
    if (!this.roomId) return 8;
    try {
      const row = await this.env.DB.prepare("SELECT settings_json FROM room_settings WHERE room_id = ? LIMIT 1")
        .bind(this.roomId).first<{ settings_json: string }>();
      const settings = row?.settings_json ? JSON.parse(row.settings_json) as Record<string, unknown> : {};
      const value = Number(settings.seats ?? 8);
      return [2, 8, 10, 12, 14, 16, 20, 24].includes(value) ? value : 8;
    } catch {
      return 8;
    }
  }
  private readonly ready: Promise<void>;

  constructor(private readonly state: DurableObjectState, private readonly env: RoomSeatsEnv) {
    this.ready = this.state.blockConcurrencyWhile(async () => {
      this.roomId = (await this.state.storage.get<string>("room-id")) ?? '';
      this.snapshot = (await this.state.storage.get<RoomSeatSnapshot>("room-seat-snapshot")) ?? structuredClone(EMPTY_SNAPSHOT);
      if (!this.snapshot.seats) this.snapshot.seats = {};
      if (!this.snapshot.versions) this.snapshot.versions = {};
      if (!Number.isFinite(this.snapshot.revision)) this.snapshot.revision = 0;
      if (typeof this.snapshot.voiceEnabled !== "boolean") this.snapshot.voiceEnabled = true;
      this.whoMicMode = (await this.state.storage.get<string>("room-who-mic-mode")) ?? "membersOnly";
      await this.expireSeats(false);
    });
  }

  async fetch(request: Request): Promise<Response> {
    await this.ready;
    const url = new URL(request.url);

    if (url.pathname === "/snapshot" && request.method === "GET") {
      return Response.json(this.publicSnapshot());
    }

    if (url.pathname === "/gift" && request.method === "POST") {
      const roomId = request.headers.get("x-room-id") ?? "";
      if (!roomId || roomId !== this.roomId) return Response.json({ error: "room_mismatch" }, { status: 403 });
      let event: Record<string, unknown>;
      try { event = await request.json() as Record<string, unknown>; }
      catch { return Response.json({ error: "invalid_json" }, { status: 400 }); }
      this.broadcast({ type: "room_gift", ...event });
      return Response.json({ ok: true });
    }

    if (url.pathname === "/clear" && request.method === "POST") {
      await this.enqueue(async () => {
        // Clearing/disabling microphones ends every active continuous-time session.
        const removedMembers = Object.values(this.snapshot.seats);
        if (this.roomId) {
          for (const member of removedMembers) {
            try {
              await resetRoomSeatExperienceTimer(this.env.DB, this.roomId, member.userId, new Date().toISOString());
            } catch (error) {
              console.error("[room-seats.experience] clear timer reset failed", error instanceof Error ? error.message : "UnknownError");
            }
          }
        }
        this.snapshot.seats = {};
        this.snapshot.voiceEnabled = false;
        this.snapshot.revision++;
        await this.persist();
        await this.scheduleExpiry();
        this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/move" && request.method === "POST") {
      const userId = request.headers.get("x-user-id") ?? "";
      if (!userId) return Response.json({ error: "identity_required" }, { status: 401 });
      let body: Record<string, unknown>;
      try { body = await request.json() as Record<string, unknown>; }
      catch { return Response.json({ error: "invalid_json" }, { status: 400 }); }
      const to = body.to === null ? null : Number(body.to);
      const requestedVersion = Number(body.version);
      const version = Number.isSafeInteger(requestedVersion) && requestedVersion > 0
        ? requestedVersion
        : Math.max(Date.now() * 1000, (this.snapshot.versions[userId] ?? 0) + 1);
      if ((to !== null && (!Number.isInteger(to) || to < 1 || to > 24)) || !Number.isSafeInteger(version) || version < 1) {
        return Response.json({ error: "invalid_move" }, { status: 400 });
      }
      const identity: SocketIdentity = {
        userId,
        name: request.headers.get("x-user-name") ?? "مستخدم",
        userCode: request.headers.get("x-user-code") ?? "",
        avatarUrl: request.headers.get("x-avatar-url") ?? "",
        countryName: request.headers.get("x-country-name") ?? "",
        uid: Number(request.headers.get("x-user-code")) || null,
        isMuted: request.headers.get("x-is-muted") === "true",
        isRoomOwner: request.headers.get("x-is-room-owner") === "true",
        isRoomModerator: request.headers.get("x-is-room-moderator") === "true",
        lastVersion: 0
      };
      let result: Record<string, unknown> = {};
      await this.enqueue(async () => {
        result = await this.applyMove(identity, to, version);
        if (result.ok === true) this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
      });
      return Response.json(result, { status: result.ok === true ? 200 : result.code === "seat_occupied" ? 409 : 409 });
    }

    if (url.pathname === "/set-seat-count" && request.method === "POST") {
      const count = Number(request.headers.get("x-seat-count"));
      if (![8, 10, 12, 14, 16, 20, 24].includes(count)) {
        return Response.json({ error: "invalid_seat_count" }, { status: 400 });
      }
      await this.enqueue(async () => {
        const removed = Object.values(this.snapshot.seats).filter((seat) => seat.seatNumber > count);
        for (const member of removed) {
          delete this.snapshot.seats[String(member.seatNumber)];
          if (this.roomId) {
            try {
              await resetRoomSeatExperienceTimer(this.env.DB, this.roomId, member.userId, new Date().toISOString());
            } catch (error) {
              console.error("[room-seats.experience] seat-count timer reset failed", error instanceof Error ? error.message : "UnknownError");
            }
          }
        }
        if (removed.length > 0) {
          this.snapshot.revision++;
          await this.persist();
          await this.scheduleExpiry();
          this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
        }
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/enable" && request.method === "POST") {
      await this.enqueue(async () => {
        this.snapshot.voiceEnabled = true;
        this.snapshot.revision++;
        await this.persist();
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/set-mic-policy" && request.method === "POST") {
      const mode = request.headers.get("x-who-mic") ?? "membersOnly";
      if (!["everyone", "membersOnly", "ownerAndAdmins"].includes(mode)) {
        return Response.json({ error: "invalid_mic_policy" }, { status: 400 });
      }
      this.whoMicMode = mode;
      await this.state.storage.put("room-who-mic-mode", mode);
      return Response.json({ ok: true, whoMic: mode });
    }

    if (url.pathname === "/remove-user" && request.method === "POST") {
      const targetUserId = request.headers.get("x-target-user-id") ?? "";
      if (!targetUserId) return Response.json({ error: "target_required" }, { status: 400 });
      await this.enqueue(async () => {
        const current = Object.values(this.snapshot.seats).find((seat) => seat.userId === targetUserId);
        if (current) {
          // Moderation removal ends the member's continuous microphone session.
          if (this.roomId) {
            try {
              await resetRoomSeatExperienceTimer(this.env.DB, this.roomId, targetUserId, new Date().toISOString());
            } catch (error) {
              console.error("[room-seats.experience] removal timer reset failed", error instanceof Error ? error.message : "UnknownError");
            }
          }
          delete this.snapshot.seats[String(current.seatNumber)];
          this.snapshot.revision++;
          await this.persist();
          this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
        }
        for (const [socket, identity] of this.sockets) {
          if (identity.userId === targetUserId) {
            try { socket.close(4003, "room_moderation"); } catch { /* already closed */ }
            this.sockets.delete(socket);
          }
        }
        await this.scheduleExpiry();
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/set-moderator" && request.method === "POST") {
      const targetUserId = request.headers.get("x-target-user-id") ?? "";
      const moderator = request.headers.get("x-is-moderator") === "true";
      if (!targetUserId) return Response.json({ error: "target_required" }, { status: 400 });
      await this.enqueue(async () => {
        for (const identity of this.sockets.values()) {
          if (identity.userId === targetUserId) identity.isRoomModerator = moderator;
        }
        const member = Object.values(this.snapshot.seats).find((seat) => seat.userId === targetUserId);
        if (member) {
          member.isRoomModerator = moderator;
          this.snapshot.revision++;
          await this.persist();
          this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
        }
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/set-muted" && request.method === "POST") {
      const targetUserId = request.headers.get("x-target-user-id") ?? "";
      const muted = request.headers.get("x-is-muted") === "true";
      if (!targetUserId) return Response.json({ error: "target_required" }, { status: 400 });
      await this.enqueue(async () => {
        for (const identity of this.sockets.values()) {
          if (identity.userId === targetUserId) identity.isMuted = muted;
        }
        const member = Object.values(this.snapshot.seats).find((seat) => seat.userId === targetUserId);
        if (member) {
          member.isMuted = muted;
          this.snapshot.revision++;
          await this.persist();
          this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
        }
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/heartbeat" && request.method === "POST") {
      const userId = request.headers.get("x-user-id") ?? "";
      if (!userId) return Response.json({ error: "identity_required" }, { status: 401 });
      await this.enqueue(async () => {
        const member = Object.values(this.snapshot.seats).find((seat) => seat.userId === userId);
        if (member) {
          member.expiresAt = Date.now() + SEAT_LEASE_MS;
          this.snapshot.revision++;
          await this.persist();
        }
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname !== "/connect" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Not found", { status: 404 });
    }

    const requestedRoomId = request.headers.get("x-room-id") ?? this.roomId;
    if (!requestedRoomId) return new Response("Room identity required", { status: 400 });
    this.roomId = requestedRoomId;
    await this.state.storage.put("room-id", requestedRoomId);

    const userId = request.headers.get("x-user-id") ?? "";
    if (!userId) return new Response("Unauthorized", { status: 401 });
    const identity: SocketIdentity = {
      userId,
      name: request.headers.get("x-user-name") ?? "مستخدم",
      userCode: request.headers.get("x-user-code") ?? "",
      avatarUrl: request.headers.get("x-avatar-url") ?? "",
      countryName: request.headers.get("x-country-name") ?? "",
      uid: Number(request.headers.get("x-user-code")) || null,
      isMuted: request.headers.get("x-is-muted") === "true",
      isRoomOwner: request.headers.get("x-is-room-owner") === "true",
      isRoomModerator: request.headers.get("x-is-room-moderator") === "true",
      lastVersion: 0
    };

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();

    for (const [socket, current] of this.sockets) {
      if (current.userId === userId) {
        try { socket.close(4001, "reconnected"); } catch { /* already closed */ }
        this.sockets.delete(socket);
      }
    }
    this.sockets.set(server, identity);
    server.addEventListener("message", (event) => {
      this.enqueue(async () => this.handleSocketMessage(server, identity, event.data));
    });
    server.addEventListener("close", () => this.sockets.delete(server));
    server.addEventListener("error", () => this.sockets.delete(server));

    await this.enqueue(async () => {
      const current = Object.values(this.snapshot.seats).find((seat) => seat.userId === userId);
      if (current) {
        current.name = identity.name;
        current.userCode = identity.userCode;
        current.uid = identity.uid;
        current.avatarUrl = identity.avatarUrl;
        current.countryName = identity.countryName;
        current.isMuted = identity.isMuted;
        current.isRoomOwner = identity.isRoomOwner;
        current.isRoomModerator = identity.isRoomModerator;
        current.expiresAt = Date.now() + SEAT_LEASE_MS;
        this.snapshot.revision++;
        await this.persist();
      }
      this.send(server, { type: "seat_snapshot", ...this.publicSnapshot(), mySeat: current?.seatNumber ?? null });
      this.broadcast({ type: "seat_updated", ...this.publicSnapshot() }, server);
    });

    return new Response(null, {
      status: 101,
      headers: { "Sec-WebSocket-Protocol": "happy-live-seats" },
      webSocket: client
    });
  }

  private enqueue(task: () => Promise<void>): Promise<void> {
    this.mutationQueue = this.mutationQueue.then(task).catch((error) => {
      console.error("[room-seats] queued operation failed", error instanceof Error ? error.message : "UnknownError");
    });
    return this.mutationQueue;
  }

  private async handleSocketMessage(socket: WebSocket, identity: SocketIdentity, raw: unknown): Promise<void> {
    if (this.sockets.get(socket) !== identity) return;
    if (typeof raw !== "string" || raw.length > 4096) {
      this.send(socket, { type: "error", code: "invalid_message" });
      return;
    }
    let message: Record<string, unknown>;
    try { message = JSON.parse(raw) as Record<string, unknown>; }
    catch {
      this.send(socket, { type: "error", code: "invalid_json" });
      return;
    }

    if (message.type === "seat_heartbeat") {
      const member = Object.values(this.snapshot.seats).find((seat) => seat.userId === identity.userId);
      if (member) {
        member.expiresAt = Date.now() + SEAT_LEASE_MS;
        this.snapshot.revision++;
        await this.persist();
        try {
          if (this.roomId) await awardRoomSeatExperience(this.env.DB, this.roomId, identity.userId, new Date().toISOString());
        } catch (error) {
          console.error("[room-seats.experience] award failed", error instanceof Error ? error.message : "UnknownError");
        }
      }
      this.send(socket, { type: "heartbeat_ack", serverTime: Date.now() });
      return;
    }

    if (message.type !== "move_seat") {
      this.send(socket, { type: "error", code: "unsupported_message" });
      return;
    }

    const from = message.from === null ? null : Number(message.from);
    const to = message.to === null ? null : Number(message.to);
    const version = Number(message.version);
    if ((from !== null && (!Number.isInteger(from) || from < 1 || from > 24)) ||
        (to !== null && (!Number.isInteger(to) || to < 1 || to > 24)) ||
        !Number.isSafeInteger(version) || version < 1) {
      this.send(socket, { type: "ack", ok: false, code: "invalid_move", version, ...this.publicSnapshot() });
      return;
    }

    const result = await this.applyMove(identity, to, version);
    this.send(socket, { type: "ack", ...result });
    if (result.ok === true) {
      this.broadcast({ type: "seat_updated", ...this.publicSnapshot() }, socket);
    }
  }

  private async applyMove(identity: SocketIdentity, to: number | null, version: number): Promise<Record<string, unknown>> {
    if (!this.snapshot.voiceEnabled) {
      return { type: "ack", ok: false, code: "voice_disabled", version, ...this.publicSnapshot() };
    }
    const seatLimit = await this.configuredSeatLimit();
    if (to !== null && (!Number.isInteger(to) || to < 1 || to > seatLimit)) {
      return { type: "ack", ok: false, code: "seat_limit_exceeded", version, mySeat: Object.values(this.snapshot.seats).find((seat) => seat.userId === identity.userId)?.seatNumber ?? null, ...this.publicSnapshot() };
    }
    if (to !== null && this.whoMicMode === "ownerAndAdmins" && !identity.isRoomOwner && !identity.isRoomModerator) {
      return { type: "ack", ok: false, code: "mic_restricted", version, mySeat: Object.values(this.snapshot.seats).find((seat) => seat.userId === identity.userId)?.seatNumber ?? null, ...this.publicSnapshot() };
    }
    const lastVersion = Math.max(identity.lastVersion, this.snapshot.versions[identity.userId] ?? 0);
    if (version <= lastVersion) {
      return { type: "ack", ok: false, code: "stale_version", version, ...this.publicSnapshot() };
    }

    identity.lastVersion = version;
    this.snapshot.versions[identity.userId] = version;
    const current = Object.values(this.snapshot.seats).find((seat) => seat.userId === identity.userId);
    if (to !== null) {
      const occupant = this.snapshot.seats[String(to)];
      if (occupant && occupant.userId !== identity.userId) {
        await this.persist();
        return { type: "ack", ok: false, code: "seat_occupied", version, mySeat: current?.seatNumber ?? null, ...this.publicSnapshot() };
      }
    }

    if (current) delete this.snapshot.seats[String(current.seatNumber)];
    if (to !== null) {
      this.snapshot.seats[String(to)] = {
        seatNumber: to,
        userId: identity.userId,
        name: identity.name,
        userCode: identity.userCode,
        avatarUrl: identity.avatarUrl,
        countryName: identity.countryName,
        uid: identity.uid,
        isMuted: identity.isMuted,
        isRoomOwner: identity.isRoomOwner,
        isRoomModerator: identity.isRoomModerator,
        expiresAt: Date.now() + SEAT_LEASE_MS
      };
    }
    this.snapshot.revision++;
    await this.persist();
    await this.scheduleExpiry();
    if (current?.seatNumber !== to && this.roomId) {
      try {
        await resetRoomSeatExperienceTimer(this.env.DB, this.roomId, identity.userId, new Date().toISOString());
      } catch (error) {
        console.error("[room-seats.experience] timer reset failed", error instanceof Error ? error.message : "UnknownError");
      }
    }
    return { type: "ack", ok: true, code: "moved", version, from: current?.seatNumber ?? null, mySeat: to, ...this.publicSnapshot() };
  }

  private async expireSeats(shouldBroadcast: boolean): Promise<void> {
    const now = Date.now();
    let changed = false;
    for (const [number, member] of Object.entries(this.snapshot.seats)) {
      if (member.expiresAt <= now) {
        // An expired seat is no longer continuous microphone occupancy.
        if (this.roomId) {
          try {
            await resetRoomSeatExperienceTimer(this.env.DB, this.roomId, member.userId, new Date(now).toISOString());
          } catch (error) {
            console.error("[room-seats.experience] expiry timer reset failed", error instanceof Error ? error.message : "UnknownError");
          }
        }
        delete this.snapshot.seats[number];
        changed = true;
      }
    }
    if (changed) {
      this.snapshot.revision++;
      await this.persist();
      if (shouldBroadcast) this.broadcast({ type: "seat_updated", ...this.publicSnapshot() });
    }
    await this.scheduleExpiry();
  }

  private async scheduleExpiry(): Promise<void> {
    const expiries = Object.values(this.snapshot.seats).map((seat) => seat.expiresAt);
    if (expiries.length === 0) {
      await this.state.storage.deleteAlarm();
      return;
    }
    await this.state.storage.setAlarm(Math.min(...expiries));
  }

  async alarm(): Promise<void> {
    await this.ready;
    await this.enqueue(async () => this.expireSeats(true));
  }

  private async persist(): Promise<void> {
    await this.state.storage.put("room-seat-snapshot", this.snapshot);
  }

  private publicSnapshot(): { seats: RoomSeatMember[]; revision: number } {
    return {
      seats: Object.values(this.snapshot.seats).sort((a, b) => a.seatNumber - b.seatNumber),
      revision: this.snapshot.revision
    };
  }

  private send(socket: WebSocket, payload: Record<string, unknown>): void {
    if (socket.readyState !== WebSocket.OPEN) return;
    try { socket.send(JSON.stringify(payload)); }
    catch { this.sockets.delete(socket); }
  }

  private broadcast(payload: Record<string, unknown>, except?: WebSocket): void {
    const encoded = JSON.stringify(payload);
    for (const socket of this.sockets.keys()) {
      if (socket === except || socket.readyState !== WebSocket.OPEN) continue;
      try { socket.send(encoded); }
      catch { this.sockets.delete(socket); }
    }
  }
}
