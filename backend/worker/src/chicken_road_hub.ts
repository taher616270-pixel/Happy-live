import { DurableObject } from "cloudflare:workers";
import { balance as walletBalance, profile as walletProfile, debitStatement, creditStatement } from "../../../games/chicken-road/server/wallet.js";

interface ChickenRoadEnv { DB?: D1Database; }
type Diff = "easy" | "medium" | "hard";
type ActiveRound = {
  id: string; amount: number; diff: Diff; step: number; crashStep: number;
  seed: string; commit: string; lastStepAt: number;
};
const GAME_ID = "f21d2c7a-8f1b-4d72-9a63-5c8f7e1d4b90";
const RTP = 0.97, MAX_STEPS = 25, STEP_MIN_MS = 300, MIN_BET = 100, MAX_BET = 1_000_000;
const DEATH: Record<Diff, number> = { easy: 0.06, medium: 0.14, hard: 0.22 };
const encoder = new TextEncoder();
const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
async function sha(value: string): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
}
function multiplier(diff: Diff, step: number): number {
  if (step <= 0) return 1;
  const chance = Math.pow(1 - DEATH[diff], step);
  return Math.floor((RTP / chance) * 100) / 100;
}
function crashAt(diff: Diff, u: number): number {
  const surv = 1 - DEATH[diff];
  for (let n = 1; n <= MAX_STEPS; n++) if (u >= Math.pow(surv, n)) return n;
  return Number.POSITIVE_INFINITY;
}
function seedHex(): string {
  return hex(crypto.getRandomValues(new Uint8Array(32)));
}
function unauthorizedChickenRoadSocket(): Response {
  const pair = new WebSocketPair();
  const client = pair[0], server = pair[1];
  server.accept();
  server.close(4001, "unauthorized");
  return new Response(null, { status: 101, webSocket: client });
}

function send(ws: WebSocket, t: string, data: unknown): void {
  try { ws.send(JSON.stringify({ t, data })); } catch { /* closed */ }
}

export class ChickenRoadHub extends DurableObject<ChickenRoadEnv> {
  private readonly db?: D1Database;
  private readonly sockets = new Set<WebSocket>();
  private readonly socketSessions = new WeakMap<WebSocket, string>();
  private queue: Promise<void> = Promise.resolve();
  private readonly playerId: string;

  constructor(ctx: DurableObjectState, env: ChickenRoadEnv) {
    super(ctx, env);
    this.db = env.DB;
    this.playerId = ctx.id.name ?? "";
  }
  private requireDb(): D1Database {
    if (!this.db) throw new Error("database_unavailable");
    return this.db;
  }
  private async balance(): Promise<number> {
    return walletBalance(this.requireDb(), this.playerId);
  }
  private async activeRound(): Promise<ActiveRound | null> {
    return this.requireDb().prepare(
      "SELECT r.id, r.total_stake AS amount, s.difficulty AS diff, s.current_step AS step, s.crash_step AS crashStep, s.seed, s.commit_hash AS commit, s.last_step_at AS lastStepAt FROM game_rounds r INNER JOIN chicken_road_round_state s ON s.round_id = r.id WHERE r.game_id = ? AND r.user_id = ? AND r.status = 'open' ORDER BY r.created_at DESC LIMIT 1"
    ).bind(GAME_ID, this.playerId).first<ActiveRound>();
  }
  private async init(ws: WebSocket): Promise<void> {
    const [balance, game, player] = await Promise.all([
      this.balance(), this.activeRound(), walletProfile(this.requireDb(), this.playerId)
    ]);
    send(ws, "init", { playerId: player?.happyId ?? "", userCode: player?.happyId ?? "", player: player ?? null, balance, game: game ? {
      amount: game.amount, diff: game.diff, step: game.step, commit: game.commit
    } : null });
  }
  private async debit(amount: number, diff: Diff): Promise<ActiveRound | null> {
    const db = this.requireDb(), now = new Date().toISOString(), roundId = crypto.randomUUID();
    const betId = crypto.randomUUID(), seed = seedHex(), commit = await sha(seed);
    const entropy = await sha(seed + this.playerId);
    const u = Number.parseInt(entropy.slice(0, 13), 16) / 2 ** 52;
    const crashStep = crashAt(diff, u);
    const statements = [
      db.prepare("INSERT INTO game_rounds (id, game_id, user_id, idempotency_key, status, total_stake, total_payout, created_at) SELECT ?, ?, ?, ?, 'open', ?, 0, ? WHERE EXISTS (SELECT 1 FROM user_wallets WHERE user_id = ? AND balance >= ?) AND NOT EXISTS (SELECT 1 FROM game_rounds WHERE game_id = ? AND user_id = ? AND status = 'open')")
        .bind(roundId, GAME_ID, this.playerId, roundId, amount, now, this.playerId, amount, GAME_ID, this.playerId),
      debitStatement(db, this.playerId, amount, now, roundId),
      db.prepare("INSERT INTO game_bets (id, round_id, game_id, user_id, idempotency_key, stake, selection_json, payout, status, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, 0, 'accepted', ? WHERE EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'open')")
        .bind(betId, roundId, GAME_ID, this.playerId, betId, amount, JSON.stringify({ difficulty: diff }), now, roundId),
      db.prepare("INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, ?, ?, 'bet_debit', ?, w.balance, ?, ? FROM user_wallets w JOIN game_bets b ON b.round_id = ? AND b.id = ? WHERE w.user_id = ? AND b.status = 'accepted' AND NOT EXISTS (SELECT 1 FROM game_wallet_ledger WHERE idempotency_key = ?)")
        .bind(crypto.randomUUID(), GAME_ID, roundId, betId, this.playerId, -amount, "chicken-road-debit:" + roundId, now, roundId, betId, this.playerId, "chicken-road-debit:" + roundId),
      db.prepare("INSERT INTO chicken_road_round_state (round_id, difficulty, crash_step, seed, commit_hash, current_step, last_step_at, status) SELECT ?, ?, ?, ?, ?, 0, 0, 'active' WHERE EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'open')")
        .bind(roundId, diff, Number.isFinite(crashStep) ? crashStep : 26, seed, commit, roundId)
    ];
    await db.batch(statements);
    const round = await this.activeRound();
    return round;
  }
  private async settleDead(round: ActiveRound): Promise<void> {
    const db = this.requireDb(), now = new Date().toISOString();
    const result = JSON.stringify({ outcome: "dead", step: round.step, difficulty: round.diff, commit: round.commit, reveal: round.seed });
    await db.batch([
      db.prepare("UPDATE game_rounds SET status = 'settled', total_payout = 0, result_json = ?, settled_at = ? WHERE id = ? AND status = 'open'")
        .bind(result, now, round.id),
      db.prepare("UPDATE game_bets SET status = 'settled', payout = 0, settled_at = ? WHERE round_id = ? AND status = 'accepted'")
        .bind(now, round.id),
      db.prepare("UPDATE chicken_road_round_state SET status = 'dead', current_step = ?, last_step_at = ? WHERE round_id = ? AND status = 'active'")
        .bind(round.step, Date.now(), round.id)
    ]);
    sendAll(this.sockets, "dead", { step: round.step, amount: round.amount, reveal: round.seed, commit: round.commit });
    sendAll(this.sockets, "balance", { balance: await this.balance() });
  }
  private async cash(round: ActiveRound, auto = false): Promise<void> {
    const db = this.requireDb(), now = new Date().toISOString();
    const mult = multiplier(round.diff, round.step);
    const payout = Math.floor(round.amount * mult * 100) / 100;
    const result = JSON.stringify({ outcome: "cashed", step: round.step, difficulty: round.diff, mult, payout, commit: round.commit, reveal: round.seed });
    const settlementId = crypto.randomUUID();
    await db.batch([
      db.prepare("UPDATE game_rounds SET status = 'settling', total_payout = ?, result_json = ?, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open'")
        .bind(payout, result, now, settlementId, round.id),
      db.prepare("UPDATE game_bets SET status = 'settled', payout = ?, settled_at = ? WHERE round_id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)")
        .bind(payout, now, round.id, round.id, settlementId),
      creditStatement(db, this.playerId, payout, now, round.id, settlementId),
      db.prepare("INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, b.id, w.user_id, 'payout_credit', ?, w.balance, ?, ? FROM user_wallets w JOIN game_bets b ON b.round_id = ? AND b.status = 'settled' WHERE w.user_id = ? AND ? > 0 AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?) AND NOT EXISTS (SELECT 1 FROM game_wallet_ledger WHERE idempotency_key = ?)")
        .bind(crypto.randomUUID(), GAME_ID, round.id, payout, "chicken-road-payout:" + round.id, now, round.id, this.playerId, payout, round.id, settlementId, "chicken-road-payout:" + round.id),
      db.prepare("UPDATE game_rounds SET status = 'settled' WHERE id = ? AND status = 'settling' AND settlement_id = ?")
        .bind(round.id, settlementId),
      db.prepare("UPDATE chicken_road_round_state SET status = 'cashed', last_step_at = ? WHERE round_id = ? AND status = 'active'")
        .bind(Date.now(), round.id)
    ]);
    sendAll(this.sockets, "cashed", { step: round.step, mult, payout, reveal: round.seed, commit: round.commit, auto });
    sendAll(this.sockets, "balance", { balance: await this.balance() });
  }
  private async handle(ws: WebSocket, message: any): Promise<void> {
    if (!message || typeof message.t !== "string") return;
    if (message.t === "sync") return this.init(ws);
    if (message.t === "history") {
      const rows = await this.requireDb().prepare(
        "SELECT r.created_at AS ts, r.total_stake AS amount, r.total_payout AS payout, CASE WHEN r.total_payout > 0 THEN 1 ELSE 0 END AS win, s.difficulty AS diff, s.current_step AS step FROM game_rounds r LEFT JOIN chicken_road_round_state s ON s.round_id = r.id WHERE r.game_id = ? AND r.user_id = ? AND r.status = 'settled' ORDER BY r.created_at DESC LIMIT 30"
      ).bind(GAME_ID, this.playerId).all();
      return send(ws, "history", { rows: rows.results ?? [] });
    }
    if (message.t === "top") {
      // Saudi calendar day: 00:00 Asia/Riyadh (UTC+3) through the current instant.
      const nowMs = Date.now();
      const saudiNow = new Date(nowMs + 3 * 60 * 60 * 1000);
      const startUtcMs = Date.UTC(saudiNow.getUTCFullYear(), saudiNow.getUTCMonth(), saudiNow.getUTCDate()) - 3 * 60 * 60 * 1000;
      const start = new Date(startUtcMs).toISOString();
      const end = new Date(nowMs + 1).toISOString();
      const rows = await this.requireDb().prepare(
        "SELECT p.display_name AS name, p.avatar_key AS avatar, COALESCE(p.happy_id, '') AS userCode, SUM(r.total_payout - r.total_stake) AS coins FROM game_rounds r INNER JOIN users u ON u.id = r.user_id AND u.status = 'active' LEFT JOIN profiles p ON p.user_id = r.user_id WHERE r.game_id = ? AND r.status = 'settled' AND r.settled_at >= ? AND r.settled_at < ? GROUP BY r.user_id, p.display_name, p.avatar_key, p.happy_id HAVING SUM(r.total_payout - r.total_stake) > 0 ORDER BY coins DESC LIMIT 20"
      ).bind(GAME_ID, start, end).all();
      return send(ws, "top", { range: "today", resetsAt: new Date(startUtcMs + 24 * 60 * 60 * 1000).toISOString(), rows: (rows.results ?? []).map((row: any, index: number) => ({ ...row, rank: index + 1 })) });
    }
    if (message.t === "play") {
      const amount = Number(message.amount), diff = message.diff as Diff;
      if (!Number.isSafeInteger(amount) || amount < MIN_BET || amount > MAX_BET) return send(ws, "error", { message: "المبلغ من 100 إلى 1,000,000" });
      if (!(diff in DEATH)) return send(ws, "error", { message: "مستوى الصعوبة غير صحيح" });
      const existing = await this.activeRound();
      if (existing) return send(ws, "error", { message: "لديك لعبة جارية بالفعل" });
      const round = await this.debit(amount, diff);
      if (!round) return send(ws, "error", { message: "رصيد غير كافي" });
      sendAll(this.sockets, "started", { amount, diff, commit: round.commit });
      sendAll(this.sockets, "balance", { balance: await this.balance() });
      return;
    }
    if (message.t === "step") {
      const round = await this.activeRound();
      if (!round) return send(ws, "error", { message: "لا توجد لعبة جارية" });
      const now = Date.now();
      if (now - Number(round.lastStepAt) < STEP_MIN_MS) return;
      const nextStep = Number(round.step) + 1;
      await this.requireDb().prepare("UPDATE chicken_road_round_state SET current_step = ?, last_step_at = ? WHERE round_id = ? AND status = 'active' AND current_step = ?")
        .bind(nextStep, now, round.id, round.step).run();
      const updated = { ...round, step: nextStep, lastStepAt: now };
      if (nextStep >= Number(round.crashStep)) return this.settleDead(updated);
      if (nextStep >= MAX_STEPS) {
        sendAll(this.sockets, "step", { step: nextStep, mult: multiplier(round.diff, nextStep) });
        return this.cash(updated, true);
      }
      return sendAll(this.sockets, "step", { step: nextStep, mult: multiplier(round.diff, nextStep) });
    }
    if (message.t === "cash") {
      const round = await this.activeRound();
      if (!round || Number(round.step) < 1) return send(ws, "error", { message: "لا يمكن السحب الآن" });
      return this.cash(round, false);
    }
  }
  private async isSessionActive(sessionId: string): Promise<boolean> {
    if (!sessionId) return false;
    const now = new Date().toISOString();
    const row = await this.requireDb().prepare(
      "SELECT 1 AS active FROM game_sessions s INNER JOIN game_session_app_bindings b ON b.game_session_id = s.id INNER JOIN user_sessions app ON app.id = b.app_session_id AND app.user_id = s.user_id INNER JOIN users u ON u.id = s.user_id INNER JOIN game_registry g ON g.id = s.game_id INNER JOIN game_registry_lifecycle l ON l.game_id = g.id WHERE s.id = ? AND s.user_id = ? AND s.game_id = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND app.revoked_at IS NULL AND app.expires_at > ? AND u.status = 'active' AND g.enabled = 1 AND l.status = 'active' LIMIT 1"
    ).bind(sessionId, this.playerId, GAME_ID, now, now).first();
    return !!row;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/connect" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "not_found" }, { status: 404 });
    }
    const uid = request.headers.get("x-hl-user-id") ?? "";
    if (!uid || uid !== this.playerId) return unauthorizedChickenRoadSocket();
    const pair = new WebSocketPair(), client = pair[0], server = pair[1];
    server.accept();
    const gameSessionId = request.headers.get("x-hl-game-session-id") ?? "";
    if (!gameSessionId) return unauthorizedChickenRoadSocket();
    this.sockets.add(server);
    this.socketSessions.set(server, gameSessionId);
    server.addEventListener("close", () => { this.sockets.delete(server); this.socketSessions.delete(server); });
    server.addEventListener("error", () => { this.sockets.delete(server); this.socketSessions.delete(server); });
    server.addEventListener("message", (event) => {
      this.queue = this.queue.then(async () => {
        let message: any;
        try { message = JSON.parse(String(event.data)); } catch { return; }
        try {
          if (!(await this.isSessionActive(this.socketSessions.get(server) ?? ""))) {
            send(server, "unauthorized", { message: "انتهت جلسة Happy Live" });
            server.close(4001, "session_expired");
            this.sockets.delete(server);
            this.socketSessions.delete(server);
            return;
          }
          await this.handle(server, message);
        } catch (error) { send(server, "error", { message: "تعذر إكمال الطلب، حاول مجدداً" }); console.error("[chicken-road]", error instanceof Error ? error.message : "unknown"); }
      });
    });
    await this.init(server);
    return new Response(null, { status: 101, webSocket: client });
  }
}
function sendAll(sockets: Set<WebSocket>, type: string, data: unknown): void {
  for (const socket of sockets) send(socket, type, data);
}
