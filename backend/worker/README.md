# Happy Live Cloudflare API

The active backend is a TypeScript Cloudflare Worker. It is designed to keep the initial hosting footprint on Cloudflare's free allowances where possible.

## Components
- Workers: versioned JSON API.
- D1: relational SQLite database for accounts, moderation, room metadata and background records.
- Durable Objects: one `RoomSeatsHub` per room for the authoritative eight-seat state and realtime WebSocket moves; `RoomChatHub` remains dedicated to chat.
- R2: user-uploaded media and gift assets.
- Pages: Flutter Web and the separate admin frontend.

Free allowances and product limits can change. This architecture is intended to avoid a monthly VPS/database bill, not to promise unlimited free usage. Live audio is a separate provider and may incur charges beyond its current free quota.

## Current implementation
- `GET /api/v1`: API metadata.
- `GET /api/v1/health`: checks the D1 binding and reports media binding status.
- Authenticated room seat snapshots and compatibility seat mutations route through `ROOM_SEATS`; WebSocket moves use `GET /api/v1/rooms/{roomId}/seat-stream`.
- Seat changes are serialized and committed by one Durable Object per room. D1 is not read or written for each WebSocket move.
- Agora publisher privilege is issued only when the Durable Object confirms that the authenticated user owns a seat; the client renews the token and toggles publication without leaving the channel.
- CORS allowlist for local development and the initial Pages hostname; additional deployed origins are configured with `ALLOWED_ORIGINS`.
- D1 migrations retain account, session, profile, moderation and room metadata records.
- Private messaging uses authenticated D1 conversations, member-scoped direct/group threads, bounded message history, and server-side send throttling. The Flutter messages tab searches active users and groups the signed-in user belongs to; conversation screens refresh messages every five seconds.

See [ROOM_SEATS_PROTOCOL.md](./ROOM_SEATS_PROTOCOL.md) for the WebSocket JSON contract and latency test procedure.

## Cloudflare setup (one-time)
1. The D1 database `happy-live-db` has already been created in the Cloudflare account in APAC, and the initial schema has been applied and verified. Its database ID is already in `wrangler.toml`.
2. Enable R2 Object Storage in the Cloudflare dashboard. The account currently returns an R2-not-enabled response, so the `happy-live-media` bucket cannot be created yet.
3. After R2 is enabled, create an R2 bucket named `happy-live-media`.
4. Install dependencies in this directory with `npm install`.
5. Apply the checked-in migration locally first, then remotely only after reviewing the target database. The schema has already been applied directly to the remote D1 database; the checked-in migration is idempotent and can safely register the same initial schema with Wrangler.
   - `npm run db:local`
   - `npm run db:remote`
6. Run `npm run typecheck` and `npm run dev`.
7. Deploy only after local checks pass with `npm run deploy`.

Do not deploy while the D1 ID is a placeholder. Never commit API tokens, email-provider credentials, Agora certificates, or other secrets. Add secrets with Wrangler's secret management or the Cloudflare dashboard.

## Local development
The project uses Wrangler's local D1 emulator. The R2 binding can be emulated locally by Wrangler. Keep real user data out of local fixtures and source control.


## Deploying realtime microphone seats

After pulling the latest `main` branch, deploy the Worker from this directory:

```bash
cd backend/worker
npm ci
npm run typecheck
npm run deploy
```

Wrangler applies the `v2-room-seats` Durable Object migration and binds `ROOM_SEATS`. Do not test the new Flutter socket against the old Worker version: the deployed Worker must expose `/api/v1/rooms/{roomId}/seat-stream` and the `RoomSeatsHub` class first.
