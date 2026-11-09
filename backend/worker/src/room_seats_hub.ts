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

export class RoomSeatsHub {
  private snapshot: RoomSeatSnapshot = structuredClone(EMPTY_SNAPSHOT);
  private readonly sockets = new Map<WebSocket, SocketIdentity>();
  private mutationQueue: Promise<void> = Promise.resolve();
  private readonly ready: Promise<void>;

  constructor(private readonly state: DurableObjectState, private readonly env: unknown) {
    this.ready = this.state.blockConcurrencyWhile(async () => {
      this.snapshot = (await this.state.storage.get<RoomSeatSnapshot>("room-seat-snapshot")) ?? structuredClone(EMPTY_SNAPSHOT);
      if (!this.snapshot.seats) this.snapshot.seats = {};
      if (!this.snapshot.versions) this.snapshot.versions = {};
      if (!Number.isFinite(this.snapshot.revision)) this.snapshot.revision = 0;
      if (typeof this.snapshot.voiceEnabled !== "boolean") this.snapshot.voiceEnabled = true;
      await this.expireSeats(false);
    });
  }

  async fetch(request: Request): Promise<Response> {
    await this.ready;
    const url = new URL(request.url);

    if (url.pathname === "/snapshot" && request.method === "GET") {
      return Response.json(this.publicSnapshot());
    }

    if (url.pathname === "/clear" && request.method === "POST") {
      await this.enqueue(async () => {
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
      if ((to !== null && (!Number.isInteger(to) || to < 1 || to > 8)) || !Number.isSafeInteger(version) || version < 1) {
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

    if (url.pathname === "/enable" && request.method === "POST") {
      await this.enqueue(async () => {
        this.snapshot.voiceEnabled = true;
        this.snapshot.revision++;
        await this.persist();
      });
      return Response.json({ ok: true, ...this.publicSnapshot() });
    }

    if (url.pathname === "/remove-user" && request.method === "POST") {
      const targetUserId = request.headers.get("x-target-user-id") ?? "";
      if (!targetUserId) return Response.json({ error: "target_required" }, { status: 400 });
      await this.enqueue(async () => {
        const current = Object.values(this.snapshot.seats).find((seat) => seat.userId === targetUserId);
        if (current) {
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
    if ((from !== null && (!Number.isInteger(from) || from < 1 || from > 8)) ||
        (to !== null && (!Number.isInteger(to) || to < 1 || to > 8)) ||
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
    return { type: "ack", ok: true, code: "moved", version, from: current?.seatNumber ?? null, mySeat: to, ...this.publicSnapshot() };
  }

  private async expireSeats(shouldBroadcast: boolean): Promise<void> {
    const now = Date.now();
    let changed = false;
    for (const [number, member] of Object.entries(this.snapshot.seats)) {
      if (member.expiresAt <= now) {
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
