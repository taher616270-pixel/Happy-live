import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";

const root = new URL("../", import.meta.url);
const migration = await readFile(new URL("migrations/0045_game_economy_foundation.sql", root), "utf8");

function createDatabase({ balance = 1000, maxBets = 6, maxTotal = 6000, maxBet = 1000, multiplier = 100000 } = {}) {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    PRAGMA foreign_keys = ON;
    CREATE TABLE users (id TEXT PRIMARY KEY);
    CREATE TABLE game_registry (id TEXT PRIMARY KEY);
    CREATE TABLE user_wallets (
      user_id TEXT PRIMARY KEY REFERENCES users(id),
      balance INTEGER NOT NULL DEFAULT 0 CHECK(balance >= 0),
      updated_at TEXT NOT NULL
    );
  `);
  db.exec(migration);
  db.prepare("INSERT INTO users (id) VALUES (?)").run("user-1");
  db.prepare("INSERT INTO game_registry (id) VALUES (?)").run("game-1");
  db.prepare("INSERT INTO user_wallets (user_id, balance, updated_at) VALUES (?, ?, ?)").run("user-1", balance, "2026-11-14T00:00:00.000Z");
  db.prepare("INSERT INTO game_economy_settings (game_id, enabled, min_bet, max_bet, max_bets_per_round, max_total_bet, max_payout_multiplier_bp, updated_at) VALUES (?, 1, 10, ?, ?, ?, ?, ?)").run("game-1", maxBet, maxBets, maxTotal, multiplier, "2026-11-14T00:00:00.000Z");
  return db;
}

function batch(db, statements) {
  db.exec("BEGIN");
  try {
    for (const [sql, params] of statements) db.prepare(sql).run(...params);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

function createRound(db, id, idempotencyKey) {
  db.prepare("INSERT INTO game_rounds (id, game_id, user_id, idempotency_key, status, total_stake, total_payout, created_at) VALUES (?, 'game-1', 'user-1', ?, 'open', 0, 0, ?)").run(id, idempotencyKey, "2026-11-14T00:00:00.000Z");
}

function placeBet(db, { id, roundId, key, stake }) {
  const now = "2026-11-14T00:00:01.000Z";
  batch(db, [
    [`INSERT OR IGNORE INTO game_bets (id, round_id, game_id, user_id, idempotency_key, stake, selection_json, payout, status, created_at)
      SELECT ?, ?, ?, ?, ?, ?, '{}', 0, 'processing', ?
      WHERE EXISTS (
        SELECT 1 FROM game_rounds r JOIN game_economy_settings s ON s.game_id = r.game_id
        WHERE r.id = ? AND r.status = 'open' AND r.game_id = ? AND r.user_id = ?
          AND s.enabled = 1 AND ? BETWEEN s.min_bet AND s.max_bet
          AND (SELECT COUNT(*) FROM game_bets b WHERE b.round_id = r.id AND b.status IN ('accepted','settled')) < s.max_bets_per_round
          AND r.total_stake + ? <= s.max_total_bet
      ) AND EXISTS (SELECT 1 FROM user_wallets w WHERE w.user_id = ? AND w.balance >= ?)`,
      [id, roundId, "game-1", "user-1", key, stake, now, roundId, "game-1", "user-1", stake, stake, "user-1", stake]],
    ["UPDATE user_wallets SET balance = balance - ?, updated_at = ? WHERE user_id = ? AND balance >= ? AND changes() = 1", [stake, now, "user-1", stake]],
    ["UPDATE game_bets SET status = 'accepted' WHERE id = ? AND status = 'processing' AND changes() = 1", [id]],
    ["UPDATE game_rounds SET total_stake = total_stake + ? WHERE id = ? AND status = 'open' AND changes() = 1", [stake, roundId]],
    ["INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, b.id, b.user_id, 'bet_debit', -b.stake, w.balance, ?, ? FROM game_bets b JOIN user_wallets w ON w.user_id = b.user_id WHERE b.id = ? AND b.status = 'accepted' AND changes() = 1", ["ledger-" + id, "game-1", roundId, "bet:" + id, now, id]],
    ["DELETE FROM game_bets WHERE id = ? AND status = 'processing'", [id]]
  ]);
  return db.prepare("SELECT id, status, stake FROM game_bets WHERE round_id = ? AND idempotency_key = ? LIMIT 1").get(roundId, key) ?? null;
}

test("game economy migration creates isolated tables without changing the legacy wallet schema", () => {
  const db = createDatabase();
  try {
    const tables = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all().map(row => row.name);
    for (const name of ["game_economy_settings", "game_rounds", "game_bets", "game_wallet_ledger", "game_server_keys"]) {
      assert.ok(tables.includes(name), "missing table " + name);
    }
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_wallet_ledger").get().n, 0);
  } finally {
    db.close();
  }
});

test("wager debit is atomic, bounded, and idempotent", () => {
  const db = createDatabase({ balance: 1000, maxBets: 2, maxTotal: 500, maxBet: 500 });
  try {
    createRound(db, "round-1", "round-key-0001");
    const first = placeBet(db, { id: "bet-1", roundId: "round-1", key: "bet-key-0001", stake: 400 });
    assert.equal(first?.status, "accepted");
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 600);

    const duplicate = placeBet(db, { id: "bet-duplicate", roundId: "round-1", key: "bet-key-0001", stake: 400 });
    assert.equal(duplicate?.id, "bet-1");
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 600);

    const overLimit = placeBet(db, { id: "bet-2", roundId: "round-1", key: "bet-key-0002", stake: 200 });
    assert.equal(overLimit, null);
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 600);
    assert.equal(db.prepare("SELECT total_stake FROM game_rounds WHERE id = 'round-1'").get().total_stake, 400);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_wallet_ledger WHERE entry_type = 'bet_debit'").get().n, 1);
  } finally {
    db.close();
  }
});

test("trusted settlement credits the wallet once and records the payout", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-2", "round-key-0002");
    placeBet(db, { id: "bet-3", roundId: "round-2", key: "bet-key-0003", stake: 400 });
    const now = "2026-11-14T00:00:02.000Z";
    const settlementId = "settlement-1";
    batch(db, [
      ["UPDATE game_rounds SET status = 'settling', total_payout = ?, result_json = ?, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open'", [800, '{"winner":true}', now, settlementId, "round-2"]],
      ["UPDATE game_bets SET status = 'settled', payout = ?, settled_at = ? WHERE id = ? AND round_id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", [800, now, "bet-3", "round-2", "round-2", settlementId]],
      ["UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", [800, now, "user-1", "round-2", settlementId]],
      ["INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, NULL, ?, 'payout_credit', ?, w.balance, ?, ? FROM user_wallets w WHERE w.user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", ["ledger-payout", "game-1", "round-2", "user-1", 800, "payout:round-2", now, "user-1", "round-2", settlementId]],
      ["UPDATE game_rounds SET status = 'settled' WHERE id = ? AND status = 'settling' AND settlement_id = ?", ["round-2", settlementId]]
    ]);
    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = 'round-2'").get().status, "settled");
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 1400);
    assert.equal(db.prepare("SELECT amount FROM game_wallet_ledger WHERE entry_type = 'payout_credit'").get().amount, 800);

    const retryId = "settlement-retry";
    db.prepare("UPDATE game_rounds SET status = 'settling', settlement_id = ? WHERE id = ? AND status = 'open'").run(retryId, "round-2");
    db.prepare("UPDATE user_wallets SET balance = balance + 800 WHERE user_id = 'user-1' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = 'round-2' AND status = 'settling' AND settlement_id = ?)").run(retryId);
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 1400);
  } finally {
    db.close();
  }
});

test("aborted rounds refund exactly their accepted stakes once", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-3", "round-key-0003");
    placeBet(db, { id: "bet-4", roundId: "round-3", key: "bet-key-0004", stake: 300 });
    const now = "2026-11-14T00:00:03.000Z";
    const settlementId = "cancel-1";
    batch(db, [
      ["UPDATE game_rounds SET status = 'settling', total_payout = 0, result_json = ?, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open'", ['{"cancelled":true}', now, settlementId, "round-3"]],
      ["UPDATE game_bets SET status = 'cancelled', payout = 0, settled_at = ? WHERE id = ? AND round_id = ? AND status = 'accepted' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", [now, "bet-4", "round-3", "round-3", settlementId]],
      ["UPDATE user_wallets SET balance = balance + ?, updated_at = ? WHERE user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", [300, now, "user-1", "round-3", settlementId]],
      ["INSERT INTO game_wallet_ledger (id, game_id, round_id, bet_id, user_id, entry_type, amount, balance_after, idempotency_key, created_at) SELECT ?, ?, ?, NULL, ?, 'refund_credit', ?, w.balance, ?, ? FROM user_wallets w WHERE w.user_id = ? AND EXISTS (SELECT 1 FROM game_rounds WHERE id = ? AND status = 'settling' AND settlement_id = ?)", ["ledger-refund", "game-1", "round-3", "user-1", 300, "refund:round-3", now, "user-1", "round-3", settlementId]],
      ["UPDATE game_rounds SET status = 'cancelled' WHERE id = ? AND status = 'settling' AND settlement_id = ?", ["round-3", settlementId]]
    ]);
    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = 'round-3'").get().status, "cancelled");
    assert.equal(db.prepare("SELECT status FROM game_bets WHERE id = 'bet-4'").get().status, "cancelled");
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 1000);
    assert.equal(db.prepare("SELECT entry_type, amount FROM game_wallet_ledger WHERE id = 'ledger-refund'").get().entry_type, "refund_credit");
  } finally {
    db.close();
  }
});


test("per-round wager count and maximum single bet are enforced in SQL", () => {
  const db = createDatabase({ balance: 2000, maxBets: 1, maxTotal: 6000, maxBet: 500 });
  try {
    createRound(db, "round-4", "round-key-0004");
    assert.equal(placeBet(db, { id: "bet-5", roundId: "round-4", key: "bet-key-0005", stake: 300 })?.status, "accepted");
    assert.equal(placeBet(db, { id: "bet-6", roundId: "round-4", key: "bet-key-0006", stake: 100 }), null);
    assert.equal(placeBet(db, { id: "bet-7", roundId: "round-4", key: "bet-key-0007", stake: 600 }), null);
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 1700);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_bets WHERE round_id = 'round-4'").get().n, 1);
  } finally {
    db.close();
  }
});


test("settlement refuses a stale wager snapshot when a concurrent bet lands before its atomic claim", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-race-settle", "round-race-settle-key");
    placeBet(db, { id: "bet-race-a", roundId: "round-race-settle", key: "bet-race-key-a", stake: 300 });
    const staleStake = db.prepare("SELECT total_stake FROM game_rounds WHERE id = ?").get("round-race-settle").total_stake;
    const staleCount = db.prepare("SELECT COUNT(*) AS n FROM game_bets WHERE round_id = ? AND status = 'accepted'").get("round-race-settle").n;
    placeBet(db, { id: "bet-race-b", roundId: "round-race-settle", key: "bet-race-key-b", stake: 100 });

    const settlementId = "stale-settlement";
    batch(db, [
      ["UPDATE game_rounds SET status = 'settling', total_payout = 500, result_json = '{}', settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND total_stake = ? AND (SELECT COALESCE(SUM(stake), 0) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (SELECT COUNT(*) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ?", ["2026-11-14T00:00:04.000Z", settlementId, "round-race-settle", staleStake, "round-race-settle", staleStake, "round-race-settle", staleCount]],
      ["UPDATE user_wallets SET balance = balance + 500 WHERE user_id = 'user-1' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = 'round-race-settle' AND status = 'settling' AND settlement_id = ?)", [settlementId]]
    ]);

    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = 'round-race-settle'").get().status, "open");
    assert.equal(db.prepare("SELECT total_stake FROM game_rounds WHERE id = 'round-race-settle'").get().total_stake, 400);
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 600);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_bets WHERE round_id = 'round-race-settle' AND status = 'accepted'").get().n, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_wallet_ledger WHERE entry_type = 'payout_credit'").get().n, 0);
  } finally {
    db.close();
  }
});

test("cancellation refuses a stale wager snapshot instead of partially refunding a round", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-race-cancel", "round-race-cancel-key");
    placeBet(db, { id: "bet-cancel-a", roundId: "round-race-cancel", key: "bet-cancel-key-a", stake: 300 });
    const staleStake = db.prepare("SELECT total_stake FROM game_rounds WHERE id = ?").get("round-race-cancel").total_stake;
    const staleCount = db.prepare("SELECT COUNT(*) AS n FROM game_bets WHERE round_id = ? AND status = 'accepted'").get("round-race-cancel").n;
    placeBet(db, { id: "bet-cancel-b", roundId: "round-race-cancel", key: "bet-cancel-key-b", stake: 100 });

    const cancellationId = "stale-cancellation";
    batch(db, [
      ["UPDATE game_rounds SET status = 'settling', total_payout = 0, result_json = '{\"cancelled\":true}', settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND total_stake = ? AND (SELECT COALESCE(SUM(stake), 0) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ? AND (SELECT COUNT(*) FROM game_bets WHERE round_id = ? AND status = 'accepted') = ?", ["2026-11-14T00:00:05.000Z", cancellationId, "round-race-cancel", staleStake, "round-race-cancel", staleStake, "round-race-cancel", staleCount]],
      ["UPDATE user_wallets SET balance = balance + 300 WHERE user_id = 'user-1' AND EXISTS (SELECT 1 FROM game_rounds WHERE id = 'round-race-cancel' AND status = 'settling' AND settlement_id = ?)", [cancellationId]]
    ]);

    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = 'round-race-cancel'").get().status, "open");
    assert.equal(db.prepare("SELECT total_stake FROM game_rounds WHERE id = 'round-race-cancel'").get().total_stake, 400);
    assert.equal(db.prepare("SELECT balance FROM user_wallets WHERE user_id = 'user-1'").get().balance, 600);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_bets WHERE round_id = 'round-race-cancel' AND status = 'accepted'").get().n, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM game_wallet_ledger WHERE entry_type = 'refund_credit'").get().n, 0);
  } finally {
    db.close();
  }
});


test("settlement refuses to claim a round when a positive payout has no wallet row", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-no-wallet-settle", "round-no-wallet-settle-key");
    placeBet(db, { id: "bet-no-wallet-settle", roundId: "round-no-wallet-settle", key: "bet-no-wallet-settle-key", stake: 300 });
    db.prepare("DELETE FROM user_wallets WHERE user_id = 'user-1'").run();
    db.prepare("UPDATE game_rounds SET status = 'settling', total_payout = 100, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND (100 = 0 OR EXISTS (SELECT 1 FROM user_wallets WHERE user_id = 'user-1'))").run("2026-11-14T00:00:06.000Z", "no-wallet-settle", "round-no-wallet-settle");
    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = ?").get("round-no-wallet-settle").status, "open");
    assert.equal(db.prepare("SELECT status FROM game_bets WHERE id = ?").get("bet-no-wallet-settle").status, "accepted");
  } finally { db.close(); }
});

test("cancellation refuses to claim a refund round when its wallet row is missing", () => {
  const db = createDatabase({ balance: 1000 });
  try {
    createRound(db, "round-no-wallet-cancel", "round-no-wallet-cancel-key");
    placeBet(db, { id: "bet-no-wallet-cancel", roundId: "round-no-wallet-cancel", key: "bet-no-wallet-cancel-key", stake: 300 });
    db.prepare("DELETE FROM user_wallets WHERE user_id = 'user-1'").run();
    db.prepare("UPDATE game_rounds SET status = 'settling', total_payout = 0, settled_at = ?, settlement_id = ? WHERE id = ? AND status = 'open' AND (300 = 0 OR EXISTS (SELECT 1 FROM user_wallets WHERE user_id = 'user-1'))").run("2026-11-14T00:00:07.000Z", "no-wallet-cancel", "round-no-wallet-cancel");
    assert.equal(db.prepare("SELECT status FROM game_rounds WHERE id = ?").get("round-no-wallet-cancel").status, "open");
    assert.equal(db.prepare("SELECT status FROM game_bets WHERE id = ?").get("bet-no-wallet-cancel").status, "accepted");
  } finally { db.close(); }
});
