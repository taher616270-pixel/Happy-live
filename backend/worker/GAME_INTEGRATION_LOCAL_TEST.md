# Unified Games Integration — Local Test Run

This runbook is for testing the unified in-app games integration without deploying a Worker or applying migrations to the production D1 database.

## Safety boundary

- Stay on branch `feat/unified-games-integration-phases-4-10`.
- Do not merge this branch into `main` for this test.
- Do not run `npm run deploy`: the existing deploy script applies migrations with `--remote` and deploys the production Worker.
- Do not run any Wrangler command with `--remote`.
- Do not build Android for this test.
- The existing Food Wheel implementation is outside this integration test and must remain unchanged.

## Worker checks

Use Node.js 22.5 or newer (Node 22 LTS recommended), then from `backend/worker`:

```bash
npm ci
npm run typecheck
npm run test:games
```

The game tests use Node's built-in SQLite test database and do not connect to Cloudflare production.

## Local D1 and Worker

From `backend/worker`:

```bash
npm run db:games:local
npm run dev:local
```

These commands apply pending migrations to Wrangler's local D1 database and start a local Worker. They do not use the production D1 database. Keep any test users, game registry records, and wallet balances in this local database.

## Run the web app against the local Worker

In a second terminal, from `frontend`:

```bash
flutter run -d chrome --web-port 8080 --dart-define=HAPPY_LIVE_API_BASE=http://127.0.0.1:8787/api/v1
```

The API override is compile-time only. Normal builds keep the production API URL unless this define is explicitly supplied. Port 8080 is already included in the Worker local CORS allowlist. Create a fresh local test account; the local D1 database is separate from production and does not contain production users or balances.

If the local admin bootstrap flow requires it, put a locally chosen `ADMIN_SETUP_TOKEN` in `backend/worker/.dev.vars` before starting Wrangler. Never copy production secrets into this file.

## Test sequence

1. Sign in to the local Happy Live web app using a local test account.
2. In the admin panel, create a test game with an HTTPS game URL that you control and activate it.
3. Configure the game's economy limits and generate its server key. Store the key only in the trusted game backend's local secret/configuration; never put it in browser code.
4. Launch the game from the app. Confirm the game receives only its short-lived player session and public player profile.
5. Check wallet reads, create a round, place bets, and verify each accepted bet deducts the wallet exactly once.
6. Retry the same idempotency key with the same payload; it must not deduct again. Retry it with a different stake or selection; it must return an idempotency conflict.
7. Settle a round through the trusted server endpoint and confirm the payout, wallet balance, and game ledger agree.
8. Cancel a separate round and confirm accepted stakes are refunded exactly once.
9. Try insufficient balance, disabled economy, revoked/expired app session, invalid server key, and a request from an unregistered game origin.
10. Confirm the game cannot settle a round from browser JavaScript and cannot read another player's wallet or round history.

## Current boundary

A successful local test is required before treating the integration as accepted. This runbook does not claim that the integration has already passed end-to-end testing. Production deployment, production D1 migrations, and Android builds are intentionally not part of this test.
