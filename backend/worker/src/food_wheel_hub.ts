import { DurableObject } from "cloudflare:workers";

interface FoodWheelEnv {
  DB?: D1Database;
}

interface FoodWheelRound {
  id: string;
  roundNo: number;
  status: "betting" | "result" | "settled";
  startedAt: string;
  bettingEndsAt: string;
  endsAt: string;
  resultSlot: number | null;
}

const MULTIPLIERS = [45, 5, 15, 5, 25, 5, 10, 5] as const;
const BETTING_MS = 20_000;
// 20s betting + 5s server-result spin + popup countdown 4,3,2,1.
// The next round starts exactly when the popup reaches 1s.
const ROUND_MS = 28_000;
const MAX_CATCH_UP_ROUNDS = 100;

function chooseResultSlot(): number {
  const weights = MULTIPLIERS.map((value) => 1 / value);
  const total = weights.reduce((sum, value) => sum + value, 0);
  const random = crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296 * total;
  let cursor = 0;
  for (let index = 0; index < weights.length; index++) {
    cursor += weights[index];
    if (random < cursor) return index;
  }
  return weights.length - 1;
}

export class FoodWheelRoundsHub extends DurableObject<FoodWheelEnv> {
  private readonly db?: D1Database;

  constructor(ctx: DurableObjectState, env: FoodWheelEnv) {
    super(ctx, env);
    this.db = env.DB;
  }

  private requireDb(): D1Database {
    if (!this.db) throw new Error("food_wheel_database_unavailable");
    return this.db;
  }

  private async currentRound(): Promise<FoodWheelRound | null> {
    const db = this.requireDb();
    return db.prepare(
      "SELECT id, round_no AS roundNo, status, started_at AS startedAt, betting_ends_at AS bettingEndsAt, ends_at AS endsAt, result_slot AS resultSlot FROM food_wheel_rounds WHERE status IN ('betting', 'result') ORDER BY round_no DESC LIMIT 1"
    ).first<FoodWheelRound>();
  }

  private async createRound(startMs: number): Promise<FoodWheelRound> {
    const db = this.requireDb();
    const startedAt = new Date(startMs).toISOString();
    const bettingEndsAt = new Date(startMs + BETTING_MS).toISOString();
    const endsAt = new Date(startMs + ROUND_MS).toISOString();
    try {
      await db.prepare(
        "INSERT INTO food_wheel_rounds (id, status, started_at, betting_ends_at, ends_at, created_at) VALUES (?, 'betting', ?, ?, ?, ?)"
      ).bind(crypto.randomUUID(), startedAt, bettingEndsAt, endsAt, new Date().toISOString()).run();
    } catch (error) {
      const raced = await this.currentRound();
      if (raced) return raced;
      throw error;
    }
    const created = await this.currentRound();
    if (!created) throw new Error("food_wheel_round_create_failed");
    return created;
  }

  private async ensureRound(): Promise<FoodWheelRound> {
    const db = this.requireDb();
    const active = await this.currentRound();
    if (active) return active;

    const last = await db.prepare(
      "SELECT ends_at AS endsAt FROM food_wheel_rounds ORDER BY round_no DESC LIMIT 1"
    ).first<{ endsAt: string }>();
    const startMs = last ? Date.parse(last.endsAt) : Date.now();
    return this.createRound(Number.isFinite(startMs) ? startMs : Date.now());
  }

  private async scheduleRound(round: FoodWheelRound): Promise<void> {
    const dueAt = round.status === "betting"
      ? Date.parse(round.bettingEndsAt)
      : Date.parse(round.endsAt);
    await this.ctx.storage.setAlarm(Math.max(Date.now() + 1, dueAt));
  }

  private async chooseAndPublishResult(round: FoodWheelRound): Promise<void> {
    const db = this.requireDb();
    const resultSlot = chooseResultSlot();
    const now = new Date();
    // Anchor the result phase to the exact betting deadline so a delayed
    // alarm cannot steal seconds from the five-second result countdown.
    const chosenAt = round.bettingEndsAt;
    const resultEndsAt = new Date(Date.parse(round.bettingEndsAt) + 8_000).toISOString();
    // The chosen slot and all winning payouts commit together. If an alarm is
    // retried or races an ensure request, the first persisted result always wins.
    await db.batch([
      db.prepare(
        "UPDATE food_wheel_rounds SET status = 'result', result_slot = ?, result_chosen_at = ?, ends_at = ? WHERE id = ? AND status = 'betting'"
      ).bind(resultSlot, chosenAt, resultEndsAt, round.id),
      db.prepare(
        "UPDATE food_wheel_bets SET payout = CASE slot WHEN 0 THEN stake * 45 WHEN 1 THEN stake * 5 WHEN 2 THEN stake * 15 WHEN 3 THEN stake * 5 WHEN 4 THEN stake * 25 WHEN 5 THEN stake * 5 WHEN 6 THEN stake * 10 ELSE stake * 5 END WHERE round_id = ? AND status = 'accepted' AND slot = (SELECT result_slot FROM food_wheel_rounds WHERE id = ? AND status = 'result')"
      ).bind(round.id, round.id),
      db.prepare(
        "UPDATE game_bets SET payout = COALESCE((SELECT fb.payout FROM food_wheel_bets fb WHERE fb.game_bet_id = game_bets.id), 0) WHERE status = 'accepted' AND id IN (SELECT game_bet_id FROM food_wheel_bets WHERE round_id = ? AND status = 'accepted')"
      ).bind(round.id)
    ]);
    const persisted = await db.prepare(
      "SELECT result_slot AS resultSlot FROM food_wheel_rounds WHERE id = ? AND status = 'result' LIMIT 1"
    ).bind(round.id).first<{ resultSlot: number | null }>();
    if (persisted?.resultSlot == null) throw new Error("food_wheel_result_not_persisted");
  }

  private async settleRound(round: FoodWheelRound): Promise<void> {
    const db = this.requireDb();
    const bets = await db.prepare(
      "SELECT id, game_bet_id AS gameBetId, game_round_id AS gameRoundId, user_id AS userId, payout FROM food_wheel_bets WHERE round_id = ? AND status = 'accepted' ORDER BY created_at, id"
    ).bind(round.id).all<{
      id: string;
      gameBetId: string;
      gameRoundId: string;
      userId: string;
      payout: number;
    }>();
    const rows = bets.results ?? [];
    const winningUsers = [...new Set(rows.filter((bet) => bet.payout > 0).map((bet) => bet.userId))];
    if (winningUsers.length > 0) {
      const placeholders = winningUsers.map(() => "?").join(",");
      const wallets = await db.prepare(
        "SELECT user_id AS userId FROM user_wallets WHERE user_id IN (" + placeholders + ")"
      ).bind(...winningUsers).all<{ userId: string }>();
      const found = new Set((wallets.results ?? []).map((row) => row.userId));
      if (winningUsers.some((userId) => !found.has(userId))) {
        throw new Error("food_wheel_winner_wallet_missing");
      }
    }

    const now = new Date().toISOString();
    for (let offset = 0; offset < rows.length; offset += 20) {
      const chunk = rows.slice(offset, offset + 20);
      const statements: D1PreparedStatement[] = [];
      for (const bet of chunk) {
        const payout = Math.max(0, Math.floor(Number(bet.payout) || 0));
        const ledgerKey = "food-wheel-payout:" + round.id + ":" + bet.gameBetId;
        statements.push(
          db.prepare(
            "UPDATE game_bets SET status = 'settled', payout = ?, settled_at = ? WHERE id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM food_wheel_rounds WHERE id = ? AND status = 'result')"
          ).bind(payout, now, bet.gameBetId, round.id),
          db.prepare(
            "UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ? AND ? > 0 AND EXISTS (SELECT 1 FROM game_bets WHERE id = ? AND status = 'settled' AND payout = ?) AND NOT EXISTS (SELECT 1 FROM game_wallet_ledger WHERE idempotency_key = ?)"
          ).bind(payout, now, bet.userId, payout, bet.gameBetId, payout, ledgerKey),
          db.prepare(
            "INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, ?, ?, 'payout_credit', ?, w.balance, ?, ? FROM user_wallets w JOIN game_bets b ON b.id = ? WHERE w.user_id = ? AND b.status = 'settled' AND b.payout = ? AND ? > 0 AND NOT EXISTS (SELECT 1 FROM game_wallet_ledger WHERE idempotency_key = ?)"
          ).bind(crypto.randomUUID(), "4bcb9b74-3c87-4d9e-9f26-2b61c9a5f841", bet.gameRoundId, bet.gameBetId, bet.userId, payout, ledgerKey, now, bet.gameBetId, bet.userId, payout, payout, ledgerKey),
          db.prepare(
            "UPDATE food_wheel_bets SET status = 'settled', settled_at = ? WHERE id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_bets WHERE id = ? AND status = 'settled')"
          ).bind(now, bet.id, bet.gameBetId)
        );
      }
      if (statements.length > 0) await db.batch(statements);
    }

    const financialRounds = await db.prepare(
      "SELECT DISTINCT game_round_id AS gameRoundId FROM food_wheel_bets WHERE round_id = ?"
    ).bind(round.id).all<{ gameRoundId: string }>();
    const resultJson = JSON.stringify({ result_slot: round.resultSlot, global_round_id: round.id });
    for (const item of financialRounds.results ?? []) {
      await db.prepare(
        "UPDATE game_rounds SET status = 'settled', total_payout = (SELECT COALESCE(SUM(payout), 0) FROM game_bets WHERE round_id = ? AND status = 'settled'), result_json = ?, settled_at = ? WHERE id = ? AND status = 'open'"
      ).bind(item.gameRoundId, resultJson, now, item.gameRoundId).run();
    }

    await db.prepare(
      "UPDATE food_wheel_rounds SET status = 'settled', settled_at = ? WHERE id = ? AND status = 'result'"
    ).bind(now, round.id).run();
  }

  private async advance(): Promise<void> {
    let round = await this.ensureRound();
    for (let step = 0; step < MAX_CATCH_UP_ROUNDS; step++) {
      const now = Date.now();
      if (round.status === "betting") {
        const closesAt = Date.parse(round.bettingEndsAt);
        if (now < closesAt) {
          await this.scheduleRound(round);
          return;
        }
        await this.chooseAndPublishResult(round);
        const updated = await this.currentRound();
        if (!updated) throw new Error("food_wheel_result_round_missing");
        round = updated;
        continue;
      }

      if (round.status === "result") {
        const endsAt = Date.parse(round.endsAt);
        if (now < endsAt) {
          await this.scheduleRound(round);
          return;
        }
        await this.settleRound(round);
        round = await this.createRound(endsAt);
        continue;
      }
    }
    await this.ctx.storage.setAlarm(Date.now() + 1_000);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/ensure") {
      return Response.json({ error: "not_found" }, { status: 404 });
    }
    try {
      await this.advance();
      const round = await this.currentRound();
      const alarmAt = await this.ctx.storage.getAlarm();
      return Response.json({
        ok: true,
        roundId: round?.roundNo ?? null,
        phase: round?.status ?? null,
        alarmAt
      });
    } catch (error) {
      console.error("[food-wheel.ensure]", error instanceof Error ? error.message : "UnknownError");
      return Response.json({ error: "food_wheel_scheduler_unavailable" }, { status: 503 });
    }
  }

  async alarm(): Promise<void> {
    try {
      await this.advance();
    } catch (error) {
      console.error("[food-wheel.alarm]", error instanceof Error ? error.message : "UnknownError");
      await this.ctx.storage.setAlarm(Date.now() + 5_000);
    }
  }
}
